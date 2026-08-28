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
        final status = ref.watch(thinkingStatusProvider);
        final content = ref.watch(thinkingContentProvider);
        final startedAt = ref.watch(thinkingStartedAtProvider);
        final expanded = ref.watch(thinkingExpandedProvider);
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
                  onToggle: () {
                    ref.read(thinkingExpandedProvider.notifier).state = !expanded;
                  },
                ),
              ),
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

