import 'package:flutter/material.dart';

/// 比输赢「切角·撕开一角」装饰系统。
///
/// 与 `RoundedRectangleBorder` / `BoxDecoration` 用法等价的替换件：
/// 当 `fold == false` 时行为和普通圆角矩形一模一样（为爱=圆角、论对错=直角
/// 照旧），当 `fold == true` 时把右上角沿对角线切掉一角，形成「撕开一角」。
/// 切角大小按元素高度比例计算，卡片/输入框/小按钮都会协调缩放。

/// 按元素高度计算切角边长，保证卡片与按钮缩放协调。
double foldCutBy(
  double edge, {
  double factor = 0.30,
  double min = 8,
  double max = 24,
}) {
  return (edge * factor).clamp(min, max).toDouble();
}

/// 右上角切掉的折角路径。
Path buildFoldPath(Size size, double cut) {
  final c = cut.clamp(0.0, size.shortestSide / 2);
  return Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - c, 0)
    ..lineTo(size.width, c)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
}

/// 裁剪折叠区内容（把颜色、描边之下的内容裁成同样折角）。
class FoldClipper extends CustomClipper<Path> {
  const FoldClipper();

  @override
  Path getClip(Size size) => buildFoldPath(size, foldCutBy(size.height));

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) =>
      oldClipper is! FoldClipper;
}

/// 折角形状：`RoundedRectangleBorder` 的等价替换（fold=false 时完全一致）。
///
/// 可直接给 `Material(shape:)`、`InkWell(customBorder:)`、`TextButton` 的
/// `shape:`、`ShapedInputBorder(shape:)` 使用。
class FoldShape extends OutlinedBorder {
  const FoldShape({
    super.side = const BorderSide(),
    this.borderRadius = BorderRadius.zero,
    this.fold = false,
    this.foldFactor = 0.30,
  });

  final BorderRadius borderRadius;
  final bool fold;
  final double foldFactor;

  double _cutFor(double height) =>
      fold ? foldCutBy(height, factor: foldFactor) : 0;

  Path _path(Rect rect, TextDirection? textDirection) {
    final c = _cutFor(rect.height);
    if (c <= 0) {
      return Path()
        ..addRRect(borderRadius.resolve(textDirection).toRRect(rect));
    }
    return buildFoldPath(rect.size, c).shift(rect.topLeft);
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final c = _cutFor(rect.height);
    if (c <= 0) {
      return Path()..addRRect(
        borderRadius.resolve(textDirection).toRRect(rect.deflate(side.width)),
      );
    }
    return buildFoldPath(
      rect.size,
      c + side.width,
    ).shift(rect.topLeft.translate(side.width, -side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect, textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.width <= 0) return;
    final path = _path(rect, textDirection);
    canvas.drawPath(
      path,
      side.toPaint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side.width,
    );
  }

  @override
  FoldShape copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
    bool? fold,
    double? foldFactor,
  }) {
    return FoldShape(
      side: side ?? this.side,
      borderRadius: borderRadius as BorderRadius? ?? this.borderRadius,
      fold: fold ?? this.fold,
      foldFactor: foldFactor ?? this.foldFactor,
    );
  }

  @override
  FoldShape scale(double t) {
    return FoldShape(
      side: side.copyWith(width: side.width * t),
      borderRadius: borderRadius,
      fold: fold,
      foldFactor: foldFactor,
    );
  }
}

/// `Container(decoration: BoxDecoration(...))` 的等价替换。
/// fold=false 时与普通 Container 完全一致（圆角/直角照旧）；
/// fold=true 时右上角切角，并保留阴影、底色、描边与折痕。
class CutBox extends StatelessWidget {
  const CutBox({
    super.key,
    required this.fold,
    this.color,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.borderColor,
    this.foldFactor = 0.30,
    this.padding,
    this.child,
    this.width,
    this.height,
    this.alignment,
    this.clipBehavior = Clip.none,
  });

  final bool fold;
  final Color? color;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final Color? borderColor;
  final double foldFactor;
  final EdgeInsetsGeometry? padding;
  final Widget? child;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    if (!fold || border == null) {
      return Container(
        width: width,
        height: height,
        padding: padding,
        alignment: alignment,
        clipBehavior: clipBehavior,
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: border,
          boxShadow: boxShadow,
        ),
        child: child,
      );
    }

    final stroke = border!.top.color;
    final strokeW = border!.top.width.isFinite ? border!.top.width : 1.0;
    return Container(
      width: width,
      height: height,
      alignment: alignment,
      decoration: BoxDecoration(
        boxShadow: boxShadow ?? const [],
        color: Colors.transparent,
      ),
      child: ClipPath(
        clipper: const FoldClipper(),
        child: CustomPaint(
          foregroundPainter: stroke.a > 0
              ? _FoldOutlinePainter(
                  strokeColor: borderColor ?? stroke,
                  strokeWidth: strokeW,
                )
              : null,
          child: Container(
            color: color ?? Colors.transparent,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FoldOutlinePainter extends CustomPainter {
  const _FoldOutlinePainter({
    required this.strokeColor,
    required this.strokeWidth,
  });

  final Color strokeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokeColor.a <= 0) return;
    final path = buildFoldPath(size, foldCutBy(size.height));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = strokeColor
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant _FoldOutlinePainter old) =>
      old.strokeColor != strokeColor || old.strokeWidth != strokeWidth;
}
