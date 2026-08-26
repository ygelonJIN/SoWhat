import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          EmptyState(
            icon: Icons.settings_outlined,
            title: '设置页占位',
            subtitle: '后续这里会加入 API Key、默认模式、导出配置等选项。',
          ),
        ],
      ),
    );
  }
}
