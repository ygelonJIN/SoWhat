import 'dart:async';

import '../models/models.dart';
import 'app_repository.dart';

/// 内存版仓库：用于当前可运行原型，后续替换为 drift + SQLCipher。
class MemoryAppRepository implements AppRepository {
  final List<Case> _cases = [];
  final Map<String, List<Message>> _messagesByConversation = {};
  final Map<String, List<Analysis>> _analysesByConversation = {};
  final Map<String, StreamController<BattleState>> _battleControllers = {};
  final Map<String, BattleState> _battleStates = {};
  late final StreamController<List<Case>> _caseController =
      StreamController<List<Case>>.broadcast(onListen: _emitCases);
  late final StreamController<MemoryProfile> _memoryController =
      StreamController<MemoryProfile>.broadcast(onListen: _emitMemory);
  late final StreamController<AiConfig> _aiConfigController =
      StreamController<AiConfig>.broadcast();
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamController<List<Analysis>>> _analysisControllers = {};

  MemoryProfile _memory = MemoryProfile.empty();
  AiConfig _aiConfig = const AiConfig();
  final List<Asset> _assets = [];
  final StreamController<List<Asset>> _assetController =
      StreamController<List<Asset>>.broadcast();

  MemoryAppRepository();

  @override
  Stream<List<Case>> watchCases() async* {
    yield List.unmodifiable(_cases);
    yield* _caseController.stream;
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
    yield List.unmodifiable(
      _messagesByConversation[conversationId] ?? const [],
    );
    yield* controller.stream;
  }

  @override
  Stream<List<Analysis>> watchAnalyses(String conversationId) async* {
    final controller = _analysisControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Analysis>>.broadcast(),
    );
    yield List.unmodifiable(
      _analysesByConversation[conversationId] ?? const [],
    );
    yield* controller.stream;
  }

  @override
  Stream<BattleState> watchBattleState(
    String conversationId,
    BattleView view,
  ) async* {
    final controller = _battleControllers.putIfAbsent(
      conversationId,
      () => StreamController<BattleState>.broadcast(),
    );
    final state = _battleStates[conversationId] ?? BattleState.initial(view);
    yield state.view == view ? state : state.copyWith(view: view);
    yield* controller.stream;
  }

  @override
  Stream<DateTime> watchConversationStartedAt(String conversationId) async* {
    yield* watchCases().map((cases) {
      for (final caseItem in cases) {
        if (caseItem.id == conversationId) return caseItem.createdAt;
      }
      return DateTime.now();
    });
  }

  @override
  Stream<MemoryProfile> watchMemory() async* {
    yield _memory;
    yield* _memoryController.stream;
  }

  @override
  Stream<List<Asset>> watchAssets() async* {
    yield List.unmodifiable(_assets);
    yield* _assetController.stream;
  }

  @override
  Future<Asset?> assetByPath(String path) async {
    for (final asset in _assets) {
      if (asset.path == path) return asset;
    }
    return null;
  }

  @override
  Future<void> saveAsset(Asset asset) async {
    final index = _assets.indexWhere(
      (item) => item.id == asset.id || item.path == asset.path,
    );
    if (index >= 0) {
      _assets[index] = asset;
    } else {
      _assets.add(asset);
    }
    _assetController.add(List.unmodifiable(_assets));
  }

  @override
  Future<void> renameAsset(String assetId, String title) async {
    final index = _assets.indexWhere((asset) => asset.id == assetId);
    if (index < 0) return;
    _assets[index] = _assets[index].copyWith(title: title);
    _assetController.add(List.unmodifiable(_assets));
  }

  @override
  Future<void> deleteAssets(List<String> assetIds) async {
    _assets.removeWhere((asset) => assetIds.contains(asset.id));
    _assetController.add(List.unmodifiable(_assets));
  }

  @override
  Stream<AiConfig> watchAiConfig() async* {
    yield _aiConfig;
    yield* _aiConfigController.stream;
  }

  void _emitCases() {
    if (!_caseController.isClosed) {
      _caseController.add(List.unmodifiable(_cases));
    }
  }

  void _emitMessages(String conversationId) {
    final controller = _messageControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(
        List.unmodifiable(_messagesByConversation[conversationId] ?? const []),
      );
    }
  }

  void _emitAnalyses(String conversationId) {
    final controller = _analysisControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(
        List.unmodifiable(_analysesByConversation[conversationId] ?? const []),
      );
    }
  }

  void _emitBattle(String conversationId) {
    final controller = _battleControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(_battleStates[conversationId] ?? BattleState.initial());
    }
  }

  void _emitMemory() {
    if (!_memoryController.isClosed) _memoryController.add(_memory);
  }

  @override
  Future<Case> upsertCase(Case caseItem) async {
    final index = _cases.indexWhere((item) => item.id == caseItem.id);
    if (index >= 0) {
      _cases[index] = caseItem;
    } else {
      _cases.add(caseItem);
    }
    _emitCases();
    return caseItem;
  }

  @override
  Future<Case> setCasePinned(String caseId, bool pinned) async {
    final index = _cases.indexWhere((item) => item.id == caseId);
    if (index < 0) {
      throw StateError('未找到对话 $caseId');
    }
    final updated = _cases[index].copyWith(
      pinnedAt: pinned ? DateTime.now() : null,
    );
    _cases[index] = updated;
    _emitCases();
    return updated;
  }

  @override
  Future<Case> renameCase(String caseId, String title) async {
    final index = _cases.indexWhere((item) => item.id == caseId);
    if (index < 0) {
      throw StateError('未找到对话 $caseId');
    }
    final updated = _cases[index].copyWith(title: title);
    _cases[index] = updated;
    _emitCases();
    return updated;
  }

  @override
  Future<Case> updateCaseCreatedAt(String caseId, DateTime createdAt) async {
    final index = _cases.indexWhere((item) => item.id == caseId);
    if (index < 0) {
      throw StateError('未找到对话 $caseId');
    }
    final updated = _cases[index].copyWith(createdAt: createdAt);
    _cases[index] = updated;
    _emitCases();
    return updated;
  }

  @override
  Future<void> deleteEmptyConversation(String conversationId) async {
    final messages =
        _messagesByConversation[conversationId] ?? const <Message>[];
    if (messages.isEmpty) {
      _cases.removeWhere((item) => item.id == conversationId);
      _messagesByConversation.remove(conversationId);
      _analysesByConversation.remove(conversationId);
      _emitCases();
    }
  }

  @override
  Future<bool> cleanupEmptyConversation(String conversationId) async {
    final messages =
        _messagesByConversation[conversationId] ?? const <Message>[];
    if (messages.isEmpty) {
      await deleteEmptyConversation(conversationId);
      return false;
    }
    return true;
  }

  @override
  Future<void> deleteCase(String conversationId) async {
    _cases.removeWhere((item) => item.id == conversationId);
    _messagesByConversation.remove(conversationId);
    _analysesByConversation.remove(conversationId);
    _emitCases();
  }

  @override
  Future<int> nextMessageSequence(String conversationId) async {
    return (_messagesByConversation[conversationId]?.length ?? 0) + 1;
  }

  @override
  Future<void> addMessage(Message message) async {
    final list = _messagesByConversation.putIfAbsent(
      message.conversationId,
      () => [],
    );
    list.add(message);
    _emitMessages(message.conversationId);
  }

  @override
  Future<void> deleteMessage(String conversationId, int sequence) async {
    final messages = _messagesByConversation[conversationId];
    if (messages == null) return;
    messages.removeWhere((message) => message.sequence == sequence);
    _emitMessages(conversationId);
  }

  @override
  Future<void> saveAnalysis(Analysis analysis) async {
    final list = _analysesByConversation.putIfAbsent(
      analysis.conversationId,
      () => [],
    );
    list.add(analysis);
    _emitAnalyses(analysis.conversationId);
  }

  @override
  Future<void> importCaseData({
    required Case caseItem,
    required List<Message> messages,
    required List<Analysis> analyses,
  }) async {
    // 内存仓库为测试/参考实现：按顺序写入，语义与 Drift 事务版一致。
    _cases.removeWhere((c) => c.id == caseItem.id);
    _cases.add(caseItem);
    _messagesByConversation[caseItem.id] = List.of(messages);
    _analysesByConversation[caseItem.id] = List.of(analyses);
    for (final analysis in analyses) {
      _battleStates.putIfAbsent(
        caseItem.id,
        () => BattleState.initial(analysis.view),
      );
    }
    _emitCases();
    _emitMessages(caseItem.id);
    _emitAnalyses(caseItem.id);
  }

  @override
  Future<void> saveMemory(MemoryProfile memory) async {
    _memory = memory;
    _emitMemory();
  }

  @override
  Future<void> saveMemoryWithProcessing({
    required MemoryProfile memory,
    required List<String> analysisIds,
    required List<String> conversationIds,
  }) async {
    // 内存仓库为测试/参考实现：按顺序执行，语义与 Drift 事务版一致。
    _memory = memory;
    await markAnalysesProcessed(analysisIds);
    await finalizeConversationsForMemory(conversationIds);
    _emitMemory();
  }

  @override
  Future<void> saveAiConfig(AiConfig config) async {
    _aiConfig = config;
    if (!_aiConfigController.isClosed) {
      _aiConfigController.add(_aiConfig);
    }
  }

  @override
  Future<void> wipeUserData() async {
    _cases.clear();
    _messagesByConversation.clear();
    _analysesByConversation.clear();
    _battleStates.clear();
    _memory = MemoryProfile.empty();
    _assets.clear();
    for (final controller in _messageControllers.values.toList()) {
      controller.add(const []);
    }
    for (final controller in _analysisControllers.values.toList()) {
      controller.add(const []);
    }
    for (final controller in _battleControllers.values.toList()) {
      controller.add(BattleState.initial(BattleView.love));
    }
    _emitCases();
    _emitMemory();
    if (!_assetController.isClosed) {
      _assetController.add(const []);
    }
  }

  @override
  Future<void> clearUserData({
    bool conversations = false,
    bool analyses = false,
    bool memory = false,
    bool assets = false,
  }) async {
    if (conversations) {
      await wipeUserData();
      return;
    }
    if (analyses) {
      _analysesByConversation.clear();
      _battleStates.clear();
      for (final controller in _analysisControllers.values.toList()) {
        controller.add(const []);
      }
      for (final controller in _battleControllers.values.toList()) {
        controller.add(BattleState.initial(BattleView.love));
      }
    }
    if (memory) {
      _memory = MemoryProfile.empty();
      _emitMemory();
    }
    if (assets) {
      _assets.clear();
      if (!_assetController.isClosed) {
        _assetController.add(const []);
      }
    }
  }

  @override
  Future<void> deleteMemoryForConversation(String conversationId) async {
    final remaining = _memory.entries
        .where(
          (entry) =>
              !entry.sources.any((s) => s.conversationId == conversationId),
        )
        .toList();
    if (remaining.length == _memory.entries.length) return;
    await saveMemory(_memory.copyWith(entries: remaining));
  }

  @override
  Future<void> finalizeConversationsForMemory(
    List<String> conversationIds,
  ) async {
    for (final convId in conversationIds) {
      final index = _cases.indexWhere((item) => item.id == convId);
      if (index < 0) continue;
      final c = _cases[index];
      if (c.hasFinalizedMemory) continue;
      _cases[index] = c.copyWith(memoryFinalizedAt: DateTime.now());
    }
    _emitCases();
  }

  @override
  Future<void> markAnalysesProcessed(List<String> analysisIds) async {
    if (analysisIds.isEmpty) return;
    for (final list in _analysesByConversation.values) {
      for (var i = 0; i < list.length; i++) {
        final analysis = list[i];
        if (analysisIds.contains(analysis.id) &&
            analysis.memoryProcessedAt == null) {
          list[i] = _copyAnalysisProcessed(analysis);
        }
      }
    }
    for (final id in _analysesByConversation.keys.toList()) {
      _emitAnalyses(id);
    }
  }

  Analysis _copyAnalysisProcessed(Analysis analysis) {
    return Analysis(
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
      memoryProcessedAt: DateTime.now(),
    );
  }

  @override
  Future<void> setBattleView(String conversationId, BattleView view) async {
    final current = _battleStates[conversationId] ?? BattleState.initial(view);
    _battleStates[conversationId] = current.copyWith(
      view: view,
      headline: current.headline,
      cards: current.cards,
      updatedAt: DateTime.now(),
    );
    final index = _cases.indexWhere((item) => item.id == conversationId);
    if (index >= 0) {
      _cases[index] = _cases[index].copyWith(lastView: view);
      _emitCases();
    }
    _emitBattle(conversationId);
  }

  /// 分析完成后更新战场状态（维度卡片 + 战况小结 + 可视化指标）。
  @override
  Future<void> applyAnalysisToBattle({
    required Analysis analysis,
    required List<BattleCard> cards,
    String headline = '',
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
    String? summary,
  }) async {
    _battleStates[analysis.conversationId] = BattleState.initial(analysis.view)
        .copyWith(
          view: analysis.view,
          headline: headline.isEmpty ? _headlineFor(analysis.view) : headline,
          cards: cards,
          updatedAt: DateTime.now(),
          thinkingContent: thinkingContent,
          thinkingStartedAt: thinkingStartedAt,
          thinkingFinishedAt: thinkingFinishedAt,
          thinkingActive: thinkingActive,
          summary: summary ?? analysis.summary,
        );
    _emitBattle(analysis.conversationId);
  }

  @override
  Future<void> saveThinkingState({
    required String conversationId,
    required BattleView view,
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
  }) async {
    final current = _battleStates[conversationId] ?? BattleState.initial(view);
    _battleStates[conversationId] = current.copyWith(
      view: view,
      thinkingContent: thinkingContent,
      thinkingStartedAt: thinkingStartedAt,
      thinkingFinishedAt: thinkingFinishedAt,
      thinkingActive: thinkingActive,
      updatedAt: DateTime.now(),
    );
    _emitBattle(conversationId);
  }

  String _headlineFor(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '先看看这段对话里的在乎、需求，以及还有多少修复空间。';
      case BattleView.right:
        return '把事实和表达分开看，不急着给任何一方下结论。';
      case BattleView.win:
        return '看看谁暂时占了上风，以及这场胜负真正的代价。';
    }
  }

  @override
  void dispose() {
    _caseController.close();
    _memoryController.close();
    _aiConfigController.close();
    _assetController.close();
    for (final controller in _battleControllers.values) {
      controller.close();
    }
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    for (final controller in _analysisControllers.values) {
      controller.close();
    }
  }
}
