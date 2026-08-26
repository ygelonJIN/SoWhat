import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          EmptyState(
            icon: Icons.cloud_upload_outlined,
            title: '导入流程正在搭建',
            subtitle: '后续这里会支持截图多选、复制粘贴解析和逐条确认。',
          ),
        ],
      ),
    );
  }
}
