import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';
import '../repositories/drift_app_repository.dart';
import '../repositories/memory_app_repository.dart';
import '../services/ai_client.dart';
import '../services/analysis_service.dart';
import '../services/memory_generation_service.dart';
import '../services/prompt_service.dart';

/// MiMo-V2.5 对单张 Base64 图片的官方限制。
///
/// 官方限制针对单张图片的 Base64 字符串，不是图片张数；因此不再设置
/// 人为的 9/10 张上限。多张图片是否能一次发送，还取决于请求体和模型上下文限制。
const int kMaxBase64ImageBytes = 50 * 1024 * 1024;

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

final assetsProvider = StreamProvider<List<Asset>>((ref) {
  return ref.watch(appRepositoryProvider).watchAssets();
});

/// 当前打开的对话（设置页点击聊天记录 / 新建对话时切换）。
/// 初始为 null：首帧先由 [AppRepositoryActions.ensureConversation] 解析出
/// 最近一段对话（空白对话只作为「当前对话」短暂存在，切换后即被清理）。
final selectedConversationIdProvider = StateProvider<String?>((ref) {
  return null;
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

/// 当前视图是否有分析任务；状态按「对话 + 模式」隔离，允许并行分析。
final isAnalyzingProvider = StateProvider.family<bool, String>((ref, key) => false);

/// 调试：聊天框实时显示当前正在执行的动作（测试用，后续可整体移除）。
final debugStatusProvider = StateProvider<String>((ref) => '');

// ─── 思考过程 ──────────────────────────────────────────────────────────────

/// 思考状态按「对话 + 模式」隔离，切换模式不会覆盖另一个模式的思考框。
final thinkingStatusProvider =
    StateProvider.family<ThinkingStatus, String>((ref, key) {
  return ThinkingStatus.idle;
});

final thinkingContentProvider = StateProvider.family<String, String>((ref, key) => '');

final thinkingStartedAtProvider =
    StateProvider.family<DateTime?, String>((ref, key) => null);

final thinkingExpandedProvider =
    StateProvider.family<bool, String>((ref, key) => false);

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

  /// 确保当前始终有一个可编辑的对话。
  ///
  /// 启动时（selected 为空）总是新建一段「临时空白对话」作为当前对话：
  /// 可正常编辑发送；但没有消息时不进入历史记录，切换出去即被清理。
  /// 仅当 selected 已指向存在的对话时（用户已切换过）复用。
  Future<String> ensureConversation() async {
    final selected = ref.read(selectedConversationIdProvider);
    if (selected != null) {
      final cases = await repository.watchCases().first;
      if (cases.any((c) => c.id == selected)) return selected;
      ref.read(selectedConversationIdProvider.notifier).state = null;
    }
    final fresh = await createConversation();
    ref.read(selectedConversationIdProvider.notifier).state = fresh.id;
    return fresh.id;
  }

  /// 清理历史中残留的没有任何消息的空白对话（保留 [keepConversationId]）。
  /// 启动时兜底调用，保证空白草稿只在「作为当前对话时」短暂存在。
  Future<void> cleanupStaleEmptyConversations({
    required String keepConversationId,
  }) async {
    final cases = await repository.watchCases().first;
    for (final caseItem in cases) {
      if (caseItem.id == keepConversationId) continue;
      await repository.cleanupEmptyConversation(caseItem.id);
    }
  }

  Future<bool> cleanupEmptyConversation(String conversationId) =>
      repository.cleanupEmptyConversation(conversationId);


  Future<Case> setConversationPinned(String conversationId, bool pinned) =>
      repository.setCasePinned(conversationId, pinned);

  Future<Case> renameConversation(String conversationId, String title) =>
      repository.renameCase(conversationId, title);

  /// 保存 BYOK 接入配置。
  Future<void> saveAiConfig(AiConfig config) => repository.saveAiConfig(config);

  /// 删除对话；[deleteMemory] 为 true 时连同引用该对话的记忆一并删除。
  Future<void> deleteEmptyConversation(String conversationId) =>
      repository.deleteEmptyConversation(conversationId);

  Future<void> deleteConversation(
    String conversationId, {
    bool deleteMemory = false,
  }) async {
    await repository.deleteCase(conversationId);
    if (deleteMemory) {
      await repository.deleteMemoryForConversation(conversationId);
    }
    // 删的是当前对话时，清空 selected 让后续 ensureConversation 重新选一个。
    if (ref.read(selectedConversationIdProvider) == conversationId) {
      ref.read(selectedConversationIdProvider.notifier).state = null;
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

  String _stateKey(String conversationId, BattleView view) =>
      '$conversationId:${view.name}';

  void _setThinkingState(
    String conversationId,
    BattleView view, {
    ThinkingStatus? status,
    String? content,
    DateTime? startedAt,
    bool? expanded,
  }) {
    final key = _stateKey(conversationId, view);
    if (status != null) {
      ref.read(thinkingStatusProvider(key).notifier).state = status;
    }
    if (content != null) {
      ref.read(thinkingContentProvider(key).notifier).state = content;
    }
    if (startedAt != null || status == ThinkingStatus.idle) {
      ref.read(thinkingStartedAtProvider(key).notifier).state = startedAt;
    }
    if (expanded != null) {
      ref.read(thinkingExpandedProvider(key).notifier).state = expanded;
    }
  }

  /// 取消指定视角的分析；模式切换不会调用此方法，因此其他视角可继续运行。
  void cancelAnalysis(String conversationId, BattleView view) {
    final key = _stateKey(conversationId, view);
    final activeKey = _activeAnalysisKeys[key];
    if (activeKey == null) return;
    final completer = _analysisCancellations[activeKey];
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// 兼容旧调用：仅取消当前选中对话的当前视角，不影响其他并行任务。
  void cancelCurrentAnalysis() {
    final conversationId = ref.read(selectedConversationIdProvider);
    if (conversationId == null) return;
    cancelAnalysis(conversationId, ref.read(selectedBattleViewProvider));
  }

  bool isAnalysisActive(String conversationId, BattleView view) {
    final activeKey = _activeAnalysisKeys[_stateKey(conversationId, view)];
    final cancellation = activeKey == null
        ? null
        : _analysisCancellations[activeKey];
    return cancellation != null && !cancellation.isCompleted;
  }

  /// 切换到其他模式时，恢复该模式独立的思考状态。
  Future<void> syncThinkingToView(String conversationId, BattleView view) async {
    final key = _stateKey(conversationId, view);
    _activeViewKey = key;
    final activeKey = _activeAnalysisKeys[key];
    final activeCancellation = activeKey == null
        ? null
        : _analysisCancellations[activeKey];
    if (activeCancellation != null && !activeCancellation.isCompleted) {
      _setThinkingState(
        conversationId,
        view,
        status: ThinkingStatus.thinking,
        expanded: true,
      );
      return;
    }

    final battleState = await repository.watchBattleState(conversationId, view).first;
    if (battleState != null &&
        (battleState.thinkingActive ||
            (battleState.thinkingContent?.isNotEmpty ?? false))) {
      _setThinkingState(
        conversationId,
        view,
        status: battleState.thinkingActive
            ? ThinkingStatus.thinking
            : ThinkingStatus.done,
        content: battleState.thinkingContent ?? '',
        startedAt: battleState.thinkingStartedAt,
        expanded: battleState.thinkingActive,
      );
    } else {
      _setThinkingState(
        conversationId,
        view,
        status: ThinkingStatus.idle,
        content: '',
        startedAt: null,
        expanded: false,
      );
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

  Future<int> runAnalysis(
    String conversationId, {
    String turnId = '',
    required BattleView analysisView,
  }) async {
    final messages = await repository.watchMessages(conversationId).first;
    if (messages.isEmpty) return 0;

    final effectiveTurnId = turnId.isNotEmpty
        ? turnId
        : DateTime.now().millisecondsSinceEpoch.toString();
    final view = analysisView;
    final stateKey = _stateKey(conversationId, view);
    final viewKey = '$stateKey:$effectiveTurnId';

    final thinkingStartTime = DateTime.now();
    ref.read(isAnalyzingProvider(stateKey).notifier).state = true;
    _setThinkingState(
      conversationId,
      view,
      status: ThinkingStatus.thinking,
      content: '',
      startedAt: thinkingStartTime,
      expanded: true,
    );
    unawaited(repository.saveThinkingState(
      conversationId: conversationId,
      view: view,
      thinkingContent: '',
      thinkingStartedAt: thinkingStartTime,
      thinkingActive: true,
    ));

    final cancelCompleter = Completer<void>();
    _analysisCancellations[viewKey] = cancelCompleter;
    _activeAnalysisKeys['$conversationId:${view.name}'] = viewKey;
    _activeViewKey = '$conversationId:${view.name}';

    // 思考过程持久化节流：每 3 秒写一次 DB，避免高频写入。
    var lastPersistAt = DateTime.now();
    const persistInterval = Duration(seconds: 3);
    var skippedImages = 0;

    try {
      final memory = await repository.watchMemory().first;
      final config = await repository.watchAiConfig().first;
      final conversation = const PromptService().formatConversation(messages);
      // 图片可能已被移动/删除（如重装后沙盒路径变化、资产管理里删除），
      // 失效图片跳过不阻塞整轮分析，避免「图片文件不存在」中断。
      final imageFiles = <({MessageImage image, int sizeBytes})>[];
      for (final message in messages) {
        if (!message.isImageType || message.assetPath == null) continue;
        final file = File(message.assetPath!);
        if (!await file.exists()) {
          skippedImages++;
          continue;
        }
        final size = await file.length();
        imageFiles.add((image: MessageImage(message.assetPath!), sizeBytes: size));
      }
      final images = [for (final entry in imageFiles) entry.image];
      // Base64 体积 = ceil(原始字节 / 3) * 4，用于估算请求体大小。
      final payloadBytes = imageFiles.fold<int>(
        0,
        (sum, entry) => sum + (entry.sizeBytes + 2) ~/ 3 * 4,
      );
      final payloadMb = (payloadBytes / (1024 * 1024)).toStringAsFixed(1);
      if (skippedImages > 0) {
        ref.read(debugStatusProvider.notifier).state =
            '已跳过 $skippedImages 张失效图片';
      }
      ref.read(debugStatusProvider.notifier).state =
          '已准备 ${images.length} 张图片（Base64 约 $payloadMb MB）参与本轮分析';

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
            ref.read(thinkingContentProvider(stateKey).notifier).state = content;
            // 定期持久化思考过程到 DB。
            final now = DateTime.now();
            if (now.difference(lastPersistAt) >= persistInterval) {
              lastPersistAt = now;
              repository.saveThinkingState(
                conversationId: conversationId,
                view: view,
                thinkingContent: content,
                thinkingStartedAt: thinkingStartTime,
                thinkingActive: true,
              );
            }
          }
        },
      );
      if (cancelCompleter.isCompleted) return skippedImages;
      if (_activeViewKey == stateKey) {
        ref.read(debugStatusProvider.notifier).state =
            '分析完成：${analysis.cards.length} 张卡片';
      }

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
      if (cancelCompleter.isCompleted) return skippedImages;

      final cards = savedAnalysis.cards.map((c) {
        return BattleCard(
          title: c.title,
          conclusion: c.conclusion,
          evidence: c.evidence ?? '',
          speculation: c.speculation,
        );
      }).toList();
      // 分析完成：保存卡片 + 思考过程最终状态。
      final finalThinkingContent = ref.read(thinkingContentProvider(stateKey));
      await repository.applyAnalysisToBattle(
        analysis: savedAnalysis,
        cards: cards,
        headline: _headlineFor(view, cards),
        thinkingContent: finalThinkingContent.isNotEmpty ? finalThinkingContent : null,
        thinkingStartedAt: thinkingStartTime,
        thinkingFinishedAt: DateTime.now(),
        thinkingActive: false,
      );
      if (cancelCompleter.isCompleted) return skippedImages;
      _setThinkingState(
        conversationId,
        view,
        status: ThinkingStatus.done,
        expanded: false,
      );
      ref.read(isAnalyzingProvider(stateKey).notifier).state = false;
    } catch (_) {
      if (!cancelCompleter.isCompleted) {
        // 分析失败：仍保存思考过程，方便用户回看排查。
        final finalThinkingContent = ref.read(thinkingContentProvider(stateKey));
        repository.saveThinkingState(
          conversationId: conversationId,
          view: view,
          thinkingContent: finalThinkingContent.isNotEmpty ? finalThinkingContent : null,
          thinkingStartedAt: thinkingStartTime,
          thinkingFinishedAt: DateTime.now(),
          thinkingActive: false,
        );
        _setThinkingState(
          conversationId,
          view,
          status: ThinkingStatus.done,
          expanded: false,
        );
        ref.read(isAnalyzingProvider(stateKey).notifier).state = false;
        if (_activeViewKey == stateKey) rethrow;
      }
    } finally {
      _analysisCancellations.remove(viewKey);
      if (_activeAnalysisKeys['$conversationId:${view.name}'] == viewKey) {
        _activeAnalysisKeys.remove('$conversationId:${view.name}');
      }
      ref.read(isAnalyzingProvider(stateKey).notifier).state = false;
    }
    return skippedImages;
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