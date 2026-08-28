import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mode_theme.dart';

/// 常驻悬浮的截图卡牌扇，叠在聊天内容上方、日期按钮正下方。
///
/// 三个层次：
/// 1. 最小收起态
/// 2. 稍微放大一点的收起态
/// 3. 单张图片大图查看
class ImageFanGallery extends StatefulWidget {
  const ImageFanGallery({
    super.key,
    required this.paths,
    required this.mode,
    this.onPeekChanged,
    this.onRemove,
  });

  final List<String> paths;
  final ModeTheme mode;
  final VoidCallback? onRemove;

  /// 收起态变化时回调（true = 放大收起态，false = 最小收起态）。
  final ValueChanged<bool>? onPeekChanged;

  @override
  State<ImageFanGallery> createState() => ImageFanGalleryState();
}

class ImageFanGalleryState extends State<ImageFanGallery>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 620);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    reverseDuration: _duration,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  bool get _peeked => _controller.value >= 0.5;
  bool _lastReportedPeeked = false;

  void _togglePeeked() {
    if (_controller.isAnimating) return;
    if (_peeked) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  /// 从外部请求收起（例如点击卡片外部区域时）。
  void collapse() {
    if (_peeked) {
      _controller.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handlePeekChanged);
  }

  void _handlePeekChanged() {
    final peeked = _peeked;
    if (peeked != _lastReportedPeeked) {
      _lastReportedPeeked = peeked;
      widget.onPeekChanged?.call(peeked);
    }
  }

  @override
  void dispose() {
    final onPeekChanged = widget.onPeekChanged;
    _controller.dispose();
    super.dispose();
    // 组件被替换/卸载时，通知外部收起态已经复位，避免拦截层残留。
    if (onPeekChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onPeekChanged(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.paths;
    if (paths.isEmpty) return const SizedBox.shrink();

    // 直接按扇面实际内容尺寸布局：不再包一层固定 360x170 的容器，
    // 否则内部 Positioned 卡片会被约束到左侧，卡片位置就会跑偏。
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) => _buildFan(widget.mode, _curve.value),
    );
  }

  Widget _buildFan(ModeTheme mode, double t) {
    final count = widget.paths.length;

    // 最小收起态：比之前再紧凑一点，仍是“攥在手里”的小扇面。
    const collapsedW = 56.0, collapsedH = 72.0;
    const peekedW = 112.0, peekedH = 142.0;
    final cardW = collapsedW + (peekedW - collapsedW) * t;
    final cardH = collapsedH + (peekedH - collapsedH) * t;

    // 展开后仍然保留一点重叠和角度，不会完全拉平。
    const stepCollapsed = 5.0, stepPeeked = 28.0;
    final step = stepCollapsed + (stepPeeked - stepCollapsed) * t;
    const halfSpreadCollapsed = 18.0, halfSpreadPeeked = 12.0;
    final halfSpread =
        halfSpreadCollapsed + (halfSpreadPeeked - halfSpreadCollapsed) * t;

    final contentWidth = cardW + (count - 1) * step;
    final height = cardH + 12;

    const maxWidth = 340.0;
    final scale = math.min(1.0, maxWidth / contentWidth);
    final sCardW = cardW * scale;
    final sCardH = cardH * scale;
    final sStep = step * scale;
    final sContentWidth = contentWidth * scale;
    final sHeight = height * scale;

    final mid = (count - 1) / 2;
    final denom = math.max(mid, 1.0);
    // 与模式按钮的边框颜色保持一致（未选中态）。
    final borderColor = mode.chipBorder;

    return SizedBox(
      width: sContentWidth,
      height: sHeight + (_peeked ? 64 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          if (_peeked)
            Positioned(
              left: (sContentWidth - 40) / 2,
              top: sHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onRemove,
                child: Material(
                  color: mode.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: mode.chipRadius,
                    side: BorderSide(
                      color: mode.primary.withValues(alpha: 0.8),
                      width: 1,
                    ),
                  ),
                  elevation: 3,
                  shadowColor: Colors.black.withValues(alpha: 0.18),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < count; i++)
            Positioned(
              top: 0,
              left: (sContentWidth - sCardW) / 2 + (i - mid) * sStep,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (context, child) {
                  final indexOffset = i - mid;
                  final normalized = indexOffset / denom;
                  final fanAngle = normalized * halfSpread;
                  final lift =
                      (1 - (normalized.abs() * 0.12).clamp(0.0, 0.12)) * t * 3;
                  final translateY =
                      (1 - t) * (indexOffset.abs() * 0.28) - lift;
                  final scaleFactor = 0.96 + t * 0.04;

                  return Transform.translate(
                    offset: Offset(0, translateY),
                    child: Transform.rotate(
                      angle: fanAngle * math.pi / 180,
                      alignment: Alignment.bottomCenter,
                      child: Transform.scale(
                        scale: scaleFactor,
                        alignment: Alignment.bottomCenter,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _FanCard(
                  key: ValueKey(widget.paths[i]),
                  path: widget.paths[i],
                  width: sCardW,
                  height: sCardH,
                  mode: mode,
                  borderColor: borderColor,
                  onTap: _peeked ? () => _openViewer(i) : _togglePeeked,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openViewer(int index) async {
    // 打开大图前收起键盘，避免大图被键盘遮挡。
    FocusManager.instance.primaryFocus?.unfocus();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭大图',
      barrierColor: Colors.black.withValues(alpha: 0.94),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, __) =>
          _FullScreenViewer(paths: widget.paths, initialIndex: index),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  const _FanCard({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    required this.mode,
    required this.borderColor,
    this.onTap,
  });

  final String path;
  final double width;
  final double height;
  final ModeTheme mode;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: borderColor.withValues(alpha: 0.9),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.file(
            File(path),
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(
              color: mode.surface.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: Icon(Icons.broken_image_outlined, color: mode.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenViewer extends StatefulWidget {
  const _FullScreenViewer({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  State<_FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<_FullScreenViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  double _dragDy = 0;

  final Map<int, TransformationController> _controllers = {};

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int index) {
    return _controllers.putIfAbsent(index, () => TransformationController());
  }

  void _toggleZoom(int index) {
    final controller = _controllerFor(index);
    final current = controller.value;
    final isZoomed = current.getMaxScaleOnAxis() > 1.2;
    controller.value = isZoomed
        ? Matrix4.identity()
        : (Matrix4.identity()..scale(2.4));
  }

  void _dismissToGallery() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissToGallery,
        onVerticalDragUpdate: (details) {
          _dragDy += details.primaryDelta ?? 0;
        },
        onVerticalDragEnd: (_) {
          if (_dragDy.abs() > 55) _dismissToGallery();
          _dragDy = 0;
        },
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.paths.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    final controller = _controllerFor(index);
                    return GestureDetector(
                      onDoubleTap: () => _toggleZoom(index),
                      child: InteractiveViewer(
                        transformationController: controller,
                        maxScale: 5,
                        child: Center(
                          child: Image.file(
                            File(widget.paths[index]),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 48,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _dismissToGallery,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.paths.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
