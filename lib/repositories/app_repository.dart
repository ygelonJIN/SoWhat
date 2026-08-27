import '../models/models.dart';

/// App 级数据仓库接口。当前为内存实现，后续替换为本地数据库。
abstract class AppRepository {
  Stream<List<Case>> watchCases();
  Stream<List<Message>> watchMessages(String conversationId);
  Stream<List<Analysis>> watchAnalyses(String conversationId);
  Stream<BattleState> watchBattleState();
  Stream<MemoryProfile> watchMemory();

  /// 当前对话开始的时间（右上角展示，不随当前时刻变动）。
  Stream<DateTime> watchConversationStartedAt();

  Future<void> seedDemoData();
  Future<Case> upsertCase(Case caseItem);
  Future<void> deleteCase(String conversationId);
  Future<int> nextMessageSequence(String conversationId);
  Future<void> addMessage(Message message);
  Future<void> deleteMessage(String conversationId, int sequence);
  Future<void> saveAnalysis(Analysis analysis);
  Future<void> saveMemory(MemoryProfile memory);
  Future<void> deleteMemoryEntry(String entryId);
  Future<void> setBattleView(BattleView view);
  Future<void> applyAnalysisToBattle({
    required Analysis analysis,
    required List<BattleCard> cards,
    String headline = '',
  });

  void dispose();
}
