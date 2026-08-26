import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../widgets/empty_state.dart';

/// 预留的历史对话列表，当前不在主导航中展示。
class CaseListScreen extends ConsumerWidget {
  const CaseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final casesAsync = ref.watch(casesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('历史对话')),
      body: casesAsync.when(
        data: (cases) {
          if (cases.isEmpty) {
            return const EmptyState(
              icon: Icons.forum_outlined,
              title: '还没有历史对话',
              subtitle: '之后的对话会自动保存在这里。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: cases.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = cases[index];
              return ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Text(item.displayTitle),
                subtitle: Text(item.displayDate),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('加载失败：$error')),
      ),
    );
  }
}
