import 'dart:async';

import '../models/models.dart';
import 'app_repository.dart';

/// 内存版仓库：用于当前可运行原型，后续替换为 drift + SQLCipher。
class MemoryAppRepository implements AppRepository {
  final List<Case> _cases = [];
  final Map<String, List<Message>> _messagesByConversation = {};
  final Map<String, List<Analysis>> _analysesByConversation = {};
  final StreamController<List<Case>> _caseController =
      StreamController<List<Case>>.broadcast();
  final StreamController<BattleState> _battleController =
      StreamController<BattleState>.broadcast();
  final StreamController<MemoryProfile> _memoryController =
      StreamController<MemoryProfile>.broadcast();
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamController<List<Analysis>>> _analysisControllers = {};

  BattleState _battleState = BattleState.initial();
  MemoryProfile _memory = MemoryProfile.empty();

  MemoryAppRepository() {
    seedDemoData();
  }

  @override
  Stream<List<Case>> watchCases() => _caseController.stream;

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    return _messageControllers
        .putIfAbsent(
          conversationId,
          () => StreamController<List<Message>>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<List<Analysis>> watchAnalyses(String conversationId) {
    return _analysisControllers
        .putIfAbsent(
          conversationId,
          () => StreamController<List<Analysis>>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<BattleState> watchBattleState() => _battleController.stream;

  @override
  Stream<MemoryProfile> watchMemory() => _memoryController.stream;

  void _emitCases() {
    if (!_caseController.isClosed) _caseController.add(List.unmodifiable(_cases));
  }

  void _emitMessages(String conversationId) {
    final controller = _messageControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(List.unmodifiable(_messagesByConversation[conversationId] ?? const []));
    }
  }

  void _emitAnalyses(String conversationId) {
    final controller = _analysisControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(List.unmodifiable(_analysesByConversation[conversationId] ?? const []));
    }
  }

  void _emitBattle() {
    if (!_battleController.isClosed) _battleController.add(_battleState);
  }

  void _emitMemory() {
    if (!_memoryController.isClosed) _memoryController.add(_memory);
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
    final list = _messagesByConversation.putIfAbsent(message.conversationId, () => []);
    list.add(message);
    _emitMessages(message.conversationId);
  }

  @override
  Future<void> saveAnalysis(Analysis analysis) async {
    final list = _analysesByConversation.putIfAbsent(analysis.conversationId, () => []);
    list.add(analysis);
    _emitAnalyses(analysis.conversationId);
  }

  @override
  Future<void> saveMemory(MemoryProfile memory) async {
    _memory = memory;
    _emitMemory();
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

  void dispose() {
    _caseController.close();
    _battleController.close();
    _memoryController.close();
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    for (final controller in _analysisControllers.values) {
      controller.close();
    }
  }
}
