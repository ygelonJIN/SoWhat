import 'dart:convert';

import '../models/models.dart';
import 'ai_client.dart';
import 'prompt_service.dart';

/// 三视角分析服务。
///
/// 已配置 API（BYOK，小米 MiMo）：用 [PromptService] 生成系统提示词（含
/// JSON 输出契约），直连模型厂商，把返回的 JSON 解析成维度卡片；接口失败
/// 抛 [AiRequestException]（UI 已统一以 SnackBar 展示错误）。
/// 未配置：抛 [AiRequestException]，提示去设置页配置。
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

    throw const AiRequestException(
      '未配置 AI，请先在设置页「配置 API」填入接口信息后重试。',
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

  /// 解析模型返回的结构化 JSON（可能被 ```json 代码块包裹）。
  List<AnalysisCard> _parseCards(String raw) {
    final text = _normalizeJson(_stripFences(raw.trim()));
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

  /// 容错：AI 偶尔会把 JSON 的英文大括号打成中文全角 ｛｝，先归一化再解析。
  String _normalizeJson(String text) {
    return text.replaceAll('｛', '{').replaceAll('｝', '}');
  }
}
