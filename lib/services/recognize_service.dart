/// 对话理解服务。
///
/// 当前占位：只返回描述性文本，不做结构化解析。
/// 后续接入视觉模型后，直接基于截图/文本原始内容判断出三视角分析。
class RecognizeService {
  const RecognizeService();

  Future<String> understandImages(List<String> imagePaths) async {
    return '（等待接入视觉模型：${imagePaths.length} 张截图，AI 将直接看图理解对话内容）';
  }

  Future<String> understandText(String text) async {
    return '（等待接入文本模型：${text.length} 个字符，AI 将直接理解对话内容）';
  }
}
