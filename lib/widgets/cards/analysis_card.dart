import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/mode_theme.dart';

/// 单张分析卡片：标题 + 结论 + 依据 + 推测。
///
/// 视觉完全由 `ModeTheme` 的 `card*` 令牌驱动，三个模式各有一套配色
/// （背景 / 标题 / 正文 / 弱化文字 / 边框 / 阴影）。
class BattleAnalysisCard extends StatefulWidget {
  const BattleAnalysisCard({super.key, required this.card, required this.mode});

  final BattleCard card;
  final ModeTheme mode;

  @override
  State<BattleAnalysisCard> createState() => _BattleAnalysisCardState();
}

class _BattleAnalysisCardState extends State<BattleAnalysisCard> {
  bool _evidenceExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = widget.card;
    final mode = widget.mode;

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
          const SizedBox(height: 8),
          _EvidenceDisclosure(
            mode: mode,
            evidence: card.evidence,
            speculation: card.speculation,
            expanded: _evidenceExpanded,
            onToggle: () =>
                setState(() => _evidenceExpanded = !_evidenceExpanded),
          ),
        ],
      ),
    );
  }
}

class _EvidenceDisclosure extends StatelessWidget {
  const _EvidenceDisclosure({
    required this.mode,
    required this.evidence,
    required this.speculation,
    required this.expanded,
    required this.onToggle,
  });

  final ModeTheme mode;
  final String evidence;
  final String? speculation;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final hasSpeculation = speculation?.trim().isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_right_rounded,
                    size: 15,
                    color: mode.cardMuted,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '依据',
                  style: TextStyle(color: mode.cardMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6, left: 5),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: mode.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: mode.cardBorder.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evidence.trim().isEmpty ? '暂无可对应的原文依据' : evidence,
                    style: TextStyle(
                      color: mode.cardMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                  if (hasSpeculation) ...[
                    const SizedBox(height: 6),
                    Text(
                      '推测：$speculation',
                      style: TextStyle(
                        color: mode.cardMuted,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}
