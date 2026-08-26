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
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  String get viewDisplayText {
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
