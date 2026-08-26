import 'package:flutter/material.dart';

import '../models/models.dart';

class BattleScoreboard extends StatelessWidget {
  const BattleScoreboard({super.key, required this.state});

  final BattleState state;

  @override
  Widget build(BuildContext context) {
    return _BattleVisualCard(
      title: '争输赢',
      child: Row(
        children: [
          Expanded(
            child: _FighterColumn(
              label: '我',
              hp: state.userHp,
              score: state.userScore,
              color: Colors.redAccent,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'VS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: _FighterColumn(
              label: 'TA',
              hp: state.partnerHp,
              score: state.partnerScore,
              color: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class JusticeScale extends StatelessWidget {
  const JusticeScale({super.key, required this.state});

  final BattleState state;

  @override
  Widget build(BuildContext context) {
    final balance = state.justiceBalance.clamp(-1.0, 1.0);
    return _BattleVisualCard(
      title: '争对错',
      child: Column(
        children: [
          Text(
            balance < 0
                ? '目前更偏向我'
                : balance > 0
                ? '目前更偏向 TA'
                : '目前势均力敌',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 18,
                  child: Transform.rotate(
                    angle: balance * 0.25,
                    child: Container(
                      width: 220,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 132,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Positioned(
                  top: 70 + balance * 20,
                  left: 36,
                  child: const _ScalePan(label: '我', tint: Colors.redAccent),
                ),
                Positioned(
                  top: 70 - balance * 20,
                  right: 36,
                  child: const _ScalePan(label: 'TA', tint: Colors.blueAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoveTree extends StatelessWidget {
  const LoveTree({super.key, required this.state});

  final BattleState state;

  @override
  Widget build(BuildContext context) {
    final growth = ((state.userLove + state.partnerLove) / 2).clamp(0.0, 1.0);
    return _BattleVisualCard(
      title: '争爱',
      child: Column(
        children: [
          Text(
            growth > 0.65
                ? '关系正在抽芽'
                : growth > 0.45
                ? '树还活着，需要一起浇水'
                : '先照顾关系，再继续争论',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 16,
                  height: 66 + growth * 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8D5A3B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Positioned(
                  bottom: 54 + growth * 34,
                  child: Container(
                    width: 110 + growth * 46,
                    height: 78 + growth * 18,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFFB6DD84),
                        const Color(0xFF3A9142),
                        growth,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WaterDrop(active: state.userLove > 0.45),
                      const SizedBox(width: 18),
                      _WaterDrop(active: state.partnerLove > 0.45),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BattleAnalysisCard extends StatelessWidget {
  const BattleAnalysisCard({super.key, required this.card});

  final BattleCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(card.conclusion),
          const SizedBox(height: 10),
          Text(
            '依据：${card.evidence}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          if (card.speculation != null) ...[
            const SizedBox(height: 8),
            Text(
              '推测：${card.speculation}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _BattleVisualCard extends StatelessWidget {
  const _BattleVisualCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          child,
        ],
      ),
    );
  }
}

class _FighterColumn extends StatelessWidget {
  const _FighterColumn({
    required this.label,
    required this.hp,
    required this.score,
    required this.color,
  });

  final String label;
  final double hp;
  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          minHeight: 12,
          value: hp.clamp(0.0, 1.0),
          backgroundColor: color.withValues(alpha: 0.14),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        const SizedBox(height: 6),
        Text(
          '${score.round()} 分',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _ScalePan extends StatelessWidget {
  const _ScalePan({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 42,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tint.withOpacity(0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(color: tint, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _WaterDrop extends StatelessWidget {
  const _WaterDrop({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.water_drop_rounded,
      color: active ? Colors.lightBlue : Colors.black12,
      size: 26,
    );
  }
}
