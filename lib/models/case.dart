import 'package:uuid/uuid.dart';

import 'enums.dart';

/// 一段可持续回看的对话存档。
///
/// [title] 为可选的**自定义名称**：为空时界面按创建时间展示「日期 时间」；
/// 重命名后展示自定义文字，但 [createdAt] 始终保留，按日期/时间搜索仍可命中。
/// [pinnedAt] 非空表示置顶（按置顶时间倒序排在最前）。
/// [lastView] 该对话上次使用的分析模式（为爱 / 论对错 / 比输赢）。
class Case {
  final String id;
  final String? title;
  final DateTime createdAt;
  final DateTime? pinnedAt;
  final String? background;
  final DateTime? memoryFinalizedAt;
  final BattleView lastView;

  Case({
    String? id,
    this.title,
    DateTime? createdAt,
    this.pinnedAt,
    this.background,
    this.memoryFinalizedAt,
    this.lastView = BattleView.love,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  String get displayTitle =>
      (title == null || title!.isEmpty) ? '未命名对话' : title!;

  String get displayDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inDays < 1) return '今天';
    if (difference.inDays < 2) return '昨天';
    if (difference.inDays < 7) return '${difference.inDays} 天前';
    return '${createdAt.month}/${createdAt.day}';
  }

  bool get isPinned => pinnedAt != null;

  bool get hasFinalizedMemory => memoryFinalizedAt != null;

  static const _sentinel = Object();

  Case copyWith({
    Object? title = _sentinel,
    Object? pinnedAt = _sentinel,
    Object? background = _sentinel,
    Object? memoryFinalizedAt = _sentinel,
    Object? lastView = _sentinel,
  }) {
    return Case(
      id: id,
      title: title == _sentinel ? this.title : title as String?,
      createdAt: createdAt,
      pinnedAt: pinnedAt == _sentinel ? this.pinnedAt : pinnedAt as DateTime?,
      background: background == _sentinel
          ? this.background
          : background as String?,
      memoryFinalizedAt: memoryFinalizedAt == _sentinel
          ? this.memoryFinalizedAt
          : memoryFinalizedAt as DateTime?,
      lastView: lastView == _sentinel ? this.lastView : lastView as BattleView,
    );
  }
}
