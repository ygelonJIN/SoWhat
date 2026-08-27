import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';
import '../repositories/memory_app_repository.dart';
import '../services/ai_client.dart';
import '../services/analysis_service.dart';
import '../services/memory_generation_service.dart';
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

final memoryGenerationServiceProvider =
    Provider<MemoryGenerationService>((ref) {
  return const MemoryGenerationService();
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

/// BYOK 接入配置（设置页「配置 API」写入，供分析 / 记忆生成读取）。
final aiConfigProvider = StreamProvider<AiConfig>((ref) {
  return ref.watch(appRepositoryProvider).watchAiConfig();
});

/// 当前打开的对话（设置页点击聊天记录 / 新建对话时切换）。
final selectedConversationIdProvider = StateProvider<String>((ref) {
  return MemoryAppRepository.currentConversationId;
});

final conversationStartedAtProvider =
    StreamProvider.family<DateTime, String>((ref, conversationId) {
  return ref.watch(appRepositoryProvider).watchConversationStartedAt(
    conversationId,
  );
});

final battleStateProvider = StreamProvider.family<BattleState, String>((
  ref,
  conversationId,
) {
  return ref.watch(appRepositoryProvider).watchBattleState(conversationId);
});

// ─── 状态 ──────────────────────────────────────────────────────────────────

final selectedBattleViewProvider = StateProvider<BattleView>((ref) {
  return BattleView.love;
});

final isAnalyzingProvider = StateProvider<bool>((ref) {
  return false;
});

/// 调试：聊天框实时显示当前正在执行的动作（测试用，后续可整体移除）。
final debugStatusProvider = StateProvider<String>((ref) => '');

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

  Future<void> setBattleView(String conversationId, BattleView view) =>
      repository.setBattleView(conversationId, view);

  /// 新建一段对话（未命名，界面按创建时间展示日期时间），返回新对话。
  Future<Case> createConversation() => repository.upsertCase(Case());

  Future<Case> setConversationPinned(String conversationId, bool pinned) =>
      repository.setCasePinned(conversationId, pinned);

  Future<Case> renameConversation(String conversationId, String title) =>
      repository.renameCase(conversationId, title);

  /// 保存 BYOK 接入配置。
  Future<void> saveAiConfig(AiConfig config) => repository.saveAiConfig(config);

  /// 删除对话；[deleteMemory] 为 true 时连同引用该对话的记忆一并删除。
  Future<void> deleteConversation(
    String conversationId, {
    bool deleteMemory = false,
  }) async {
    await repository.deleteCase(conversationId);
    if (deleteMemory) {
      await repository.deleteMemoryForConversation(conversationId);
    }
  }

  /// 把一批分析卡片标记为已被「更新记忆」消化。
  Future<void> markAnalysesProcessed(List<String> analysisIds) =>
      repository.markAnalysesProcessed(analysisIds);

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
      final config = await repository.watchAiConfig().first;
      final conversation = const PromptService().formatConversation(messages);
      final images = [
        for (final message in messages)
          if (message.isImageType && message.assetPath != null)
            MessageImage(message.assetPath!),
      ];

      final analysisService = ref.read(analysisServiceProvider);

      final analysis = await analysisService.analyze(
        conversationId: conversationId,
        view: view,
        channel: config.isConfigured
            ? AiChannel.byok
            : AiChannel.promptExport,
        memory: memory,
        conversation: conversation,
        config: config.isConfigured ? config : null,
        images: images,
        onDebug: (message) =>
            ref.read(debugStatusProvider.notifier).state = message,
      );
      ref.read(debugStatusProvider.notifier).state =
          '分析完成：${analysis.cards.length} 张卡片';

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