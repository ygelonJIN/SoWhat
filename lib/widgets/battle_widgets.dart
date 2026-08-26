import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/mode_theme.dart';

/// 根据当前模式分发顶部战场视觉。
///
/// 当前版本不再展示树 / 天平 / VS 作为主视觉；页面采用纯色背景，
/// 这里仅保留可复用的卡片 / 标题组件。
class ModeVisual extends StatelessWidget {
  const ModeVisual({super.key, required this.state});

  final BattleState state;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class BattleAnalysisCard extends StatelessWidget {
  const BattleAnalysisCard({super.key, required this.card, required this.mode});

  final BattleCard card;
  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = mode.cardRadius;

    final cardColor = switch (mode.view) {
      BattleView.win => const Color(0xFF16161A),
      BattleView.right => const Color(0xFF2D2A24),
      BattleView.love => const Color(0xFF5B7F50),
    };
    final titleColor = switch (mode.view) {
      BattleView.win => const Color(0xFF9C9CA6),
      BattleView.right => const Color(0xFFE0AE40),
      BattleView.love => Colors.white,
    };
    final bodyColor = switch (mode.view) {
      BattleView.win => Colors.white,
      BattleView.right => const Color(0xFFF2E9D6),
      BattleView.love => Colors.white,
    };
    final mutedColor = switch (mode.view) {
      BattleView.win => const Color(0xFF9C9CA6),
      BattleView.right => const Color(0xFFB09B74),
      BattleView.love => const Color(0xFFD9E8D4),
    };
    final borderColor = switch (mode.view) {
      BattleView.win => Colors.white.withValues(alpha: 0.22),
      BattleView.right => const Color(0xFFE0AE40).withValues(alpha: 0.4),
      BattleView.love => Colors.white.withValues(alpha: 0.18),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: mode.view == BattleView.win ? 0.35 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: titleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                card.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            card.conclusion,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: bodyColor,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '依据：${card.evidence}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mutedColor,
              height: 1.4,
            ),
          ),
          if (card.speculation != null) ...[
            const SizedBox(height: 6),
            Text(
              '推测：${card.speculation}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedColor,
                height: 1.4,
              ),
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
