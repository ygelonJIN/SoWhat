import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';
import '../repositories/memory_app_repository.dart';
import '../services/analysis_service.dart';
import '../services/memory_service.dart';
import '../services/prompt_service.dart';

// 当前仍使用内存仓库，后续切换到本地数据库持久化。

// ─── 仓库 ─────────────────────────────────────────────────────────────────

final appRepositoryProvider = Provider<AppRepository>((ref) {
  final repository = MemoryAppRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

// ─── 服务 ─────────────────────────────────────────────────────────────────

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return const AnalysisService();
});

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return const MemoryService();
});

final promptServiceProvider = Provider<PromptService>((ref) {
  return const PromptService();
});

// ─── 数据流 ────────────────────────────────────────────────────────────────

final casesProvider = StreamProvider<List<Case>>((ref) {
  return ref.watch(appRepositoryProvider).watchCases();
});

final conversationMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, conversationId) {
      return ref.watch(appRepositoryProvider).watchMessages(conversationId);
    });

final conversationAnalysesProvider =
    StreamProvider.family<List<Analysis>, String>((ref, conversationId) {
      return ref.watch(appRepositoryProvider).watchAnalyses(conversationId);
    });

final memoryProfileProvider = StreamProvider<MemoryProfile>((ref) {
  return ref.watch(appRepositoryProvider).watchMemory();
});

final conversationStartedAtProvider = StreamProvider<DateTime>((ref) {
  return ref.watch(appRepositoryProvider).watchConversationStartedAt();
});

final battleStateProvider = StreamProvider<BattleState>((ref) {
  return ref.watch(appRepositoryProvider).watchBattleState();
});

// ─── 状态 ──────────────────────────────────────────────────────────────────

final selectedBattleViewProvider = StateProvider<BattleView>((ref) {
  return BattleView.love;
});

final isAnalyzingProvider = StateProvider<bool>((ref) {
  return false;
});

final userIdentityProvider = StateProvider<bool>((ref) {
  // false = 未确认"哪边是我"，true = 已确认
  return false;
});

// ─── 操作 ──────────────────────────────────────────────────────────────────

final repositoryActionsProvider = Provider<AppRepositoryActions>((ref) {
  return AppRepositoryActions(
    repository: ref.watch(appRepositoryProvider),
    ref: ref,
  );
});

class AppRepositoryActions {
  const AppRepositoryActions({required this.repository, required this.ref});

  final AppRepository repository;
  final Ref ref;

  Future<void> setBattleView(BattleView view) => repository.setBattleView(view);

  Future<void> addMessage({
    required String conversationId,
    required Party party,
    required String content,
    MessageType type = MessageType.text,
    String? assetPath,
  }) async {
    final sequence = await repository.nextMessageSequence(conversationId);
    await repository.addMessage(
      Message(
        conversationId: conversationId,
        sequence: sequence,
        party: party,
        type: type,
        content: content,
        assetPath: assetPath,
      ),
    );
  }

  /// 运行一轮分析（占位实现：基于当前对话 + 记忆 + 视角生成战场卡片）。
  Future<void> deleteMessage({
    required String conversationId,
    required int sequence,
  }) => repository.deleteMessage(conversationId, sequence);

  Future<void> runAnalysis(String conversationId) async {
    if (ref.read(isAnalyzingProvider)) return;

    final messages = await repository.watchMessages(conversationId).first;
    if (messages.isEmpty) return;

    ref.read(isAnalyzingProvider.notifier).state = true;
    try {
      final view = ref.read(selectedBattleViewProvider);
      final memory = await repository.watchMemory().first;
      final conversation = const PromptService().formatConversation(messages);

      final analysisService = ref.read(analysisServiceProvider);
      final memoryService = ref.read(memoryServiceProvider);

      final analysis = await analysisService.analyze(
        conversationId: conversationId,
        view: view,
        channel: AiChannel.promptExport,
        memory: memory,
        conversation: conversation,
      );

      await repository.saveAnalysis(analysis);

      final cards = analysis.cards.map((c) {
        return BattleCard(
          title: c.title,
          conclusion: c.conclusion,
          evidence: c.evidence ?? '',
          speculation: c.speculation,
        );
      }).toList();
      await repository.applyAnalysisToBattle(
        analysis: analysis,
        cards: cards,
        headline: _headlineFor(view, cards),
      );

      final entries = memoryService.extractEntries(
        messages: messages,
        view: view,
        analysisText: analysis.content,
      );
      final updatedMemory = memoryService.mergeEntries(memory, entries);
      await repository.saveMemory(updatedMemory);
    } finally {
      ref.read(isAnalyzingProvider.notifier).state = false;
    }
  }

  String _headlineFor(BattleView view, List<BattleCard> cards) {
    final summary = cards.isNotEmpty ? '分析了 ${cards.length} 个维度' : '暂无分析结果';
    switch (view) {
      case BattleView.love:
        return '争爱视角 — $summary';
      case BattleView.right:
        return '争对错视角 — $summary';
      case BattleView.win:
        return '争输赢视角 — $summary';
    }
  }
}