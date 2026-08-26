import '../models/models.dart';

/// 长期记忆服务（产品文档第 4 章）。
///
/// 职责：把每次对话与分析的观察沉淀进记忆档案；把记忆注入后续分析；
/// 支持回顾问答与记忆管理。当前为占位实现，沉淀逻辑待 AI 服务接入后替换。
class MemoryService {
  const MemoryService();

  /// 从一轮对话 + 分析结果中提取值得记住的新观察。
  ///
  /// 当前实现为“半结构化抽取”：不依赖真实模型，但会尽量从消息文本中
  /// 提炼出双方画像、关系状态、成长轨迹三类记忆，并保证每条都带出处。
  List<MemoryEntry> extractEntries({
    required List<Message> messages,
    required BattleView view,
    String? analysisText,
  }) {
    if (messages.isEmpty) return const [];

    final entries = <MemoryEntry>[];
    final viewLabel = _viewLabel(view);
    final source = '本轮对话（${messages.length} 条）';
    final text = messages.map((m) => m.content).join(' ');

    final userPhrases = <String>['我知道了', '对不起', '以后', '不是故意', '我会'];
    final partnerPhrases = <String>['你每次', '我等了你', '我只是希望', '我不是要'];

    final userTexts = messages
        .where((m) => m.party == Party.a)
        .map((m) => m.content)
        .join(' ');
    final partnerTexts = messages
        .where((m) => m.party == Party.b)
        .map((m) => m.content)
        .join(' ');

    if (text.contains('加班') || text.contains('没电') || text.contains('失联')) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.relationship,
          summary: '关系里反复出现「回复不及时 / 失联」类议题，容易触发等待和不安。',
          source: source,
        ),
      );
    }

    if (userTexts.contains('加班') || userTexts.contains('没电') || userTexts.contains('真的不是故意')) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.profile,
          summary: '用户倾向先解释客观原因，再补充道歉和承诺，冲突中会尝试给出修复动作。',
          source: source,
        ),
      );
    }

    if (partnerTexts.contains('希望你在乎') || partnerTexts.contains('被看见') || partnerTexts.contains('感受')) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.profile,
          summary: 'TA 更在意被重视和被接住的感觉，冲突里常把重点放在情绪和在乎上。',
          source: source,
        ),
      );
    }

    if (userTexts.contains('对不起') || userTexts.contains('以后') || userTexts.contains('我会')) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.growth,
          summary: '这轮对话里出现了修复动作和具体承诺，说明双方至少在尝试往和解方向走。',
          source: source,
        ),
      );
    }

    if (partnerTexts.contains('你要我怎么证明') || partnerTexts.contains('每次都这么说')) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.profile,
          summary: '争执中存在“反复核验 / 反复证明”的模式，信任感有被消耗的迹象。',
          source: source,
        ),
      );
    }

    if (userPhrases.any(userTexts.contains) || partnerPhrases.any(partnerTexts.contains)) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.relationship,
          summary: '本轮对话显示双方已经开始围绕“怎么减少伤害”而不是只盯着输赢。',
          source: '$source · $viewLabel',
        ),
      );
    }

    if (entries.isEmpty) {
      entries.add(
        MemoryEntry(
          kind: MemoryKind.profile,
          summary: '完成了一次「$viewLabel」视角复盘，积累了新的关系样本。',
          source: source,
        ),
      );
    }

    return _dedupe(entries);
  }

  /// 把新观察并入档案（去重：同源同摘要的条目不重复记）。
  MemoryProfile mergeEntries(MemoryProfile memory, List<MemoryEntry> entries) {
    if (entries.isEmpty) return memory;
    final existing = memory.entries.toList();
    for (final entry in entries) {
      final duplicated = existing.any(
        (e) =>
            !e.isDeleted &&
            e.source == entry.source &&
            e.summary == entry.summary,
      );
      if (!duplicated) existing.add(entry);
    }
    return memory.copyWith(entries: existing, updatedAt: DateTime.now());
  }

  List<MemoryEntry> _dedupe(List<MemoryEntry> entries) {
    final result = <MemoryEntry>[];
    for (final entry in entries) {
      final exists = result.any((e) => e.kind == entry.kind && e.summary == entry.summary && e.source == entry.source);
      if (!exists) result.add(entry);
    }
    return result;
  }

  String _viewLabel(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '争爱';
      case BattleView.right:
        return '争对错';
      case BattleView.win:
        return '争输赢';
    }
  }
}
