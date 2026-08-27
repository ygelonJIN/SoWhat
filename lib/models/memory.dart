import 'package:uuid/uuid.dart';

import 'enums.dart';

/// 关于这段关系的长期记忆档案。
///
/// [userSummary] / [partnerSummary] / [relationshipSummary] / [growthSummary]
/// 四份概况是「当前最新综合版」档案（记忆页顶部展示，每次「更新记忆」时
/// 由 AI 融合旧概况 + 新卡片重新产出，极其完善、不限篇幅）；
/// [entries] 是九板块的增量条目记录。
class MemoryProfile {
  final String id;
  final String? userSummary;
  final String? partnerSummary;
  final String? relationshipSummary;
  final String? growthSummary;
  final List<MemoryEntry> entries;
  final DateTime updatedAt;

  MemoryProfile({
    String? id,
    this.userSummary,
    this.partnerSummary,
    this.relationshipSummary,
    this.growthSummary,
    this.entries = const [],
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now();

  factory MemoryProfile.empty() => MemoryProfile(id: 'relationship-memory');

  MemoryProfile copyWith({
    String? userSummary,
    String? partnerSummary,
    String? relationshipSummary,
    String? growthSummary,
    List<MemoryEntry>? entries,
    DateTime? updatedAt,
  }) {
    return MemoryProfile(
      id: id,
      userSummary: userSummary ?? this.userSummary,
      partnerSummary: partnerSummary ?? this.partnerSummary,
      relationshipSummary: relationshipSummary ?? this.relationshipSummary,
      growthSummary: growthSummary ?? this.growthSummary,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// 一条有出处的长期记忆（九板块之一，随源对话删除，不可单独清除）。
class MemoryEntry {
  final String id;
  final MemoryKind kind;
  final String summary;
  final List<MemorySourceRef> sources;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  MemoryEntry({
    String? id,
    required this.kind,
    required this.summary,
    this.sources = const [],
    DateTime? createdAt,
    this.updatedAt,
    this.isDeleted = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  MemoryEntry copyWith({
    String? summary,
    List<MemorySourceRef>? sources,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return MemoryEntry(
      id: id,
      kind: kind,
      summary: summary ?? this.summary,
      sources: sources ?? this.sources,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// 记忆的结构化出处：指向来源对话与分析卡片（时间编号），可跳回查看。
class MemorySourceRef {
  final String conversationId;
  final String? analysisId;
  final DateTime happenedAt;

  const MemorySourceRef({
    required this.conversationId,
    this.analysisId,
    required this.happenedAt,
  });
}