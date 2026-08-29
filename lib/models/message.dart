import 'package:uuid/uuid.dart';

import 'enums.dart';

/// 对话中的一条消息。AI 直接理解原文或图片，不要求先转换为结构化文本。
class Message {
  final String id;
  final String conversationId;
  final int sequence;
  final DateTime createdAt;
  final Party party;
  final MessageType type;
  final String content;
  final String? assetPath;

  Message({
    String? id,
    required this.conversationId,
    required this.sequence,
    DateTime? createdAt,
    required this.party,
    required this.type,
    required this.content,
    this.assetPath,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Message copyWith({
    String? conversationId,
    String? assetPath,
  }) {
    return Message(
      id: id,
      conversationId: conversationId ?? this.conversationId,
      sequence: sequence,
      createdAt: createdAt,
      party: party,
      type: type,
      content: content,
      assetPath: assetPath ?? this.assetPath,
    );
  }

  String get partyLabel => party == Party.a ? '我' : 'TA';

  bool get isImageType =>
      type == MessageType.image || type == MessageType.sticker;
}
