import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../theme/mode_theme.dart';

/// 全屏聊天式的输入条：文字输入 + 截图附着 + 发送。
///
/// 样式由 `ModeTheme` 驱动（圆角、边框、主色、字体）。`isAnalyzing` 时
/// 附着 / 发送按钮禁用。`pendingCount > 0` 表示有暂存图片待发送：附着
/// 按钮显示数量角标，输入框提示语切换为「点发送一起发出」。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.mode,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    required this.onInputTap,
    this.isAnalyzing = false,
    this.pendingCount = 0,
  });

  final ModeTheme mode;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onInputTap;
  final bool isAnalyzing;

  /// 暂存的待发送图片数量（>0 时显示角标并切换提示语）。
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingCount > 0;
    return Material(
      color: mode.surface.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: mode.inputRadius,
        side: BorderSide(
          color: mode.textMuted.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: mode.inputRadius,
          border: mode.inputBorderWidth > 0
              ? Border.all(
                  color: mode.inputBorderColor,
                  width: mode.inputBorderWidth,
                )
              : null,
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 1,
          maxLines: 4,
          style: TextStyle(
            color: mode.text,
            fontSize: 16,
            fontWeight: mode.view == BattleView.win
                ? FontWeight.w500
                : FontWeight.w400,
          ),
          cursorColor: mode.primary,
          textInputAction: TextInputAction.newline,
          onTap: onInputTap,
          decoration: InputDecoration(
            hintText: hasPending ? '已选 $pendingCount 张图片，点发送一起发出' : '上传截图，或把对话贴进来',
            hintStyle: TextStyle(
              color: mode.textMuted,
              fontSize: hasPending ? 12.5 : 13,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
              child: _ActionChipButton(
                mode: mode,
                icon: Icons.photo_library_rounded,
                badge: hasPending ? pendingCount : 0,
                onPressed: isAnalyzing ? null : onAttach,
              ),
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: _ActionChipButton(
                mode: mode,
                icon: Icons.arrow_upward_rounded,
                onPressed: isAnalyzing ? null : onSend,
              ),
            ),
          ),
          onSubmitted: (_) {
            if (!isAnalyzing) onSend();
          },
        ),
      ),
    );
  }
}

/// 输入条内的圆形操作芯片（附着 / 发送）。
///
/// 视觉由 `ModeTheme` 的 `actionChip*` 令牌驱动；win 模式为白底反色。
/// `onPressed == null` 时进入禁用态（主色降透明）。
/// `badge > 0` 时右上角显示数量角标（暂存图片数）。
class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.mode,
    required this.icon,
    required this.onPressed,
    this.badge = 0,
  });

  final ModeTheme mode;
  final IconData icon;
  final VoidCallback? onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: onPressed == null
              ? mode.actionChipBackground.withValues(alpha: 0.38)
              : mode.actionChipBackground,
          shape: RoundedRectangleBorder(
            borderRadius: mode.chipRadius,
            side: BorderSide(
              color: mode.actionChipBorder.withValues(
                alpha: onPressed == null ? 0.4 : 0.8,
              ),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: mode.chipRadius,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: mode.actionChipForeground,
              ),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: mode.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: mode.surface, width: 1.2),
              ),
              child: Text(
                '$badge',
                style: TextStyle(
                  color: mode.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
