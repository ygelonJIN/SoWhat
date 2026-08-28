import '../models/models.dart';

/// App 级数据仓库接口。当前为内存实现，后续替换为本地数据库。
abstract class AppRepository {
  Stream<List<Case>> watchCases();
  Stream<List<Message>> watchMessages(String conversationId);
  Stream<List<Analysis>> watchAnalyses(String conversationId);
  Stream<BattleState> watchBattleState(String conversationId, BattleView view);
  Stream<MemoryProfile> watchMemory();
  Stream<AiConfig> watchAiConfig();
  Stream<List<Asset>> watchAssets();
  Future<Asset?> assetByPath(String path);
  Future<void> saveAsset(Asset asset);
  Future<void> renameAsset(String assetId, String title);
  Future<void> deleteAssets(List<String> assetIds);

  /// 指定对话开始的时间（右上角展示，不随当前时刻变动）。
  Stream<DateTime> watchConversationStartedAt(String conversationId);

  Future<Case> upsertCase(Case caseItem);
  Future<void> deleteCase(String conversationId);
  Future<void> deleteEmptyConversation(String conversationId);

  /// 清理没有任何消息的对话，并返回仍然存在的对话 id。
  Future<bool> cleanupEmptyConversation(String conversationId);

  /// 置顶 / 取消置顶一段对话。
  Future<Case> setCasePinned(String caseId, bool pinned);

  /// 重命名一段对话（自定义名称；日期时间记录保留，仍可被搜索命中）。
  Future<Case> renameCase(String caseId, String title);

  /// 删除引用了该对话的所有记忆条目（删除对话时勾选「连同记忆一起删除」）。
  Future<void> deleteMemoryForConversation(String conversationId);

  /// 标记一批对话已完成长期记忆写入（每个对话只允许一次）。
  Future<void> finalizeConversationsForMemory(List<String> conversationIds);

  /// 把分析卡片标记为「已被记忆消化」。
  Future<void> markAnalysesProcessed(List<String> analysisIds);

  Future<int> nextMessageSequence(String conversationId);
  Future<void> addMessage(Message message);
  Future<void> deleteMessage(String conversationId, int sequence);
  Future<void> saveAnalysis(Analysis analysis);
  Future<void> saveMemory(MemoryProfile memory);

  /// 保存 BYOK 接入配置（厂商 / API Key / 模型 / 端点）。
  Future<void> saveAiConfig(AiConfig config);

  /// 清空全部用户数据（对话 / 消息 / 分析 / 战场状态 / 长期记忆 / 图片），
  /// 保留 AI 配置。用于「清空全部数据」：清完后各页面回到空白态。
  Future<void> wipeUserData();
  Future<void> setBattleView(String conversationId, BattleView view);
  Future<void> applyAnalysisToBattle({
    required Analysis analysis,
    required List<BattleCard> cards,
    String headline = '',
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
  });

  /// 保存思考过程到当前视角的 BattleState（分析进行中实时调用）。
  Future<void> saveThinkingState({
    required String conversationId,
    required BattleView view,
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
  });

  void dispose();
}
