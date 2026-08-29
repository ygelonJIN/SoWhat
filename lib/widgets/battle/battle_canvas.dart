import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/app_providers.dart';
import '../../theme/mode_theme.dart';
import '../cards/analysis_card.dart';
import '../thinking/thinking_panel.dart';

/// 聊天主内容区：仅保留分析卡片。
///
/// 截图卡牌现在是 `BattleScreen` 顶部的常驻覆盖层，不再出现在滚动内容里。
class BattleCanvas extends StatefulWidget {
  const BattleCanvas({
    super.key,
    required this.state,
    required this.messages,
    required this.mode,
    required this.scrollController,
    this.onScroll,
  });

  final BattleState state;
  final List<Message> messages;

  /// 当前模式主题（由外层传入，避免空对话时取到默认视角的主题）。
  final ModeTheme mode;

  final ScrollController scrollController;
  final VoidCallback? onScroll;

  @override
  State<BattleCanvas> createState() => _BattleCanvasState();
}

class _BattleCanvasState extends State<BattleCanvas> {
  @override
  void initState() {
    super.initState();
    _attachScrollListener();
  }

  @override
  void didUpdateWidget(covariant BattleCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController ||
        oldWidget.onScroll != widget.onScroll) {
      _detachScrollListener(oldWidget);
      _attachScrollListener();
    }
  }

  void _attachScrollListener() {
    if (widget.onScroll != null) {
      widget.scrollController.addListener(widget.onScroll!);
    }
  }

  void _detachScrollListener(BattleCanvas oldWidget) {
    if (oldWidget.onScroll != null) {
      oldWidget.scrollController.removeListener(oldWidget.onScroll!);
    }
  }

  @override
  void dispose() {
    _detachScrollListener(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final conversationId = widget.messages.isEmpty
            ? ref.read(selectedConversationIdProvider) ?? ''
            : widget.messages.first.conversationId;
        final thinkingKey = '$conversationId:${widget.mode.view.name}';
        final status = ref.watch(thinkingStatusProvider(thinkingKey));
        final content = ref.watch(thinkingContentProvider(thinkingKey));
        final startedAt = ref.watch(thinkingStartedAtProvider(thinkingKey));
        final finishedAt = ref.watch(thinkingFinishedAtProvider(thinkingKey));
        final expanded = ref.watch(thinkingExpandedProvider(thinkingKey));
        final showThinking = status != ThinkingStatus.idle;
        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 118, 16, 236),
          children: [
            if (showThinking)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ThinkingPanel(
                  mode: widget.mode,
                  status: status,
                  content: content,
                  expanded: expanded,
                  startedAt: startedAt,
                  finishedAt: finishedAt,
                  onToggle: () {
                    ref
                            .read(
                              thinkingExpandedProvider(thinkingKey).notifier,
                            )
                            .state =
                        !expanded;
                  },
                ),
              ),
            if (widget.messages.isEmpty &&
                widget.state.cards.isEmpty &&
                !showThinking)
              _EmptyBattleState(mode: widget.mode),
            ...widget.state.cards.map(
              (card) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: BattleAnalysisCard(card: card, mode: widget.mode),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 对话还没有任何内容时的空白态：每个模式三行引文，不带图标。
class _EmptyBattleState extends StatelessWidget {
  const _EmptyBattleState({required this.mode});

  final ModeTheme mode;

  static ({String line1, String line2, String line3}) _for(BattleView view) {
    switch (view) {
      case BattleView.love:
        return (line1: '靠近一点，慢慢说。', line2: '我听见的，不只是你的话。', line3: 'love soft.');
      case BattleView.right:
        return (line1: '剥离情绪，只看事实。', line2: '放心，只偏袒真相。', line3: 'love hard.');
      case BattleView.win:
        return (line1: '胜负落定之后。', line2: '爱已经失去位置。', line3: 'love gone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _for(mode.view);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 200, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.line1,
            style: TextStyle(
              color: mode.text,
              fontSize: 24,
              fontWeight: mode.strongWeight,
              height: 1,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            c.line2,
            style: TextStyle(color: mode.textMuted, fontSize: 20, height: 1),
          ),
          const SizedBox(height: 20),
          Text(
            c.line3,
            style: TextStyle(
              color: mode.primary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
