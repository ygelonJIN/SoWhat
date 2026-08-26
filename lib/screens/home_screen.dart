import 'package:flutter/material.dart';

import '../widgets/battle_preview.dart';
import '../widgets/feature_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onOpenCases, this.onOpenBattle, this.onOpenImport});

  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenBattle;
  final VoidCallback? onOpenImport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroHeader(
              onOpenCases: onOpenCases,
              onOpenBattle: onOpenBattle,
              onOpenImport: onOpenImport,
            ),
            const SizedBox(height: 20),
            const BattlePreview(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '核心功能',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                TextButton(
                  onPressed: onOpenBattle,
                  child: const Text('进入战场'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const FeatureCard(
              icon: Icons.photo_library_outlined,
              title: '截图 / 复制导入',
              subtitle: '把聊天记录直接搬进来，保留证据源。',
            ),
            const SizedBox(height: 12),
            const FeatureCard(
              icon: Icons.hub_outlined,
              title: '三种语气分析',
              subtitle: '冷血判官、中立分析、温柔哄人。',
            ),
            const SizedBox(height: 12),
            const FeatureCard(
              icon: Icons.explore_outlined,
              title: '实时战场',
              subtitle: '争爱 / 争对错 / 争输赢三视角即时拆解。',
            ),
            const SizedBox(height: 12),
            const FeatureCard(
              icon: Icons.lock_outline,
              title: '本地优先',
              subtitle: '数据留在手机里，AI 分析按需联网。',
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({this.onOpenCases, this.onOpenBattle, this.onOpenImport});

  final VoidCallback? onOpenCases;
  final VoidCallback? onOpenBattle;
  final VoidCallback? onOpenImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.2),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '爱·对·赢',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Love > Right > Win',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 18),
          Text(
            '让 AI 做情侣吵架时的第三方，把爱放回第一位。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.92),
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Pill(label: 'A/B 匿名化', onTap: onOpenCases),
              _Pill(label: '本地优先', onTap: onOpenImport),
              _Pill(label: '证据可溯源', onTap: onOpenBattle),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.26)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
