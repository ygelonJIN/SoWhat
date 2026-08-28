import 'package:flutter/material.dart';

import '../models/models.dart';

/// 单个模式的完整视觉体系。
///
/// 三模式共用同一套「令牌 → 用法」逻辑（背景 / 表面 / 卡片 / 输入框 / 按钮 /
/// 文字的可读性规则完全一致，任何页面在三模式下都可读），只保留各自的配色
/// 个性与形状特征：为爱=圆润暖绿、论对错=方正暗金、比输赢=斜切黑白。
class ModeTheme {
  const ModeTheme({
    required this.view,
    required this.title,
    required this.tagline,
    required this.background,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.mineBubble,
    required this.mineText,
    required this.text,
    required this.textMuted,
    required this.inputRadius,
    required this.cardRadius,
    required this.chipRadius,
    required this.cardBackground,
    required this.cardTitle,
    required this.cardBody,
    required this.cardMuted,
    required this.cardBorder,
    required this.cardShadowAlpha,
    required this.chipBackground,
    required this.chipForeground,
    required this.chipBorder,
    required this.actionChipBackground,
    required this.actionChipForeground,
    required this.actionChipBorder,
    required this.inputBorderColor,
    this.inputBorderWidth = 0,
    this.fontFamily,
    this.fontFamilyFallback = const <String>[],
    this.strongWeight = FontWeight.w800,
  });

  final BattleView view;

  /// 模式名：争爱 / 争对错 / 争输赢。
  final String title;

  /// 战场视觉的名字：共育之树 / 法庭之秤 / 胜负之局。
  final String tagline;

  final Color background;
  final Color surface;
  final Color primary;
  final Color onPrimary;

  /// 「我」的消息气泡底色与文字色。
  final Color mineBubble;
  final Color mineText;

  final Color text;
  final Color textMuted;

  /// 输入框圆角（争爱全圆、争对错直角、争输赢斜切）。
  final BorderRadius inputRadius;

  /// 卡片 / 气泡圆角。
  final BorderRadius cardRadius;

  /// 浮动模式按钮 / 发送按钮的切角。
  final BorderRadius chipRadius;

  /// 分析卡片色组（BattleAnalysisCard 专用）。
  final Color cardBackground;
  final Color cardTitle;
  final Color cardBody;
  final Color cardMuted;
  final Color cardBorder;

  /// 分析卡片阴影强度。
  final double cardShadowAlpha;

  /// 通用胶囊按钮（未选中态）——已含 0.92 背景 / 0.74 前景透明度。
  final Color chipBackground;
  final Color chipForeground;

  /// 胶囊按钮边框色（不透明底色，状态透明度由组件叠加）。
  final Color chipBorder;

  /// 主要操作芯片（发送 / 附着按钮；win 模式为白底反色）。
  final Color actionChipBackground;
  final Color actionChipForeground;
  final Color actionChipBorder;

  final Color inputBorderColor;
  final double inputBorderWidth;

  /// 各模式专属中文字体（随 App 打包的开源字体，iOS/Android 均可渲染中文）。
  ///
  /// 全局生效：`themeData.fontFamily` 驱动所有文字（含空白态、输入框、提示语）。
  /// `fontFamilyFallback` 供主字体缺失的字形回退到系统字体，避免缺字。
  final String? fontFamily;

  /// 主字体不可用时的回退字体族（按优先级）。
  final List<String> fontFamilyFallback;
  final FontWeight strongWeight;

  bool get isDark =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

  ThemeData get themeData {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          surface: surface,
          onSurface: text,
          onSurfaceVariant: textMuted,
          primaryContainer: mineBubble,
          onPrimaryContainer: mineText,
          secondaryContainer: mineBubble,
          onSecondaryContainer: mineText,
          outline: textMuted.withValues(alpha: 0.5),
          outlineVariant: textMuted.withValues(alpha: 0.25),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: chipBackground,
        hintStyle: TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.26),
        selectionHandleColor: primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text),
      ),
      dividerColor: textMuted.withValues(alpha: 0.25),
    );
  }
}

/// 三模式的预置主题。
abstract final class ModeThemes {
  /// 为爱：暖纸色 · 圆润 · 楷体（霞鹜文楷）——「共育之树」。
  static const love = ModeTheme(
    view: BattleView.love,
    title: '为爱',
    tagline: '共育之树',
    background: Color(0xFFFAF3E6),
    surface: Color(0xFFF1F7EC),
    primary: Color(0xFF4F7B49),
    onPrimary: Colors.white,
    mineBubble: Color(0xFF6B9E5A),
    mineText: Color(0xFFF8FBF6),
    text: Color(0xFF2F3A2A),
    textMuted: Color(0xFF6F7D68),
    inputRadius: BorderRadius.all(Radius.circular(999)),
    cardRadius: BorderRadius.all(Radius.circular(26)),
    chipRadius: BorderRadius.all(Radius.circular(999)),
    cardBackground: Color(0xFFF1F7EC),
    cardTitle: Color(0xFF4F7B49),
    cardBody: Color(0xFF2F3A2A),
    cardMuted: Color(0xFF5F7057),
    cardBorder: Color(0x5E4F7B49),
    cardShadowAlpha: 0.10,
    chipBackground: Color(0xEBF1F7EC),
    chipForeground: Color(0xBD2F3A2A),
    chipBorder: Color(0xFF6F7D68),
    actionChipBackground: Color(0xFF4F7B49),
    actionChipForeground: Color(0xFFFFFFFF),
    actionChipBorder: Color(0xFF4F7B49),
    inputBorderColor: Colors.transparent,
    inputBorderWidth: 0,
    fontFamily: 'LXGW WenKai',
    strongWeight: FontWeight.w700,
  );

  /// 论对错：墨色 · 方正 · 宋体（思源宋体）· 金线 ——「法庭之秤」。
  static const right = ModeTheme(
    view: BattleView.right,
    title: '论对错',
    tagline: '法庭之秤',
    background: Color(0xFF1C1B1E),
    surface: Color(0xFF2D2A24),
    primary: Color(0xFFE0AE40),
    onPrimary: Color(0xFF241C07),
    mineBubble: Color(0xFF5A4C35),
    mineText: Color(0xFFF6E9C8),
    text: Color(0xFFF2E9D6),
    textMuted: Color(0xFFB09B74),
    inputRadius: BorderRadius.zero,
    cardRadius: BorderRadius.zero,
    chipRadius: BorderRadius.zero,
    cardBackground: Color(0xFF2D2A24),
    cardTitle: Color(0xFFE0AE40),
    cardBody: Color(0xFFF2E9D6),
    cardMuted: Color(0xFFB09B74),
    cardBorder: Color(0x66E0AE40),
    cardShadowAlpha: 0.06,
    chipBackground: Color(0xEB2D2A24),
    chipForeground: Color(0xBDF2E9D6),
    chipBorder: Color(0xFFB09B74),
    actionChipBackground: Color(0xFFE0AE40),
    actionChipForeground: Color(0xFF241C07),
    actionChipBorder: Color(0xFFE0AE40),
    inputBorderColor: Color(0xFFD8A84E),
    inputBorderWidth: 1,
    fontFamily: 'Noto Serif SC',
    strongWeight: FontWeight.w600,
  );

  /// 比输赢：黑白对决 · 斜切 · 重磅黑体（思源黑体）——「胜负之局」（浅色基底）。
  ///
  /// 统一为浅底深字（与论对错的深底浅字互为反相）：背景浅灰、卡片与面板
  /// 用白/浅灰，主色与发送按钮保持黑色，保留「黑白对决」的个性。
  static const win = ModeTheme(
    view: BattleView.win,
    title: '比输赢',
    tagline: '胜负之局',
    background: Color(0xFFF1F1F4),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF16161A),
    onPrimary: Colors.white,
    mineBubble: Color(0xFF16161A),
    mineText: Colors.white,
    text: Color(0xFF1C1C24),
    textMuted: Color(0xFF6E6E78),
    inputRadius: BorderRadius.only(
      topLeft: Radius.circular(6),
      bottomLeft: Radius.circular(36),
      topRight: Radius.circular(36),
      bottomRight: Radius.circular(6),
    ),
    cardRadius: BorderRadius.only(
      topLeft: Radius.circular(2),
      bottomLeft: Radius.circular(48),
      topRight: Radius.circular(48),
      bottomRight: Radius.circular(2),
    ),
    chipRadius: BorderRadius.only(
      topLeft: Radius.circular(6),
      bottomLeft: Radius.circular(32),
      topRight: Radius.circular(32),
      bottomRight: Radius.circular(6),
    ),
    cardBackground: Color(0xFFFFFFFF),
    cardTitle: Color(0xFF16161A),
    cardBody: Color(0xFF2A2A34),
    cardMuted: Color(0xFF6E6E78),
    cardBorder: Color(0xFFDCDCE4),
    cardShadowAlpha: 0.10,
    chipBackground: Color(0xFFE8E8EE),
    chipForeground: Color(0xFF33333D),
    chipBorder: Color(0xFFC4C4CE),
    actionChipBackground: Color(0xFF16161A),
    actionChipForeground: Color(0xFFFFFFFF),
    actionChipBorder: Color(0xFF16161A),
    inputBorderColor: Colors.transparent,
    inputBorderWidth: 0,
    fontFamily: 'Noto Sans SC',
    strongWeight: FontWeight.w900,
  );

  static final Map<BattleView, ModeTheme> _byView = {
    BattleView.love: love,
    BattleView.right: right,
    BattleView.win: win,
  };

  static ModeTheme of(BattleView view) => _byView[view]!;
}
