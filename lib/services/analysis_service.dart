import '../models/models.dart';
import 'prompt_service.dart';

/// 三视角分析服务。
///
/// 当前为占位：未接真实模型时，返回一段带提示的演示分析，并标明这是占位。
/// 真实模型接入后（V1 通道 A / V2 BYOK），按 [PromptService] 生成系统提示词，
/// 把对话内容 + 长期记忆一起交给模型。
class AnalysisService {
  const AnalysisService();

  Future<Analysis> analyze({
    required String conversationId,
    required BattleView view,
    required AiChannel channel,
    MemoryProfile? memory,
    String conversation = '',
  }) async {
    final promptService = const PromptService();
    final effectiveMemory = memory ?? MemoryProfile.empty();
    final prompt = promptService.buildSystemPrompt(
      view: view,
      memory: effectiveMemory,
      conversation: conversation,
    );
    final cards = _demoCards(view, conversation);
    return Analysis(
      conversationId: conversationId,
      view: view,
      channel: channel,
      modelName: '待接入模型',
      content: '分析服务尚未接入真实模型。点击右上角「复制分析包」，可以把这份提示词贴到免费的 AI 里得到真实分析，再粘贴回来存档。',
      cards: cards,
      tokenCount: prompt.length,
    );
  }

  List<AnalysisCard> _demoCards(BattleView view, String conversation) {
    if (conversation.trim().isEmpty) return const [];
    switch (view) {
      case BattleView.right:
        return const [
          AnalysisCard(
            title: '事实陈述',
            conclusion: '（演示）双方对「发生了什么」的叙述大体一致，未发现明显夸大或选择性记忆。',
            evidence: '待接入模型后引用原文。',
          ),
          AnalysisCard(
            title: '逻辑推理',
            conclusion: '（演示）暂未检测到「你总是 / 你从来」这类以偏概全的表述。',
            evidence: '待接入模型后引用原文。',
          ),
          AnalysisCard(
            title: '沟通方式',
            conclusion: '（演示）语气整体克制，未出现人身攻击或贴标签。',
            evidence: '待接入模型后引用原文。',
          ),
        ];
      case BattleView.love:
        return const [
          AnalysisCard(
            title: '核心需求',
            conclusion: '（演示）双方争论的背后，可能都在表达「被重视」的需要。',
            evidence: '待接入模型后引用原文。',
            speculation: '推测，需结合上下文确认。',
          ),
          AnalysisCard(
            title: '关系投资',
            conclusion: '（演示）暂未看到主动破冰或示弱的动作。',
            evidence: '待接入模型后引用原文。',
          ),
          AnalysisCard(
            title: '修复意愿',
            conclusion: '（演示）需要看双方是否愿意放下对错来保住关系。',
            evidence: '待接入模型后引用原文。',
          ),
        ];
      case BattleView.win:
        return const [
          AnalysisCard(
            title: '气势掌控',
            conclusion: '（演示）暂未判断谁主导了节奏。',
            evidence: '待接入模型后引用原文。',
          ),
          AnalysisCard(
            title: '代价收益',
            conclusion: '（演示）即便有人在「输赢」上占了上风，关系上往往双输。',
            evidence: '待接入模型后引用原文。',
          ),
          AnalysisCard(
            title: '战局结果',
            conclusion: '（演示）目前更像是双输，而不是分出胜负。',
            evidence: '待接入模型后引用原文。',
          ),
        ];
    }
  }
}
