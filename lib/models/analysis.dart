import 'package:uuid/uuid.dart';

import 'enums.dart';

/// 一轮三视角分析结果。
class Analysis {
  final String id;
  final String conversationId;
  final BattleView view;
  final AiChannel channel;
  final String? modelName;
  final String content;
  final List<AnalysisCard> cards;
  final DateTime createdAt;
  final int tokenCount;
  final Duration? duration;

  /// 同一对话下的同一次发送轮次，用于区分并行模式分析。
  final String turnId;

  /// 被「更新记忆」消化的时间；为空表示尚未进入记忆档案。
  final DateTime? memoryProcessedAt;

  /// 模型产出的战况小结（输出契约 JSON 的 `headline` 字段），随卡片一起
  /// 解析、持久化；渲染由 `BattleState.summary` 承载。
  final String? summary;

  Analysis({
    String? id,
    required this.conversationId,
    required this.view,
    required this.channel,
    this.modelName,
    required this.content,
    this.cards = const [],
    DateTime? createdAt,
    this.tokenCount = 0,
    this.duration,
    this.turnId = '',
    this.memoryProcessedAt,
    this.summary,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Analysis copyWith({
    String? conversationId,
    String? turnId,
    DateTime? memoryProcessedAt,
  }) {
    return Analysis(
      id: id,
      conversationId: conversationId ?? this.conversationId,
      view: view,
      channel: channel,
      modelName: modelName,
      content: content,
      cards: cards,
      createdAt: createdAt,
      tokenCount: tokenCount,
      duration: duration,
      turnId: turnId ?? this.turnId,
      memoryProcessedAt: memoryProcessedAt ?? this.memoryProcessedAt,
      summary: summary,
    );
  }

  String get viewDisplayText {
    switch (view) {
      case BattleView.love:
        return '为爱';
      case BattleView.right:
        return '论对错';
      case BattleView.win:
        return '比输赢';
    }
  }
}

/// 分析留白区中的一个维度卡片。
class AnalysisCard {
  final String title;
  final String conclusion;
  final String? evidence;
  final String? speculation;

  const AnalysisCard({
    required this.title,
    required this.conclusion,
    this.evidence,
    this.speculation,
  });
}