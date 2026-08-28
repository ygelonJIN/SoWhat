import 'dart:convert';

import '../models/models.dart';
import 'ai_client.dart';
import 'prompt_service.dart';

/// 三视角分析服务。
///
/// 已配置 API（BYOK，小米 MiMo）：用 [PromptService] 生成系统提示词（含
/// JSON 输出契约），直连模型厂商，把返回的 JSON 解析成维度卡片；接口失败
/// 抛 [AiRequestException]（UI 已统一以 SnackBar 展示错误）。
/// 未配置：返回占位演示分析，并提示去设置页配置。
class AnalysisService {
  const AnalysisService();

  Future<Analysis> analyze({
    required String conversationId,
    required BattleView view,
    required AiChannel channel,
    MemoryProfile? memory,
    String conversation = '',
    AiConfig? config,
    List<MessageImage> images = const [],
    void Function(String message)? onDebug,
    void Function(String cumulativeThinking)? onThinking,
  }) async {
    final promptService = const PromptService();
    final effectiveMemory = memory ?? MemoryProfile.empty();

    if (config != null && config.isConfigured) {
      return _analyzeWithModel(
        conversationId: conversationId,
        view: view,
        channel: channel,
        memory: effectiveMemory,
        conversation: conversation,
        config: config,
        promptService: promptService,
        images: images,
        onDebug: onDebug,
        onThinking: onThinking,
      );
    }

    if (onThinking != null) {
      onThinking('正在理解对话上下文…');
      await Future<void>.delayed(const Duration(milliseconds: 420));
      onThinking('正在理解对话上下文…\n正在结合长期记忆分析关系模式…');
      await Future<void>.delayed(const Duration(milliseconds: 520));
      onThinking('正在理解对话上下文…\n正在结合长期记忆分析关系模式…\n正在按「${_viewLabel(view)}」视角逐维度展开…');
      await Future<void>.delayed(const Duration(milliseconds: 480));
    }
    onDebug?.call('未配置 API，使用演示分析…');
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
      content: '分析服务尚未接入真实模型。请在设置页「配置 API」填入小米 MiMo 的 API Key。',
      cards: cards,
      tokenCount: prompt.length,
    );
  }

  Future<Analysis> _analyzeWithModel({
    required String conversationId,
    required BattleView view,
    required AiChannel channel,
    required MemoryProfile memory,
    required String conversation,
    required AiConfig config,
    required PromptService promptService,
    required List<MessageImage> images,
    void Function(String message)? onDebug,
    void Function(String cumulativeThinking)? onThinking,
  }) async {
    final prompt = promptService.buildSystemPrompt(
      view: view,
      memory: memory,
      conversation: conversation,
      structured: true,
    );
    final user = conversation.trim().isEmpty
        ? '（本轮对话内容为空，请基于已有长期记忆与图片给出分析。）'
        : conversation;

    final protocolLabel = config.protocol == AiProtocol.openai
        ? 'OpenAI 兼容'
        : 'Anthropic 兼容';
    onDebug?.call(
      images.isEmpty
          ? '正在调用 ${config.effectiveModel}（$protocolLabel）…'
          : '正在编码 ${images.length} 张图片并调用 ${config.effectiveModel}（$protocolLabel）…',
    );
    final thinkingBuffer = StringBuffer();
    final raw = await const AiClient().chatStream(
      config: config,
      system: prompt,
      user: user,
      images: images,
      onThinking: onThinking == null
          ? null
          : (delta) {
              thinkingBuffer.write(delta);
              onThinking(thinkingBuffer.toString());
            },
    );
    onDebug?.call('已收到模型响应，正在解析维度卡片…');

    final cards = _parseCards(raw);
    return Analysis(
      conversationId: conversationId,
      view: view,
      channel: channel,
      modelName: config.effectiveModel,
      content: raw,
      cards: cards,
      tokenCount: prompt.length,
    );
  }

  String _viewLabel(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '为爱';
      case BattleView.right:
        return '论对错';
      case BattleView.win:
        return '比输赢';
    }
  }

  /// 解析模型返回的结构化 JSON（可能被 ```json 代码块包裹）。
  List<AnalysisCard> _parseCards(String raw) {
    final text = _stripFences(raw.trim());
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const AiRequestException('模型返回的不是 JSON（可能被截断），请重试。');
    }
    if (decoded is! Map) {
      throw const AiRequestException('模型返回结构异常，请重试。');
    }
    final rawCards = decoded['cards'];
    if (rawCards is! List || rawCards.isEmpty) {
      throw const AiRequestException('模型没有返回分析卡片，请重试。');
    }

    final cards = <AnalysisCard>[];
    for (final item in rawCards) {
      if (item is! Map) continue;
      final title = item['title']?.toString().trim() ?? '';
      final conclusion = item['conclusion']?.toString().trim() ?? '';
      if (title.isEmpty || conclusion.isEmpty) continue;
      final evidence = _nullableText(item['evidence']);
      final speculation = _nullableText(item['speculation']);
      cards.add(
        AnalysisCard(
          title: title,
          conclusion: conclusion,
          evidence: evidence,
          speculation: speculation,
        ),
      );
    }
    if (cards.isEmpty) {
      throw const AiRequestException('模型返回的分析卡片无法解析，请重试。');
    }
    return cards;
  }

  String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _stripFences(String text) {
    final match =
        RegExp(r'^\s*```(?:json)?\s*([\s\S]*?)\s*```\s*$').firstMatch(text);
    return match == null ? text : match.group(1)!;
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
