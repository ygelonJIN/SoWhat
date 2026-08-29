import 'enums.dart';

/// 聊天框顶部的三视角可视化状态。
class BattleState {
  final BattleView view;
  final double userScore;
  final double partnerScore;
  final double userHp;
  final double partnerHp;
  final double userLove;
  final double partnerLove;
  final double justiceBalance;
  final String headline;
  final List<BattleCard> cards;
  final DateTime updatedAt;
  final String? thinkingContent;
  final DateTime? thinkingStartedAt;
  final DateTime? thinkingFinishedAt;
  final bool thinkingActive;

  const BattleState({
    required this.view,
    required this.userScore,
    required this.partnerScore,
    required this.userHp,
    required this.partnerHp,
    required this.userLove,
    required this.partnerLove,
    required this.justiceBalance,
    required this.headline,
    required this.cards,
    required this.updatedAt,
    this.thinkingContent,
    this.thinkingStartedAt,
    this.thinkingFinishedAt,
    this.thinkingActive = false,
  });

  factory BattleState.initial([BattleView view = BattleView.love]) {
    return BattleState(
      view: view,
      userScore: 50,
      partnerScore: 50,
      userHp: 1,
      partnerHp: 1,
      userLove: 0.5,
      partnerLove: 0.5,
      justiceBalance: 0,
      headline: '把对话发进来，我会从这个视角陪你们一起看。',
      cards: const [],
      updatedAt: DateTime.now(),
    );
  }

  BattleState copyWith({
    BattleView? view,
    double? userScore,
    double? partnerScore,
    double? userHp,
    double? partnerHp,
    double? userLove,
    double? partnerLove,
    double? justiceBalance,
    String? headline,
    List<BattleCard>? cards,
    DateTime? updatedAt,
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool? thinkingActive,
  }) {
    return BattleState(
      view: view ?? this.view,
      userScore: userScore ?? this.userScore,
      partnerScore: partnerScore ?? this.partnerScore,
      userHp: userHp ?? this.userHp,
      partnerHp: partnerHp ?? this.partnerHp,
      userLove: userLove ?? this.userLove,
      partnerLove: partnerLove ?? this.partnerLove,
      justiceBalance: justiceBalance ?? this.justiceBalance,
      headline: headline ?? this.headline,
      cards: cards ?? this.cards,
      updatedAt: updatedAt ?? this.updatedAt,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      thinkingStartedAt: thinkingStartedAt ?? this.thinkingStartedAt,
      thinkingFinishedAt: thinkingFinishedAt ?? this.thinkingFinishedAt,
      thinkingActive: thinkingActive ?? this.thinkingActive,
    );
  }

  String get modeTitle {
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

class BattleCard {
  final String title;
  final String conclusion;
  final String evidence;
  final String? speculation;

  const BattleCard({
    required this.title,
    required this.conclusion,
    required this.evidence,
    this.speculation,
  });
}