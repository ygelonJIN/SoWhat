import 'package:uuid/uuid.dart';

import 'enums.dart';

/// 关于这段关系的长期记忆档案。
class MemoryProfile {
  final String id;
  final String? userSummary;
  final String? partnerSummary;
  final String? relationshipSummary;
  final List<MemoryEntry> entries;
  final DateTime updatedAt;

  MemoryProfile({
    String? id,
    this.userSummary,
    this.partnerSummary,
    this.relationshipSummary,
    this.entries = const [],
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now();

  factory MemoryProfile.empty() => MemoryProfile(id: 'relationship-memory');

  MemoryProfile copyWith({
    String? userSummary,
    String? partnerSummary,
    String? relationshipSummary,
    List<MemoryEntry>? entries,
    DateTime? updatedAt,
  }) {
    return MemoryProfile(
      id: id,
      userSummary: userSummary ?? this.userSummary,
      partnerSummary: partnerSummary ?? this.partnerSummary,
      relationshipSummary: relationshipSummary ?? this.relationshipSummary,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// 一条有出处的长期记忆，可独立回看或清除。
class MemoryEntry {
  final String id;
  final MemoryKind kind;
  final String summary;
  final String? source;
  final DateTime createdAt;
  final bool isDeleted;

  MemoryEntry({
    String? id,
    required this.kind,
    required this.summary,
    this.source,
    DateTime? createdAt,
    this.isDeleted = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  MemoryEntry copyWith({bool? isDeleted}) {
    return MemoryEntry(
      id: id,
      kind: kind,
      summary: summary,
      source: source,
      createdAt: createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}