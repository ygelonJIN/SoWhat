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

  /// 修改一段对话的开始时间（右上角日期时间可点选修改，用于补录/回填历史）。
  Future<Case> updateCaseCreatedAt(String caseId, DateTime createdAt);

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

  /// 原子导入一段对话（聊天记录导入用）：对话 + 消息 + 分析 +
  /// 战场状态恢复 + 资产元数据 在同一事务内写入，任一步失败整体回滚。
  /// [messages] 的 assetPath 必须是已写入应用私有目录的最终路径。
  Future<void> importCaseData({
    required Case caseItem,
    required List<Message> messages,
    required List<Analysis> analyses,
  });

  /// 原子完成一次「更新记忆」：写档案 + 标记卡片已消化 + 锁定对话，
  /// 三者必须同事务，任一步失败全部回滚（避免卡片已消化但记忆未写入）。
  Future<void> saveMemoryWithProcessing({
    required MemoryProfile memory,
    required List<String> analysisIds,
    required List<String> conversationIds,
  });

  /// 保存 BYOK 接入配置（厂商 / API Key / 模型 / 端点）。
  Future<void> saveAiConfig(AiConfig config);

  /// 清空全部用户数据（对话 / 消息 / 分析 / 战场状态 / 长期记忆 / 图片），
  /// 保留 AI 配置。用于「清空全部数据」：清完后各页面回到空白态。
  Future<void> wipeUserData();

  /// 按勾选分类清空用户数据（保留 AI 接口配置 / API Key）。
  ///
  /// 各分类独立；勾了 [conversations] 会连带其对话的分析卡片与记忆引用一并
  /// 删除（与删除单个对话的级联一致）。[assets] 只清资产库与其未被引用的
  /// 文件，保留仍被对话使用中的图片文件。
  Future<void> clearUserData({
    bool conversations = false,
    bool analyses = false,
    bool memory = false,
    bool assets = false,
  });
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
