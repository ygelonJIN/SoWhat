/// 对话理解服务占位。
///
/// 当前原型只负责承接原始文字和图片，后续接入视觉模型与文本模型，
/// 直接基于原始输入生成三视角分析，不经过结构化文本中间层。
class RecognizeService {
  const RecognizeService();

  Future<String> understandImages(List<String> imagePaths) async {
    return '等待接入视觉模型：${imagePaths.length} 张截图';
  }

  Future<String> understandText(String text) async {
    return '等待接入文本模型：${text.length} 个字符';
  }
}
