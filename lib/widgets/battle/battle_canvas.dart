import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/mode_theme.dart';
import '../cards/analysis_card.dart';

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
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 118, 16, 236),
      // 空对话保持空白：新建页面的引导样式后续再设计（见产品文档 3.1.2）。
      children: [
        ...widget.state.cards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BattleAnalysisCard(card: card, mode: widget.mode),
          ),
        ),
      ],
    );
  }
}

