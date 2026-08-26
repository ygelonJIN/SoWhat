import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../widgets/battle/battle_canvas.dart';

class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _conversationId = 'current-conversation';

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await ref.read(repositoryActionsProvider).addMessage(
          conversationId: _conversationId,
          party: Party.a,
          content: text,
        );
    _messageController.clear();
  }

  Future<void> _selectView(BattleView view) async {
    ref.read(selectedBattleViewProvider.notifier).state = view;
    await ref.read(repositoryActionsProvider).setBattleView(view);
  }

  @override
  Widget build(BuildContext context) {
    final battleAsync = ref.watch(battleStateProvider);
    final selectedView = ref.watch(selectedBattleViewProvider);
    final messagesAsync = ref.watch(conversationMessagesProvider(_conversationId));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ChatTopBar(onSettings: () {}),
            Expanded(
              child: battleAsync.when(
                data: (battle) => BattleCanvas(
                  state: battle,
                  messages: messagesAsync.valueOrNull ?? const [],
                  scrollController: _scrollController,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('加载失败：$error')),
              ),
            ),
            _ModePicker(selectedView: selectedView, onSelected: _selectView),
            _ChatComposer(
              controller: _messageController,
              onSend: _sendMessage,
              onAttach: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.tune_rounded),
            tooltip: '设置（即将开放）',
          ),
          const SizedBox(width: 4),
          Text(
            '爱·对·赢',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          Text(
            date,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.black54,
                ),
          ),
        ],
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.selectedView, required this.onSelected});

  final BattleView selectedView;
  final ValueChanged<BattleView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<BattleView>(
          initialValue: selectedView,
          onSelected: onSelected,
          tooltip: '切换分析视角',
          itemBuilder: (context) => const [
            PopupMenuItem(value: BattleView.love, child: Text('争爱')),
            PopupMenuItem(value: BattleView.right, child: Text('争对错')),
            PopupMenuItem(value: BattleView.win, child: Text('争输赢')),
          ],
          child: Chip(
            avatar: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            label: Text(_viewLabel(selectedView)),
          ),
        ),
      ),
    );
  }

  String _viewLabel(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '争爱';
      case BattleView.right:
        return '争对错';
      case BattleView.win:
        return '争输赢';
    }
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '把对话贴进来，或发一张截图…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onAttach,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '上传截图',
                ),
                IconButton(
                  onPressed: onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: '发送',
                ),
              ],
            ),
          ),
          onSubmitted: (_) => onSend(),
        ),
      ),
    );
  }
}
