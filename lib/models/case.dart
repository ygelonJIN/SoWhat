import 'package:uuid/uuid.dart';

/// 一段可持续回看的对话存档。
class Case {
  final String id;
  final String title;
  final DateTime createdAt;
  final String? background;

  Case({
    String? id,
    required this.title,
    DateTime? createdAt,
    this.background,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  String get displayTitle => title.isNotEmpty ? title : '未命名对话';

  String get displayDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inDays < 1) return '今天';
    if (difference.inDays < 2) return '昨天';
    if (difference.inDays < 7) return '${difference.inDays} 天前';
    return '${createdAt.month}/${createdAt.day}';
  }
}
