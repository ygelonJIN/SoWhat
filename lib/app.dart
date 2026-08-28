import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/battle_screen.dart';
import 'theme/mode_theme.dart';

class SoWhatApp extends ConsumerWidget {
  const SoWhatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(selectedBattleViewProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'So What',
      // 全局主题跟随当前模式：任何页面（含未来新增页面、push 出来的路由）
      // 都会自动继承模式视觉风格，无需各自再写一套。
      theme: ModeThemes.of(view).themeData,
      home: const BattleScreen(),
    );
  }
}
