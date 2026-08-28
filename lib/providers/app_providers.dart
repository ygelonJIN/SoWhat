import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';
import '../repositories/drift_app_repository.dart';
import '../repositories/memory_app_repository.dart';
import '../services/ai_client.dart';
import '../services/analysis_service.dart';
import '../services/memory_generation_service.dart';
import '../services/prompt_service.dart';

// 当前使用 drift 持久化仓库；MemoryAppRepository 保留为测试/参考。
// 如需切回内存仓库（调试用），改用 MemoryAppRepository()。

// ─── 仓库 ─────────────────────────────────────────────────────────────────

final appRepositoryProvider = Provider<AppRepository>((ref) {
  final repository = DriftAppRepository();
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

final battleStateProvider =
    StreamProvider.family<BattleState, ({String conversationId, BattleView view})>(
  (ref, key) => ref
      .watch(appRepositoryProvider)
      .watchBattleState(key.conversationId, key.view),
);

// ─── 状态 ──────────────────────────────────────────────────────────────────

final selectedBattleViewProvider = StateProvider<BattleView>((ref) {
  return BattleView.love;
});

final isAnalyzingProvider = StateProvider<bool>((ref) {
  return false;
});

/// 调试：聊天框实时显示当前正在执行的动作（测试用，后续可整体移除）。
final debugStatusProvider = StateProvider<String>((ref) => '');

// ─── 思考过程 ──────────────────────────────────────────────────────────────

final thinkingStatusProvider = StateProvider<ThinkingStatus>((ref) {
  return ThinkingStatus.idle;
});

final thinkingContentProvider = StateProvider<String>((ref) => '');

final thinkingStartedAtProvider = StateProvider<DateTime?>((ref) => null);

final thinkingExpandedProvider = StateProvider<bool>((ref) => false);

// ─── 操作 ──────────────────────────────────────────────────────────────────

final repositoryActionsProvider = Provider<AppRepositoryActions>((ref) {
  return AppRepositoryActions(
    repository: ref.watch(appRepositoryProvider),
    ref: ref,
  );
});

class AppRepositoryActions {
  AppRepositoryActions({required this.repository, required this.ref});

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

  /// 标记一批对话已完成长期记忆写入（每个对话只允许一次）。
  Future<void> finalizeConversationsForMemory(List<String> conversationIds) =>
      repository.finalizeConversationsForMemory(conversationIds);

  /// 把一批分析卡片标记为已被「更新记忆」消化。
  Future<void> markAnalysesProcessed(List<String> analysisIds) =>
      repository.markAnalysesProcessed(analysisIds);

  final Map<String, Completer<void>> _analysisCancellations = {};
  final Map<String, String> _activeAnalysisKeys = {};
  String _activeViewKey = '';

  /// 取消当前进行中的分析（切换对话时调用）。
  void cancelCurrentAnalysis() {
    for (final completer in _analysisCancellations.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _analysisCancellations.clear();
    _activeAnalysisKeys.clear();
    _activeViewKey = '';
    ref.read(isAnalyzingProvider.notifier).state = false;
    ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.idle;
    ref.read(thinkingContentProvider.notifier).state = '';
    ref.read(thinkingStartedAtProvider.notifier).state = null;
    ref.read(thinkingExpandedProvider.notifier).state = false;
    ref.read(debugStatusProvider.notifier).state = '';
  }

  /// 切换到其他模式时，把思考面板切到该模式当前分析状态（若无则复位）。
  void syncThinkingToView(String conversationId, BattleView view) {
    final key = '$conversationId:${view.name}';
    if (key == _activeViewKey) return;
    _activeViewKey = key;
    final activeKey = _activeAnalysisKeys[key];
    final activeCancellation = activeKey == null
        ? null
        : _analysisCancellations[activeKey];
    if (activeCancellation != null && !activeCancellation.isCompleted) {
      ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.thinking;
      ref.read(thinkingExpandedProvider.notifier).state = true;
    } else {
      ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.idle;
      ref.read(thinkingContentProvider.notifier).state = '';
      ref.read(thinkingStartedAtProvider.notifier).state = null;
      ref.read(thinkingExpandedProvider.notifier).state = false;
    }
  }

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

  Future<void> runAnalysis(String conversationId, {String turnId = ''}) async {
    final messages = await repository.watchMessages(conversationId).first;
    if (messages.isEmpty) return;

    final effectiveTurnId = turnId.isNotEmpty
        ? turnId
        : DateTime.now().millisecondsSinceEpoch.toString();
    final view = ref.read(selectedBattleViewProvider);
    final viewKey = '$conversationId:${view.name}:$effectiveTurnId';

    ref.read(isAnalyzingProvider.notifier).state = true;
    ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.thinking;
    ref.read(thinkingContentProvider.notifier).state = '';
    ref.read(thinkingStartedAtProvider.notifier).state = DateTime.now();
    ref.read(thinkingExpandedProvider.notifier).state = true;

    final cancelCompleter = Completer<void>();
    _analysisCancellations[viewKey] = cancelCompleter;
    _activeAnalysisKeys['$conversationId:${view.name}'] = viewKey;
    _activeViewKey = '$conversationId:${view.name}';

    try {
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
        onDebug: (message) {
          if (!cancelCompleter.isCompleted) {
            ref.read(debugStatusProvider.notifier).state = message;
          }
        },
        onThinking: (content) {
          if (!cancelCompleter.isCompleted) {
            ref.read(thinkingContentProvider.notifier).state = content;
          }
        },
      );
      if (cancelCompleter.isCompleted) return;
      ref.read(debugStatusProvider.notifier).state =
          '分析完成：${analysis.cards.length} 张卡片';

      final savedAnalysis = analysis.turnId.isEmpty
          ? Analysis(
              id: analysis.id,
              conversationId: analysis.conversationId,
              view: analysis.view,
              channel: analysis.channel,
              modelName: analysis.modelName,
              content: analysis.content,
              cards: analysis.cards,
              createdAt: analysis.createdAt,
              tokenCount: analysis.tokenCount,
              duration: analysis.duration,
              turnId: effectiveTurnId,
              memoryProcessedAt: analysis.memoryProcessedAt,
            )
          : analysis;
      await repository.saveAnalysis(savedAnalysis);
      if (cancelCompleter.isCompleted) return;

      final cards = savedAnalysis.cards.map((c) {
        return BattleCard(
          title: c.title,
          conclusion: c.conclusion,
          evidence: c.evidence ?? '',
          speculation: c.speculation,
        );
      }).toList();
      await repository.applyAnalysisToBattle(
        analysis: savedAnalysis,
        cards: cards,
        headline: _headlineFor(view, cards),
      );
      if (cancelCompleter.isCompleted) return;
      ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.done;
      ref.read(thinkingExpandedProvider.notifier).state = false;
    } catch (_) {
      if (!cancelCompleter.isCompleted) {
        ref.read(thinkingStatusProvider.notifier).state = ThinkingStatus.done;
        ref.read(thinkingExpandedProvider.notifier).state = false;
        rethrow;
      }
    } finally {
      _analysisCancellations.remove(viewKey);
      if (_activeAnalysisKeys['$conversationId:${view.name}'] == viewKey) {
        _activeAnalysisKeys.remove('$conversationId:${view.name}');
      }
      if (_analysisCancellations.isEmpty) {
        ref.read(isAnalyzingProvider.notifier).state = false;
      }
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