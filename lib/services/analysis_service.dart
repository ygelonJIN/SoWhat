import '../models/models.dart';

/// 三视角分析服务占位。真实模型接入后，分析会同时读取本轮对话和长期记忆。
class AnalysisService {
  const AnalysisService();

  Future<Analysis> analyze({
    required String conversationId,
    required BattleView view,
    required AiChannel channel,
    MemoryProfile? memory,
    String conversation = '',
  }) async {
    return Analysis(
      conversationId: conversationId,
      view: view,
      channel: channel,
      modelName: '待接入模型',
      content: '分析服务尚未接入真实模型。对话会与长期记忆一起交给 AI 直接理解。',
      cards: const [],
    );
  }
}
