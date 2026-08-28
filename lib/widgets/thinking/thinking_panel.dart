import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/thinking.dart';
import '../../theme/mode_theme.dart';

/// 思考过程框（符合主题规范：跟随 ModeTheme）。
///
/// 特性：
/// - 两种状态：思考中 / 思考完成（idle 时不渲染）
/// - 右侧持续计时，思考完成停止
/// - 点击头部可展开/收起；默认展开，完成后自动收起
/// - 内容区最大高度 260，内部可滚动；默认锁定底部跟随新增内容
/// - 用户向上滑动 → 解除锁定；再次滑到底部 → 重新锁定
class ThinkingPanel extends StatefulWidget {
  const ThinkingPanel({
    super.key,
    required this.mode,
    required this.status,
    required this.content,
    required this.expanded,
    required this.startedAt,
    required this.onToggle,
  });

  final ModeTheme mode;
  final ThinkingStatus status;
  final String content;
  final bool expanded;
  final DateTime? startedAt;
  final VoidCallback onToggle;

  @override
  State<ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<ThinkingPanel> {
  final _scrollController = ScrollController();
  bool _autoFollow = true;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  static const _maxHeight = 260.0;
  static const _bottomThreshold = 24.0;

  @override
  void initState() {
    super.initState();
    _maybeStartTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomIfNeeded());
  }

  @override
  void didUpdateWidget(covariant ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.startedAt != widget.startedAt) {
      _maybeStartTicker();
    }
    if (oldWidget.content != widget.content) {
      if (_autoFollow) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomIfNeeded());
      }
    }
    if (oldWidget.expanded != widget.expanded && widget.expanded) {
      _autoFollow = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomIfNeeded());
    }
  }

  void _maybeStartTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.status == ThinkingStatus.thinking && widget.startedAt != null) {
      _elapsed = DateTime.now().difference(widget.startedAt!);
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (widget.status != ThinkingStatus.thinking || widget.startedAt == null) {
          _ticker?.cancel();
          return;
        }
        setState(() => _elapsed = DateTime.now().difference(widget.startedAt!));
      });
    } else if (widget.status == ThinkingStatus.done && widget.startedAt != null) {
      final frozen = DateTime.now().difference(widget.startedAt!);
      if (_elapsed != frozen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _elapsed = frozen);
        });
      }
    } else {
      _elapsed = Duration.zero;
    }
  }

  void _jumpToBottomIfNeeded() {
    if (!_autoFollow) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final target = pos.maxScrollExtent;
    // 已在底部附近则不重复跳转，避免抖动
    if ((pos.pixels - target).abs() < 2) return;
    _scrollController.jumpTo(target);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
      if (!_scrollController.hasClients) return false;
      final pos = _scrollController.position;
      final atBottom = pos.pixels >= pos.maxScrollExtent - _bottomThreshold;
      final newFollow = atBottom;
      if (newFollow != _autoFollow) {
        setState(() => _autoFollow = newFollow);
      }
    }
    return false;
  }

  String _formatElapsed(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds < 60) return '${totalSeconds}s';
    final m = d.inMinutes;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == ThinkingStatus.idle) return const SizedBox.shrink();

    final isThinking = widget.status == ThinkingStatus.thinking;
    final statusText = isThinking ? '思考中' : '思考完成';
    final timeText = widget.startedAt == null ? '--' : _formatElapsed(_elapsed);

    return Container(
      decoration: BoxDecoration(
        color: widget.mode.cardBackground,
        borderRadius: widget.mode.cardRadius,
        border: Border.all(color: widget.mode.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.mode.cardShadowAlpha),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：状态 + 计时 + 展开指示
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                child: Row(
                  children: [
                    if (isThinking)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.mode.primary,
                        ),
                      )
                    else
                      Icon(Icons.check_circle_rounded, size: 16, color: widget.mode.primary),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: widget.mode.cardTitle,
                        fontSize: 13.5,
                        fontWeight: widget.mode.strongWeight,
                      ),
                    ),
                    if (isThinking) ...[
                      const SizedBox(width: 6),
                      _ThinkingDots(color: widget.mode.cardMuted),
                    ],
                    const Spacer(),
                    Text(
                      timeText,
                      style: TextStyle(
                        color: widget.mode.cardMuted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: widget.expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: widget.mode.cardMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 内容区（可折叠）
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, thickness: 1, color: widget.mode.cardBorder.withValues(alpha: 0.6)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _maxHeight),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: _buildContent(),
                      ),
                    ),
                  ),
                ),
                if (!_autoFollow)
                  GestureDetector(
                    onTap: () {
                      setState(() => _autoFollow = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottomIfNeeded());
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.mode.primary.withValues(alpha: 0.08),
                        border: Border(top: BorderSide(color: widget.mode.cardBorder.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_downward_rounded, size: 12, color: widget.mode.primary),
                          const SizedBox(width: 4),
                          Text(
                            '回到最新',
                            style: TextStyle(color: widget.mode.primary, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            crossFadeState: widget.expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final text = widget.content.trim();
    if (text.isEmpty) {
      return Text(
        widget.status == ThinkingStatus.thinking ? '正在理解对话与记忆…' : '—',
        style: TextStyle(color: widget.mode.cardMuted, fontSize: 12.5, height: 1.6),
      );
    }
    return Text(
      text,
      style: TextStyle(color: widget.mode.cardBody, fontSize: 12.5, height: 1.65),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.color});
  final Color color;
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        double opacity(int i) {
          final phase = (t * 3) % 3;
          final dist = (phase - i).abs();
          if (dist < 0.6) return 1;
          if (dist < 1.2) return 0.45;
          return 0.2;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: Opacity(
                opacity: opacity(i),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
