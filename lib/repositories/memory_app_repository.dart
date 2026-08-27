import 'dart:async';

import '../models/models.dart';
import 'app_repository.dart';

/// 内存版仓库：用于当前可运行原型，后续替换为 drift + SQLCipher。
class MemoryAppRepository implements AppRepository {
  static const currentConversationId = 'current-conversation';

  final List<Case> _cases = [];
  final Map<String, List<Message>> _messagesByConversation = {};
  final Map<String, List<Analysis>> _analysesByConversation = {};
  late final StreamController<List<Case>> _caseController =
      StreamController<List<Case>>.broadcast(onListen: _emitCases);
  late final StreamController<BattleState> _battleController =
      StreamController<BattleState>.broadcast(onListen: _emitBattle);
  late final StreamController<MemoryProfile> _memoryController =
      StreamController<MemoryProfile>.broadcast(onListen: _emitMemory);
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamController<List<Analysis>>> _analysisControllers = {};

  late final StreamController<DateTime> _conversationStartController =
      StreamController<DateTime>.broadcast(onListen: _emitConversationStart);

  BattleState _battleState = BattleState.initial();
  MemoryProfile _memory = MemoryProfile.empty();

  /// 本次对话开始的时间（创建对话时记录，之后保持不变）。
  DateTime _conversationStartedAt = DateTime.now();

  MemoryAppRepository() {
    seedDemoData();
    _seedCurrentConversation();
  }

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
  Stream<BattleState> watchBattleState() async* {
    yield _battleState;
    yield* _battleController.stream;
  }

  @override
  Stream<DateTime> watchConversationStartedAt() async* {
    yield _conversationStartedAt;
    yield* _conversationStartController.stream;
  }

  @override
  Stream<MemoryProfile> watchMemory() async* {
    yield _memory;
    yield* _memoryController.stream;
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

  void _emitBattle() {
    if (!_battleController.isClosed) _battleController.add(_battleState);
  }

  void _emitMemory() {
    if (!_memoryController.isClosed) _memoryController.add(_memory);
  }

  void _emitConversationStart() {
    if (!_conversationStartController.isClosed) {
      _conversationStartController.add(_conversationStartedAt);
    }
  }

  void _seedCurrentConversation() {
    final now = DateTime.now();
    _conversationStartedAt = now.subtract(const Duration(minutes: 40));
    final messages = <Message>[
      Message(
        conversationId: currentConversationId,
        sequence: 1,
        createdAt: now.subtract(const Duration(minutes: 40)),
        party: Party.b,
        type: MessageType.text,
        content: '你昨天为什么又不回我消息？我等了你一晚上。',
      ),
      Message(
        conversationId: currentConversationId,
        sequence: 2,
        createdAt: now.subtract(const Duration(minutes: 38)),
        party: Party.a,
        type: MessageType.text,
        content: '我昨天加班到很晚，手机没电了，真的不是故意不回。',
      ),
      Message(
        conversationId: currentConversationId,
        sequence: 3,
        createdAt: now.subtract(const Duration(minutes: 36)),
        party: Party.b,
        type: MessageType.text,
        content: '你每次都这么说。上次出差失联两天，这次又是手机没电。',
      ),
      Message(
        conversationId: currentConversationId,
        sequence: 4,
        createdAt: now.subtract(const Duration(minutes: 34)),
        party: Party.a,
        type: MessageType.text,
        content: '上次出差是真的在飞机上，这次真的是没电。你要我怎么证明？',
      ),
      Message(
        conversationId: currentConversationId,
        sequence: 5,
        createdAt: now.subtract(const Duration(minutes: 32)),
        party: Party.b,
        type: MessageType.text,
        content: '我不是要你证明，我只是希望你在乎我的感受。等一晚上的感觉很难受。',
      ),
      Message(
        conversationId: currentConversationId,
        sequence: 6,
        createdAt: now.subtract(const Duration(minutes: 30)),
        party: Party.a,
        type: MessageType.text,
        content: '我知道了……对不起，以后加班前我先跟你说一声。',
      ),
    ];
    _messagesByConversation[currentConversationId] = messages;
    _cases.add(
      Case(
        id: currentConversationId,
        title: '昨晚没回消息',
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
    );
  }

  @override
  Future<void> seedDemoData() async {
    _emitCases();
    _emitBattle();
    _emitMemory();
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
  Future<void> saveMemory(MemoryProfile memory) async {
    _memory = memory;
    _emitMemory();
  }

  @override
  Future<void> deleteMemoryEntry(String entryId) async {
    final index = _memory.entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return;
    final entries = _memory.entries.toList();
    entries[index] = entries[index].copyWith(isDeleted: true);
    await saveMemory(_memory.copyWith(entries: entries));
  }

  @override
  Future<void> setBattleView(BattleView view) async {
    _battleState = _battleState.copyWith(
      view: view,
      headline: _headlineFor(view),
      cards: const [],
      updatedAt: DateTime.now(),
    );
    _emitBattle();
  }

  /// 分析完成后更新战场状态（维度卡片 + 战况小结 + 可视化指标）。
  @override
  Future<void> applyAnalysisToBattle({
    required Analysis analysis,
    required List<BattleCard> cards,
    String headline = '',
  }) async {
    _battleState = _battleState.copyWith(
      view: analysis.view,
      headline: headline.isEmpty ? _headlineFor(analysis.view) : headline,
      cards: cards,
      updatedAt: DateTime.now(),
    );
    _emitBattle();
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
    _battleController.close();
    _memoryController.close();
    _conversationStartController.close();
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    for (final controller in _analysisControllers.values) {
      controller.close();
    }
  }
}
