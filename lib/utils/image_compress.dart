import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 图片重编码工具（供后台 isolate 调用，函数必须是顶层或静态）。
///
/// 当前唯一输出格式：**JPEG**。这是三视角分析 + 记忆生成送往模型的通用格式
/// （Anthropic/OpenAI 兼容都收 image/jpeg），体积小、兼容最好。
///
/// 两级压缩策略：
/// - 首次导入（battle_screen `_encodeJpeg90`）：PNG/大图解码后按**全分辨率**
///   重编码为 JPEG q90；
/// - 再压缩（资产管理「压缩」/ 请求体过大自动降质）：等比缩放最长边到
///   [maxDimension] 内 + 降低 [quality]，得到明显更小的 JPEG。
///   JPEG 是有损格式，再压缩不可逆，但保证画面主体仍清晰可读。
class ImageCompress {
  const ImageCompress._();

  /// 把图片重编码为 JPEG。
  ///
  /// [maxDimension] ≤ 0 表示不缩放（保留原分辨率）；> 0 时等比缩放让最长边
  /// 不超过该值。[quality] 为 JPEG 质量（1-100）。解码失败（如 HEIC）时返回
  /// null，调用方应保留原文件。
  static Uint8List? reencodeJpeg(
    Uint8List bytes, {
    int quality = 72,
    int maxDimension = 0,
  }) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      var target = decoded;
      if (maxDimension > 0) {
        final longest = decoded.width > decoded.height
            ? decoded.width
            : decoded.height;
        if (longest > maxDimension) {
          final scale = maxDimension / longest;
          target = img.copyResize(
            decoded,
            width: (decoded.width * scale).round(),
            height: (decoded.height * scale).round(),
          );
        }
      }
      return img.encodeJpg(target, quality: quality);
    } catch (_) {
      return null;
    }
  }
}

/// [compute] 可直接调用的再压缩包装（record 打包参数，后台 isolate 执行）。
Uint8List? reencodeJpegCompat(
  ({Uint8List bytes, int quality, int maxDimension}) args,
) => ImageCompress.reencodeJpeg(
  args.bytes,
  quality: args.quality,
  maxDimension: args.maxDimension,
);