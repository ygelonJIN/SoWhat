import 'package:flutter/material.dart';

class BattlePreview extends StatelessWidget {
  const BattlePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '实时战场预览',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _BattleRow(label: '争爱', left: 0.56, right: 0.52, accent: scheme.tertiary),
          const SizedBox(height: 10),
          _BattleRow(label: '争对错', left: 0.74, right: 0.26, accent: scheme.primary),
          const SizedBox(height: 10),
          _BattleRow(label: '争输赢', left: 0.81, right: 0.64, accent: scheme.error),
        ],
      ),
    );
  }
}

class _BattleRow extends StatelessWidget {
  const _BattleRow({
    required this.label,
    required this.left,
    required this.right,
    required this.accent,
  });

  final String label;
  final double left;
  final double right;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Text('${(left * 100).round()} / ${(right * 100).round()}'),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: left,
            backgroundColor: accent.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
    );
  }
}
