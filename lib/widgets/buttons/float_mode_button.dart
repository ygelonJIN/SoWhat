import 'package:flutter/material.dart';

import '../../theme/mode_theme.dart';

/// 可切换的胶囊模式按钮，用于「为爱 / 论对错 / 比输赢」等分段切换。
///
/// - 选中态：主色填充 + 高阴影
/// - 未选中态：`ModeTheme` 的胶囊表面色（win 模式为浅灰反色）
class FloatModeButton extends StatelessWidget {
  const FloatModeButton({
    super.key,
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final ModeTheme mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : mode.chipForeground;
    final background = selected ? scheme.primary : mode.chipBackground;
    final borderColor = (selected ? scheme.primary : mode.chipBorder)
        .withValues(alpha: selected ? 0.8 : 0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: mode.chipRadius,
          side: BorderSide(color: borderColor, width: 1),
        ),
        elevation: selected ? 5 : 2,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: mode.chipRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
