import 'package:uuid/uuid.dart';

/// 应用私有目录中的持久化图片资产。
class Asset {
  final String id;
  final String path;
  final String title;
  final DateTime createdAt;
  final int sizeBytes;
  final String mimeType;

  Asset({
    String? id,
    required this.path,
    String? title,
    DateTime? createdAt,
    this.sizeBytes = 0,
    this.mimeType = 'image/jpeg',
  })  : id = id ?? const Uuid().v4(),
        title = title ?? '',
        createdAt = createdAt ?? DateTime.now();

  String get displayTitle => title.trim().isEmpty ? path.split('/').last : title;

  Asset copyWith({String? path, String? title, int? sizeBytes, String? mimeType}) {
    return Asset(
      id: id,
      path: path ?? this.path,
      title: title ?? this.title,
      createdAt: createdAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
