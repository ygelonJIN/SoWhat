import '../models/models.dart';

/// 导入服务：保留用户原始输入，交给 AI 直接理解，不做格式解析。
class ImportService {
  const ImportService();

  Message createPastedMessage({
    required String conversationId,
    required String text,
    required int sequence,
  }) {
    return Message(
      conversationId: conversationId,
      sequence: sequence,
      party: Party.a,
      type: MessageType.text,
      content: text,
    );
  }

  Message createImageMessage({
    required String conversationId,
    required String imagePath,
    required int sequence,
  }) {
    return Message(
      conversationId: conversationId,
      sequence: sequence,
      party: Party.a,
      type: MessageType.image,
      content: '待 AI 直接理解的截图',
      assetPath: imagePath,
    );
  }
}
