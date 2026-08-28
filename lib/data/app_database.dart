import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Drift 数据库（无代码生成，纯 raw SQL）。
///
/// 7 张表，嵌套对象用 JSON TEXT 字段存储，避免复杂的 TypeConverter。
/// 持久化到应用文档目录的 `lrw_db.sqlite`（经 sqlite3_flutter_libs 驱动）。
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(_open());

  /// 内存数据库（单元测试用）。
  AppDatabase.memory() : super(NativeDatabase.memory());

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      if (kIsWeb) return NativeDatabase.memory();
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'lrw_db.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        logStatements: kDebugMode,
      );
    });
  }

  @override
  int get schemaVersion => 1;

  @override
  List<TableInfo> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => _ensureSchema(),
        beforeOpen: (details) async => _ensureSchema(),
      );

  Future<void> _ensureSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cases (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT,
        created_at INTEGER NOT NULL,
        pinned_at INTEGER,
        background TEXT,
        memory_finalized_at INTEGER,
        last_view INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY NOT NULL,
        conversation_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        party INTEGER NOT NULL,
        type INTEGER NOT NULL,
        content TEXT NOT NULL,
        asset_path TEXT,
        UNIQUE(conversation_id, sequence)
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv_seq ON messages(conversation_id, sequence)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS analyses (
        id TEXT PRIMARY KEY NOT NULL,
        conversation_id TEXT NOT NULL,
        view INTEGER NOT NULL,
        channel INTEGER NOT NULL,
        model_name TEXT,
        content TEXT NOT NULL,
        cards_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        token_count INTEGER NOT NULL DEFAULT 0,
        duration_micros INTEGER,
        turn_id TEXT NOT NULL DEFAULT '',
        memory_processed_at INTEGER
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_analyses_conv ON analyses(conversation_id, created_at)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS battle_states (
        conversation_id TEXT NOT NULL,
        view INTEGER NOT NULL,
        user_score REAL NOT NULL,
        partner_score REAL NOT NULL,
        user_hp REAL NOT NULL,
        partner_hp REAL NOT NULL,
        user_love REAL NOT NULL,
        partner_love REAL NOT NULL,
        justice_balance REAL NOT NULL,
        headline TEXT NOT NULL,
        cards_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (conversation_id, view)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS memory_profiles (
        id TEXT PRIMARY KEY NOT NULL,
        user_summary TEXT,
        partner_summary TEXT,
        relationship_summary TEXT,
        growth_summary TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS memory_entries (
        id TEXT PRIMARY KEY NOT NULL,
        kind INTEGER NOT NULL,
        summary TEXT NOT NULL,
        sources_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS ai_configs (
        id INTEGER PRIMARY KEY NOT NULL,
        provider INTEGER NOT NULL,
        protocol INTEGER NOT NULL,
        api_key TEXT NOT NULL,
        model TEXT NOT NULL,
        base_url TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
