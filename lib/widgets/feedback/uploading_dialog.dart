import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/fold_decoration.dart';
import '../../theme/mode_theme.dart';

/// 图片上传/压缩进度（供上传弹窗实时刷新）。
///
/// [done] 为已处理张数；[total] 为 0 时表示还在选图阶段（进度条走不确定态）。
class UploadingProgress {
  const UploadingProgress({
    required this.done,
    required this.total,
    required this.stage,
  });

  final int done;
  final int total;
  final String stage;

  /// 0.0 ~ 1.0 的确定进度；还在选图阶段时为 null。
  double? get ratio => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

/// 主题化上传进度弹窗：选图 / 压缩 / 落盘期间展示，符合三模式主题。
///
/// 不可点击遮罩关闭（barrierDismissible: false 由调用方控制），选完图后
/// 自动收起，避免用户在压缩大量图片时误以为卡死。
class UploadingDialog extends StatelessWidget {
  const UploadingDialog({
    super.key,
    required this.mode,
    required this.progress,
  });

  final ModeTheme mode;
  final ValueListenable<UploadingProgress> progress;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: CutBox(
        width: 276,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        fold: mode.cornerFold,
        color: mode.cardBackground,
        borderRadius: mode.cardRadius,
        border: Border.all(color: mode.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: (mode.cardShadowAlpha + 0.08).clamp(0, 1),
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        child: ValueListenableBuilder<UploadingProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            final ratio = value.ratio;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: mode.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.image_outlined,
                        size: 17,
                        color: mode.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在上传图片',
                      style: TextStyle(
                        color: mode.cardTitle,
                        fontSize: 15,
                        fontWeight: mode.strongWeight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: mode.cardBorder.withValues(alpha: 0.35),
                    color: mode.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  value.stage,
                  style: TextStyle(
                    color: mode.cardMuted,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
