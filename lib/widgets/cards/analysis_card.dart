import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/mode_theme.dart';

/// 单张分析卡片：标题 + 结论 + 依据 + 推测。
///
/// 视觉完全由 `ModeTheme` 的 `card*` 令牌驱动，三个模式各有一套配色
/// （背景 / 标题 / 正文 / 弱化文字 / 边框 / 阴影）。
class BattleAnalysisCard extends StatelessWidget {
  const BattleAnalysisCard({super.key, required this.card, required this.mode});

  final BattleCard card;
  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mode.cardBackground,
        borderRadius: mode.cardRadius,
        border: Border.all(color: mode.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: mode.cardShadowAlpha),
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
                  color: mode.cardTitle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                card.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: mode.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            card.conclusion,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: mode.cardBody,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '依据：${card.evidence}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: mode.cardMuted,
              height: 1.4,
            ),
          ),
          if (card.speculation != null) ...[
            const SizedBox(height: 6),
            Text(
              '推测：${card.speculation}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: mode.cardMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
