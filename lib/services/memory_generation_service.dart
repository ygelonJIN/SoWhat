import 'dart:convert';

import '../models/models.dart';
import '../utils/format.dart';

/// 记忆生成服务（产品文档第 4 章，主打）。
///
/// 用户点「更新记忆」时：App 组装「已有档案 + 全部未消化卡片」为提示词，
/// 发给 AI；AI 返回 JSON（增量条目 + 四份概况）；本服务负责解析回模型。
/// 输出格式与提示词已定稿（见 [buildPrompt]）。
class MemoryGenerationService {
  const MemoryGenerationService();

  /// 单张「未消化」分析卡片（输入给 AI 的最小单元）。
  ///
  /// 跳过已锁定对话（hasFinalizedMemory = true）：一个对话只允许成功生成一次
  /// 长期记忆，不允许后续单看新卡片再重复生成，因为共享档案的四大类需要跨模式
  /// 客观融合，不能被单一模式的增量卡片反复修改。
  List<GenerationCard> collectUnprocessed({
    required List<Case> cases,
    required List<Analysis> Function(String conversationId) analysesOf,
  }) {
    final cards = <GenerationCard>[];
    for (final caseItem in cases) {
      if (caseItem.hasFinalizedMemory) continue;
      for (final analysis in analysesOf(caseItem.id)) {
        if (analysis.memoryProcessedAt != null) continue;
        for (final card in analysis.cards) {
          cards.add(
            GenerationCard(
              analysisId: analysis.id,
              conversationId: caseItem.id,
              conversationLabel: _conversationLabel(caseItem),
              happenedAt: analysis.createdAt,
              view: analysis.view,
              dimension: card.title,
              conclusion: card.conclusion,
              evidence: card.evidence ?? '',
            ),
          );
        }
      }
    }
    cards.sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
    return cards;
  }

  /// 对话标识：有自定义名称用名称，否则用日期时间（与聊天记录列表一致，
  /// AI 输出时原样回填，解析时按此回映射到对话）。
  String _conversationLabel(Case caseItem) {
    final hasName = caseItem.title != null && caseItem.title!.isNotEmpty;
    if (hasName) return caseItem.title!;
    return '${formatDate(caseItem.createdAt)} ${formatTime(caseItem.createdAt)}';
  }

  /// 记忆生成提示词（v6）。
  ///
  /// 输出契约：JSON，`entries` 每条带「kind / summary / cardRef」，
  /// `summaries` 四份极其完善的综合档案（user / partner / relationship / growth）。
  String buildPrompt({
    required MemoryProfile memory,
    required List<GenerationCard> cards,
  }) {
    final buffer = StringBuffer()
      ..writeln('你是这对情侣的长期关系档案管理员。用户点「更新记忆」时，把新增的分析卡片增量写进一份统一长期记忆。')
      ..writeln('长期记忆只有一份，不按模式拆分。模式只是分析视角，不是记忆分区。')
      ..writeln('本次输入可能来自 1 个、2 个或 3 个模式，请只根据实际提供的卡片进行融合，不要假设三种模式都存在。')
      ..writeln('同一对话未来不会重复写入长期记忆；你只负责输出当前这一次、对当前未消化卡片的统一归档。')
      ..writeln('如果同一对话里同时出现多个模式的卡片，请把它们合并成一份客观、稳定、去模式化的最终档案。')
      ..writeln('称呼铁律（两人绝不能搞混）：「我」= 使用本 App 的人，也就是原对话里标着「我」的一方；「TA」= 另一人，也就是原对话里标着「TA」的一方。一律用「双方 / 我 / TA」，禁止「你、他、她、A、B、男方、女方、对方」等任何其他称呼；判断谁是谁时，以卡片证据里「我 / TA」的原文标签为准。')
      ..writeln('你只输出一个 JSON 对象，不要任何其他文字。')
      ..writeln()
      ..writeln('【输入一：已有记忆档案】')
      ..writeln('<memory>')
      ..writeln(_formatMemory(memory))
      ..writeln('</memory>')
      ..writeln()
      ..writeln('【输入二：本轮新增卡片】')
      ..writeln('<cards>');

    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      buffer
        ..writeln('[卡片${i + 1}]')
        ..writeln('  对话：${card.conversationLabel}')
        ..writeln('  日期：${_formatDateTime(card.happenedAt)}')
        ..writeln('  注意：同一对话的多个卡片共享同一个来源时间；界面只显示一次日期时间。')
        ..writeln('  视角：${_viewLabel(card.view)}')
        ..writeln('  维度：${card.dimension}')
        ..writeln('  结论：${card.conclusion}')
        ..writeln('  证据：${card.evidence}');
    }

    buffer
      ..writeln('</cards>')
      ..writeln()
      ..writeln('【输出分两部分：概况（最重要）+ 增量条目】')
      ..writeln()
      ..writeln('▍一、概况 summaries —— 最重要，必须极其完善')
      ..writeln('概况是这份档案的「当前最新综合版」，共四份，覆盖全部已知信息：')
      ..writeln('- user：我（使用本 App 的人）的完整画像')
      ..writeln('- partner：TA 的完整画像')
      ..writeln('- relationship：这段关系的完整状态')
      ..writeln('- growth：从第一次记录到现在的完整成长档案')
      ..writeln('要求：')
      ..writeln('1. 每份是完整档案不是摘要：把「旧概况 + 本轮卡片里相关信息」全部融合进去，保留具体事实与例子。')
      ..writeln('2. 有内部结构，按逻辑分点（画像按：性格、表达方式、情绪触发点、在乎与害怕、对关系的期待、依恋模式…；关系按：健康度、反复矛盾、已改善、当前状态…）。')
      ..writeln('3. 反映变化：与旧概况不同的新认识明确写出（如「之前回避型，最近一次很主动」）。')
      ..writeln('4. 即使本轮没有新认知，也必须原样保留旧概况的全部内容。')
      ..writeln('5. 适度精简：若旧概况已很长，可在不丢核心事实的前提下，把过时或次要的细节适当压缩，避免概况无限膨胀。')
      ..writeln()
      ..writeln('▍二、增量条目 entries —— 九个板块')
      ..writeln('动态类（双方画像、关系状态、成长轨迹）——要「对照旧档案」：')
      ..writeln('如果本次卡片来自同一对话的不同模式，请综合它们生成更客观的统一条目，不要按模式分别输出三份记忆。')
      ..writeln('先读旧档案中同板块的旧条目，再看本轮卡片，判断关系：')
      ..writeln('- 旧档案里没有相关旧条目（第一次记录）→ 写新条目，以「新观察：…」开头。')
      ..writeln('- 卡片观察与旧条目描述「一致」（同一模式再次出现）→ 写新条目，以「仍在：…」开头。')
      ..writeln('- 卡片观察与旧条目描述「不一致 / 有新发现」→ 写新条目，以「变化：…」开头，写清从什么变成了什么。')
      ..writeln('  示例：旧条目「TA 冲突时倾向沉默」；卡片说「TA 又沉默」→「仍在：TA 冲突时倾向沉默」；卡片说「TA 主动开口表达」→「变化：TA 从沉默变为主动表达」；旧档案没有这条 →「新观察：TA 冲突时会先沉默再开口」。')
      ..writeln('  注意：条目正文一律纯文本，禁止用星号（**）、反引号等任何 markdown 标记；「仍在/变化/新观察」只用「标签：正文」这一种格式。')
      ..writeln('静态类（矛盾触发点、有效沟通方式库、关系里程碑、雷区清单、未解决的问题、承诺跟踪）——只增量，但要先去重：')
      ..writeln('本轮卡片里能观察到、且旧档案没有实质重复的内容，直接写成新条目；同一对话或同一事实在多个模式卡片中重复出现时，只输出一条，合并 cardRef；若已存在等价条目，不再重复追加。')
      ..writeln('动态类也要去重：同一对话、同一事实的多张卡片合并为一条，多个来源用逗号分隔。旧条目一律保留，只追加有新信息的条目，不覆盖。')
      ..writeln('每条必须标注出处：cardRef 填「卡片N」（引用输入卡片编号，多个来源用逗号分隔，如「卡片1,卡片3」），不要改写编号。')
      ..writeln()
      ..writeln('【输出顺序】')
      ..writeln('第一步：写四份概况，务必完整。')
      ..writeln('第二步：写增量条目，按九板块逐个处理（先动态类三块，再静态类六块）。')
      ..writeln('第三步：检查 JSON——括号闭合、字段完整、cardRef 用输入原文。')
      ..writeln()
      ..writeln('【铁律】')
      ..writeln('1. 只写卡片里能看到的事实，不编造。')
      ..writeln('1a. 「事实」「观察」「推断」分层：仅事实或多次一致观察可写入稳定档案；单次且不确定的判断写入时必须保留「可能 / 尚无法确认」等限定。')
      ..writeln('2. 用「双方 / 我 / TA」，禁止「你、他、她、A、B、男方、女方、对方」等任何其他称呼与性别标签；两人的信息绝不能互换。')
      ..writeln('3. 条目一句话一条，只写具体观察，不写情绪化评价。')
      ..writeln('4. 概况与条目一律纯文本：禁止星号（**）、反引号、井号等任何 markdown 标记。')
      ..writeln('5. 同一对话只显示一次出处日期和时间；不要输出「等几处」或重复来源提示。多个 cardRef 只用于内部精确回溯，不改变界面展示。')
      ..writeln('6. 没有新条目时 entries 输出空数组；概况任何时候都要输出完整版。')
      ..writeln()
      ..writeln('【输出 JSON】')
      ..writeln('{ "entries": [')
      ..writeln('    { "kind": "双方画像", "summary": "仍在：TA 冲突时倾向沉默", "cardRef": "卡片1" },')
      ..writeln('    { "kind": "矛盾触发点", "summary": "谈到「钱」时容易起争执", "cardRef": "卡片2,卡片3" }')
      ..writeln('  ],')
      ..writeln('  "summaries": { "user": "…", "partner": "…", "relationship": "…", "growth": "…" } }')
      ..writeln('kind 只允许九值之一：双方画像 / 关系状态 / 成长轨迹 / 矛盾触发点 / 有效沟通方式库 / 关系里程碑 / 雷区清单 / 未解决的问题 / 承诺跟踪。');
    return buffer.toString();
  }

  /// 解析 AI 返回的 JSON：映射 kind / cardRef 标签回模型。
  ///
  /// 解析失败（非 JSON / 结构不符）时抛出 [FormatException]。
  MemoryGenerationResult parseResponse({
    required String response,
    required List<GenerationCard> cards,
  }) {
    final text = _normalizeJson(_stripFences(response.trim()));
    final dynamic decoded = _decodeResponseJson(text) ??
        (throw const FormatException('记忆生成响应不是有效 JSON，可能被截断。'));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('记忆生成响应不是 JSON 对象');
    }

    // 卡片编号 → 卡片 映射，与 buildPrompt 中的「[卡片N]」编号一致。
    final cardRefMap = <String, GenerationCard>{
      for (var i = 0; i < cards.length; i++) '卡片${i + 1}': cards[i],
    };

    final entries = <MemoryEntry>[];
    final rawEntries = decoded['entries'];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is! Map) continue;
        final kind = _kindFromLabel(item['kind']?.toString() ?? '');
        final summary = item['summary']?.toString().trim() ?? '';
        if (kind == null || summary.isEmpty) continue;
        entries.add(
          MemoryEntry(
            kind: kind,
            summary: summary,
            sources: _resolveSources(
              cardRef: item['cardRef']?.toString().trim(),
              conversationLabel: item['conversation']?.toString().trim(),
              cardRefMap: cardRefMap,
              cards: cards,
            ),
          ),
        );
      }
    }

    final summaries = decoded['summaries'];
    String? value(String key) {
      if (summaries is! Map) return null;
      final v = summaries[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return MemoryGenerationResult(
      entries: entries,
      userSummary: value('user'),
      partnerSummary: value('partner'),
      relationshipSummary: value('relationship'),
      growthSummary: value('growth'),
    );
  }

  /// 解析条目出处：优先按 cardRef（卡片编号，精确无歧义）匹配，
  /// 未提供或匹配不到时回退到对话标识匹配。
  List<MemorySourceRef> _resolveSources({
    required Map<String, GenerationCard> cardRefMap,
    required List<GenerationCard> cards,
    String? cardRef,
    String? conversationLabel,
  }) {
    if (cardRef != null && cardRef.isNotEmpty) {
      final sources = <MemorySourceRef>[];
      for (final ref in cardRef.split(RegExp(r'[,，、]'))) {
        final card = cardRefMap[ref.trim()];
        if (card == null) continue;
        sources.add(
          MemorySourceRef(
            conversationId: card.conversationId,
            happenedAt: card.happenedAt,
          ),
        );
      }
      if (sources.isNotEmpty) return sources;
    }

    if (conversationLabel == null || conversationLabel.isEmpty) {
      return const [];
    }
    final matched = cards
        .where((c) => c.conversationLabel == conversationLabel)
        .toList();
    if (matched.isEmpty) return const [];
    return [
      MemorySourceRef(
        conversationId: matched.first.conversationId,
        happenedAt: matched.first.happenedAt,
      ),
    ];
  }

  String _formatMemory(MemoryProfile memory) {
    final lines = <String>[];
    void section(String title, String? text) {
      if (text == null || text.isEmpty) return;
      lines.add('【$title】');
      lines.add(text);
    }

    section('我的画像（使用本 App 的人）', memory.userSummary);
    section('TA 的画像', memory.partnerSummary);
    section('关系状态', memory.relationshipSummary);
    section('成长档案', memory.growthSummary);

    final alive = memory.entries.where((e) => !e.isDeleted).toList();
    if (alive.isNotEmpty) {
      lines.add('【已有条目】');
      for (final entry in alive) {
        lines.add('${_kindLabel(entry.kind)}：${entry.summary}');
      }
    }
    if (lines.isEmpty) lines.add('（尚无长期记忆）');
    return lines.join('\n');
  }

  String _kindLabel(MemoryKind kind) {
    return switch (kind) {
      MemoryKind.profile => '双方画像',
      MemoryKind.relationship => '关系状态',
      MemoryKind.growth => '成长轨迹',
      MemoryKind.trigger => '矛盾触发点',
      MemoryKind.commLib => '有效沟通方式库',
      MemoryKind.milestone => '关系里程碑',
      MemoryKind.minefield => '雷区清单',
      MemoryKind.openIssue => '未解决的问题',
      MemoryKind.promise => '承诺跟踪',
    };
  }

  MemoryKind? _kindFromLabel(String label) {
    return switch (label) {
      '双方画像' => MemoryKind.profile,
      '关系状态' => MemoryKind.relationship,
      '成长轨迹' => MemoryKind.growth,
      '矛盾触发点' => MemoryKind.trigger,
      '有效沟通方式库' => MemoryKind.commLib,
      '关系里程碑' => MemoryKind.milestone,
      '雷区清单' => MemoryKind.minefield,
      '未解决的问题' => MemoryKind.openIssue,
      '承诺跟踪' => MemoryKind.promise,
      _ => null,
    };
  }

  String _viewLabel(BattleView view) {
    return switch (view) {
      BattleView.love => '争爱',
      BattleView.right => '争对错',
      BattleView.win => '争输赢',
    };
  }

  String _formatDateTime(DateTime time) {
    return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 去掉 AI 偶尔包上的 ```json 代码块标记。
  String _stripFences(String text) {
    final match = RegExp(r'^\s*```(?:json)?\s*([\s\S]*?)\s*```\s*$').firstMatch(text);
    return match == null ? text : match.group(1)!;
  }

  /// 容错：AI 偶尔会把 JSON 的英文大括号打成中文全角 ｛｝，先归一化再解析。
  String _normalizeJson(String text) {
    return text.replaceAll('｛', '{').replaceAll('｝', '}');
  }

  /// 尝试把响应文本解析成 JSON：先整体解析；失败时截取首尾大括号之间的
  /// 内容（AI 偶尔在 JSON 前后夹带说明文字）再试一次。仍失败返回 null。
  dynamic _decodeResponseJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      // 容错：AI 偶尔在 JSON 前后夹带说明文字；截取首尾大括号之间的内容
      // 再试一次。若确实是输出被截断（JSON 不完整），返回 null 由上层按
      // 「可能被截断」处理。
      final salvaged = _extractJsonSubstring(text);
      if (salvaged == null) return null;
      try {
        return jsonDecode(salvaged);
      } catch (_) {
        return null;
      }
    }
  }

  /// 从响应文本里截取第一个 `{` 到最后一个 `}` 之间的内容（去掉 JSON 前后
  /// 夹带的说明文字）；截取不到或区间非法时返回 null。
  String? _extractJsonSubstring(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}

/// 输入给 AI 的单张未消化分析卡片。
class GenerationCard {
  /// 来源分析（用于生成成功后标记「已消化」）。
  final String analysisId;
  final String conversationId;
  final String conversationLabel;

  /// 卡片（分析）时间，作为「时间编号」与出处。
  final DateTime happenedAt;
  final BattleView view;
  final String dimension;
  final String conclusion;
  final String evidence;

  const GenerationCard({
    required this.analysisId,
    required this.conversationId,
    required this.conversationLabel,
    required this.happenedAt,
    required this.view,
    required this.dimension,
    required this.conclusion,
    required this.evidence,
  });
}

/// 解析结果：增量条目 + 四份概况（概况为 null 表示 AI 未输出 / 不覆盖）。
class MemoryGenerationResult {
  final List<MemoryEntry> entries;
  final String? userSummary;
  final String? partnerSummary;
  final String? relationshipSummary;
  final String? growthSummary;

  const MemoryGenerationResult({
    this.entries = const [],
    this.userSummary,
    this.partnerSummary,
    this.relationshipSummary,
    this.growthSummary,
  });
}
