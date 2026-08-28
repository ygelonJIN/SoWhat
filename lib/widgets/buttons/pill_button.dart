import 'package:flutter/material.dart';

import '../../theme/mode_theme.dart';

/// 胶囊形态的通用按钮，用于顶部栏等处的次要操作。
///
/// 视觉完全由 `ModeTheme` 驱动：
/// - `highlight = true`：主色填充（选中 / 强调态）
/// - `highlight = false`：表面色填充（普通态）
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.mode,
    required this.icon,
    required this.label,
    this.highlight = false,
    this.compact = false,
    this.onTap,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;

  /// 是否高亮（主色填充）。
  final bool highlight;

  /// 是否紧凑（更小的内边距，用于日期等次要信息）。
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = highlight ? scheme.onPrimary : mode.chipForeground;
    final background = highlight ? scheme.primary : mode.chipBackground;
    final borderColor = (highlight ? scheme.primary : mode.chipBorder)
        .withValues(alpha: 0.55);

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(color: borderColor, width: 1),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: InkWell(
        onTap: onTap,
        borderRadius: mode.chipRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 9 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
