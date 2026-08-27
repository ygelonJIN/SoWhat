import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/mode_theme.dart';
import '../battle_widgets.dart';

/// 聊天主内容区：仅保留分析卡片。
///
/// 截图卡牌现在是 `BattleScreen` 顶部的常驻覆盖层，不再出现在滚动内容里。
class BattleCanvas extends StatefulWidget {
  const BattleCanvas({
    super.key,
    required this.state,
    required this.messages,
    required this.scrollController,
    this.onScroll,
  });

  final BattleState state;
  final List<Message> messages;
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
    final modeTheme = ModeThemes.of(widget.state.view);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 118, 16, 236),
      children: [
        if (widget.messages.isEmpty)
          _EmptyChatHint(theme: modeTheme)
        else
          ...widget.state.cards.map(
            (card) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BattleAnalysisCard(card: card, mode: modeTheme),
            ),
          ),
      ],
    );
  }
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint({required this.theme});

  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.95 : 0.75),
        borderRadius: theme.cardRadius,
        border: Border.all(color: theme.textMuted.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.24 : 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 34,
            color: theme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '把对话贴进来，或上传截图',
            style: TextStyle(
              color: theme.text,
              fontSize: 15,
              fontWeight: theme.strongWeight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'AI 会从「为爱 / 论对错 / 比输赢」三个视角给出分析。',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.textMuted, height: 1.45, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
