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
///
/// JSON 健壮性（v0.16）：
/// - 维度白名单：按视角的规范维度表做归一化匹配 + 重排 + 去重；
/// - 缺失局部修复：允许缺维度，只要还有可用卡片就接受（不整轮失败）；
/// - 截断检测：括号不闭合直接判定截断，走重试而非报通用解析错误；
/// - 指数退避重试：解析类失败自动带「精简输出」提示重试（1s / 2s）；
/// - 保留原文二次解析：[parseCards] 为公开 API，可对已保存的
///   [Analysis.content] 直接重新解析，无需再调模型。
class AnalysisService {
  const AnalysisService();

  /// 每个视角的规范维度顺序（与提示词 / 产品文档 3.2 完全一致）。
  static const Map<BattleView, List<String>> canonicalDimensions = {
    BattleView.right: [
      '事实陈述',
      '逻辑推理',
      '归因责任',
      '沟通方式',
      '视角立场',
      '时间取向',
      '解决方案',
    ],
    BattleView.love: [
      '动机初衷',
      '核心需求',
      '情绪表达',
      '共情能力',
      '关系投资',
      '依恋安全感',
      '情感账户',
      '修复意愿',
    ],
    BattleView.win: [
      '气势掌控',
      '攻击效力',
      '面子自尊',
      '主动权',
      '筹码资源',
      '耐力持久',
      '代价收益',
      '战局结果',
    ],
  };

  /// 解析类错误重试上限（指数退避：第 1 次失败等 1s、第 2 次等 2s）。
  static const int _maxParseAttempts = 2;

  /// 发给模型的输出上限（思考 + 维度卡片 JSON 共用同一额度）。
  static const int _maxOutputTokens = 8192;

  /// 首轮思考超过该字数（约等于中文字符数）视为「思考挤满输出上限」：
  /// 重试时自动把 max_tokens 翻倍，而不是只提示用户手动减少输入。
  static const int _thinkingFullChars = 3000;

  /// 思考字数超过该值说明模型在无效地长篇输出，重试大概率仍失败，
  /// 直接抛出带诊断的失败，不再烧一次调用。
  static const int _thinkingRetryCapChars = 12000;

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
    final baseUser = conversation.trim().isEmpty
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
    // 首轮思考字数：决定重试时是否自动放大输出上限（思考挤满 max_tokens
    // 是「只思考、没 JSON」的常见元凶）。
    var firstAttemptThinking = 0;
    var maxTokens = _maxOutputTokens;
    // 解析类失败自动重试（指数退避），网络类失败直接抛给上层。
    AiRequestException? lastError;
    for (var attempt = 0; attempt < _maxParseAttempts; attempt++) {
      try {
        final raw = await const AiClient().chatStream(
          config: config,
          system: prompt,
          user: attempt == 0
              ? baseUser
              // 重试：上轮输出疑似截断 / JSON 不完整。若上轮思考挤满上限，
              // 本轮已自动放大 maxTokens，并要求思考精简、只保结论。
              : firstAttemptThinking >= _thinkingFullChars
                    ? '$baseUser\n\n【重试提醒】上轮输出未通过 JSON 解析（${lastError?.message ?? '疑似被截断'}）。'
                          '原因很可能是上轮思考过长、挤占了正文输出空间。'
                          '本轮已放宽输出上限，请把思考压缩到最简，'
                          '正文每张卡片一句话结论，严格只输出一个完整闭合的 JSON 对象，'
                          '不要 markdown、不要多余文字。'
                    : '$baseUser\n\n【重试提醒】上轮输出未通过 JSON 解析（${lastError?.message ?? '疑似被截断'}）。'
                          '请重新生成：正文精简到最短、每张卡片一句话结论，'
                          '严格只输出一个完整闭合的 JSON 对象，不要 markdown、不要多余文字。',
          images: images,
          // 思考（reasoning）+ 维度卡片 JSON 一起输出，给足输出上限，
          // 避免「只思考、没正文」或 JSON 被截断的失败。
          maxTokens: maxTokens,
          onThinking: onThinking == null
              ? null
              : (delta) {
                  thinkingBuffer.write(delta);
                  onThinking(thinkingBuffer.toString());
                },
        );
        onDebug?.call('已收到模型响应，正在解析维度卡片…');
        final cards = parseCards(view, raw);
        return Analysis(
          conversationId: conversationId,
          view: view,
          channel: channel,
          modelName: config.effectiveModel,
          content: raw,
          cards: cards,
          tokenCount: prompt.length,
        );
      } on AiRequestException catch (error) {
        final isRetryable = _isRetryableParseError(error.message);
        // 首轮思考过长：自动放大输出上限再试，而不是直接放弃让用户手动减小。
        if (attempt == 0) {
          firstAttemptThinking = thinkingBuffer.length;
          if (firstAttemptThinking >= _thinkingFullChars &&
              firstAttemptThinking < _thinkingRetryCapChars) {
            maxTokens = _maxOutputTokens * 2;
          }
        }
        if (attempt < _maxParseAttempts - 1 &&
            isRetryable &&
            thinkingBuffer.length < _thinkingRetryCapChars) {
          lastError = error;
          final backoff = Duration(seconds: 1 << attempt);
          final hasBumped =
              attempt == 0 &&
              firstAttemptThinking >= _thinkingFullChars &&
              firstAttemptThinking < _thinkingRetryCapChars;
          onDebug?.call(
            hasBumped
                ? '思考过长（约 $firstAttemptThinking 字），已自动放大输出上限到 '
                      '$maxTokens 后重试…'
                : '第 ${attempt + 1} 次输出未通过解析（${error.message}），'
                      '${backoff.inSeconds}s 后自动重试（已提示模型精简）…',
          );
          await Future<void>.delayed(backoff);
          continue;
        }
        // 最终失败：带上可定位的诊断信息，别让用户只看到一个含糊的文案。
        final thinkingChars = thinkingBuffer.length;
        throw thinkingChars >= 1000
            ? AiRequestException(
                '${error.message}\n排查建议：本次思考内容约 $thinkingChars 字，'
                '很可能把输出上限（max_tokens=$maxTokens，思考+JSON 共用）'
                '挤满，导致 JSON 没写出来或被截断。'
                '${attempt > 0 ? '已自动放大上限重试仍失败；' : ''}'
                '可减少本轮内容/图片数量后重试，或调大输出上限。',
              )
            : error;
      }
    }
    // 不可达：_maxParseAttempts ≥ 1 时循环内必有 return / throw。
    throw lastError ?? const AiRequestException('分析失败，请重试。');
  }

  /// 只有「输出本身有问题」（截断 / 非 JSON / 无卡片）才值得重试；
  /// 连接类错误已由 [AiClient] 内部做过非流式回退，不再额外烧一次调用。
  bool _isRetryableParseError(String message) =>
      message.contains('JSON') ||
      message.contains('截断') ||
      message.contains('解析') ||
      message.contains('结构');

  /// 公开的二次解析入口：对已保存的模型原文（[Analysis.content]）重新解析，
  /// 与首次解析走完全相同的健壮性管线，便于「失败后保留原文、稍后重试」。
  List<AnalysisCard> parseCards(BattleView view, String raw) {
    final text = _normalizeJson(_stripFences(raw.trim()));
    if (_looksTruncated(text)) {
      throw const AiRequestException(
        '模型返回的 JSON 疑似被截断（大括号未闭合），已保留原文可二次解析。请重试。',
      );
    }

    final dynamic decoded = _decodeJson(text);
    if (decoded is! Map) {
      throw const AiRequestException('模型返回结构异常，已保留原文可二次解析。请重试。');
    }

    // cards 可能是数组，也可能被输出成单个对象（容错）。
    final rawCards = decoded['cards'];
    final items = switch (rawCards) {
      List() => rawCards,
      Map() => <Object?>[rawCards],
      _ => const <Object?>[],
    };
    if (items.isEmpty) {
      throw const AiRequestException('模型没有返回分析卡片，已保留原文可二次解析。请重试。');
    }

    // 维度归一化 + 白名单重排 + 去重；未知维度保留在末尾（可能有额外信息）。
    final canonical = canonicalDimensions[view]!;
    final byKey = <String, AnalysisCard>{};
    final unknown = <AnalysisCard>[];
    for (final item in items) {
      if (item is! Map) continue;
      final title = item['title']?.toString().trim() ?? '';
      final conclusion = item['conclusion']?.toString().trim() ?? '';
      if (title.isEmpty || conclusion.isEmpty) continue;
      final card = AnalysisCard(
        title: title,
        conclusion: conclusion,
        evidence: _nullableText(item['evidence']),
        speculation: _nullableText(item['speculation']),
      );
      final key = _normalizeDimension(title);
      final matched = canonical
          .where((dim) => dim == key || dim.contains(key) || key.contains(dim))
          .toList();
      if (matched.isEmpty) {
        unknown.add(card);
      } else {
        byKey.putIfAbsent(matched.first, () => card);
      }
    }

    final cards = <AnalysisCard>[
      for (final dim in canonical)
        if (byKey[dim] != null) byKey[dim]!,
      ...unknown,
    ];
    if (cards.isEmpty) {
      throw const AiRequestException(
        '模型返回的分析卡片无法解析，已保留原文可二次解析。请重试。',
      );
    }
    return cards;
  }

  /// 维度名归一化：去掉行首编号（1. / 1、 / 一、 / （1） / 【】等）与空白，
  /// 供与规范维度白名单做模糊匹配。
  String _normalizeDimension(String title) {
    var t = title.trim();
    t = t.replaceAll(
      RegExp(r'^[\[【(（]?\s*(?:[0-9]+|[一二三四五六七八九十]+)\s*[\.、)）\]】]?\s*'),
      '',
    );
    t = t.replaceAll(RegExp(r'\s+'), '');
    return t;
  }

  /// 截断检测：剥掉字符串字面量后统计大括号是否平衡。
  /// 开括号比闭括号多 → JSON 被截断（走重试，而非通用解析错误）。
  bool _looksTruncated(String text) {
    final stripped = text.replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""');
    var opens = 0;
    for (final code in stripped.runes) {
      if (code == 0x7B) {
        opens++;
      } else if (code == 0x7D) {
        opens--;
        if (opens < 0) return false;
      }
    }
    return opens > 0;
  }

  /// 尝试把响应文本解析成 JSON；失败时先试「首尾大括号截取」（AI 偶尔在
  /// JSON 前后夹带说明文字），仍失败抛可重试的 [AiRequestException]。
  dynamic _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      final salvaged = _extractJsonSubstring(text);
      if (salvaged == null) {
        throw const AiRequestException(
          '模型返回的不是有效 JSON（可能被截断），已保留原文可二次解析。请重试。',
        );
      }
      try {
        return jsonDecode(salvaged);
      } catch (_) {
        throw const AiRequestException(
          '模型返回的不是有效 JSON（可能被截断），已保留原文可二次解析。请重试。',
        );
      }
    }
  }

  /// 从文本里截取第一个 `{` 到最后一个 `}` 之间的内容（去掉 JSON 前后
  /// 夹带的说明文字）；截取不到或区间非法时返回 null。
  String? _extractJsonSubstring(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
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
