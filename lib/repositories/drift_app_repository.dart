import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/app_database.dart';
import '../data/converters.dart' as cv;
import '../models/models.dart';
import 'app_repository.dart';

/// 按文件后缀映射 MIME 类型（与发送侧保持一致）。
String _mimeTypeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class DriftAppRepository implements AppRepository {
  DriftAppRepository({AppDatabase? database})
      : _db = database ?? AppDatabase.defaults();

  final AppDatabase _db;
  static const _secureStorage = FlutterSecureStorage();
  static const _apiKeyStorageKey = 'so_what.ai_api_key';

  final _caseController = StreamController<List<Case>>.broadcast();
  final _memoryController = StreamController<MemoryProfile>.broadcast();
  final _aiConfigController = StreamController<AiConfig>.broadcast();
  final _assetController = StreamController<List<Asset>>.broadcast();
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamController<List<Analysis>>> _analysisControllers = {};
  final Map<String, StreamController<BattleState>> _battleControllers = {};

  Future<void> _ensureReady() async {
    try {
      await _db.customSelect('SELECT 1').get();
      await _migrateSchema();
      final rows =
          await _db.customSelect('SELECT COUNT(*) AS c FROM cases').get();
      final count = rows.first.data['c'] as int;
      if (count == 0) await _seedDemo();
    } on SqliteException catch (e, st) {
      final msg = e.message;
      debugPrint('[DriftAppRepository] SqliteException: $msg\n$st');
      if (msg.contains('no such table') || msg.contains('no such column')) {
        await _repairMissingTables();
        await _migrateSchema();
        // retry once
        final rows =
            await _db.customSelect('SELECT COUNT(*) AS c FROM cases').get();
        final count = rows.first.data['c'] as int;
        if (count == 0) await _seedDemo();
        return;
      }
      rethrow;
    } catch (e, st) {
      debugPrint('[DriftAppRepository] _ensureReady error: $e\n$st');
      rethrow;
    }
  }

  Future<void> _migrateSchema() async {
    final tableColumns = <String, Set<String>>{};
    for (final table in ['cases', 'analyses', 'battle_states']) {
      final rows = await _db.customSelect('PRAGMA table_info($table)').get();
      tableColumns[table] = rows.map((row) => row.data['name'] as String).toSet();
    }

    if (!tableColumns['cases']!.contains('memory_finalized_at')) {
      await _db.customStatement(
        'ALTER TABLE cases ADD COLUMN memory_finalized_at INTEGER',
      );
    }
    if (!tableColumns['cases']!.contains('last_view')) {
      await _db.customStatement(
        'ALTER TABLE cases ADD COLUMN last_view INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!tableColumns['cases']!.contains('is_imported')) {
      await _db.customStatement(
        'ALTER TABLE cases ADD COLUMN is_imported INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!tableColumns['analyses']!.contains('turn_id')) {
      await _db.customStatement(
        "ALTER TABLE analyses ADD COLUMN turn_id TEXT NOT NULL DEFAULT ''",
      );
    }

    final battleColumns = tableColumns['battle_states']!;
    if (battleColumns.contains('conversation_id') &&
        battleColumns.contains('view')) {
      final tableSql = await _db.customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'battle_states'",
      ).get();
      final sql = tableSql.isEmpty ? '' : tableSql.first.data['sql']?.toString() ?? '';
      if (sql.contains('conversation_id TEXT PRIMARY KEY')) {
        await _db.transaction(() async {
          await _db.customStatement('ALTER TABLE battle_states RENAME TO battle_states_legacy');
          await _db.customStatement('''
            CREATE TABLE battle_states (
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
          await _db.customStatement('''
            INSERT INTO battle_states
            SELECT conversation_id, view, user_score, partner_score, user_hp,
              partner_hp, user_love, partner_love, justice_balance, headline,
              cards_json, updated_at
            FROM battle_states_legacy
          ''');
          await _db.customStatement('DROP TABLE battle_states_legacy');
        });
      }
    }

    // 迁移：battle_states 添加思考过程持久化字段。
    if (!battleColumns.contains('thinking_content')) {
      await _db.customStatement(
        'ALTER TABLE battle_states ADD COLUMN thinking_content TEXT',
      );
    }
    if (!battleColumns.contains('thinking_started_at')) {
      await _db.customStatement(
        'ALTER TABLE battle_states ADD COLUMN thinking_started_at INTEGER',
      );
    }
    if (!battleColumns.contains('thinking_finished_at')) {
      await _db.customStatement(
        'ALTER TABLE battle_states ADD COLUMN thinking_finished_at INTEGER',
      );
    }
    if (!battleColumns.contains('thinking_active')) {
      await _db.customStatement(
        "ALTER TABLE battle_states ADD COLUMN thinking_active INTEGER NOT NULL DEFAULT 0",
      );
    }
  }

  Future<void> _repairMissingTables() async {
    debugPrint('[DriftAppRepository] repairing missing tables with IF NOT EXISTS');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS cases (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT,
        created_at INTEGER NOT NULL,
        pinned_at INTEGER,
        background TEXT,
        memory_finalized_at INTEGER,
        is_imported INTEGER NOT NULL DEFAULT 0,
        last_view INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _db.customStatement('''
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
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv_seq ON messages(conversation_id, sequence)',
    );
    await _db.customStatement('''
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
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_analyses_conv ON analyses(conversation_id, created_at)',
    );
    await _db.customStatement('''
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
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS memory_profiles (
        id TEXT PRIMARY KEY NOT NULL,
        user_summary TEXT,
        partner_summary TEXT,
        relationship_summary TEXT,
        growth_summary TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await _db.customStatement('''
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
    final memoryColumns = (await _db.customSelect('PRAGMA table_info(memory_entries)').get())
        .map((row) => row.data['name'] as String)
        .toSet();
    if (!memoryColumns.contains('source_gone')) {
      await _db.customStatement(
        'ALTER TABLE memory_entries ADD COLUMN source_gone INTEGER NOT NULL DEFAULT 0',
      );
    }
    await _db.customStatement('''
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

  Future<void> _seedDemo() async {
    final now = DateTime.now();
    const convId = 'current-conversation';
    final messages = [
      Message(
        conversationId: convId,
        sequence: 1,
        createdAt: now.subtract(const Duration(minutes: 40)),
        party: Party.b,
        type: MessageType.text,
        content: '你昨天为什么又不回我消息？我等了你一晚上。',
      ),
      Message(
        conversationId: convId,
        sequence: 2,
        createdAt: now.subtract(const Duration(minutes: 38)),
        party: Party.a,
        type: MessageType.text,
        content: '我昨天加班到很晚，手机没电了，真的不是故意不回。',
      ),
      Message(
        conversationId: convId,
        sequence: 3,
        createdAt: now.subtract(const Duration(minutes: 36)),
        party: Party.b,
        type: MessageType.text,
        content: '你每次都这么说。上次出差失联两天，这次又是手机没电。',
      ),
      Message(
        conversationId: convId,
        sequence: 4,
        createdAt: now.subtract(const Duration(minutes: 34)),
        party: Party.a,
        type: MessageType.text,
        content: '上次出差是真的在飞机上，这次真的是没电。你要我怎么证明？',
      ),
      Message(
        conversationId: convId,
        sequence: 5,
        createdAt: now.subtract(const Duration(minutes: 32)),
        party: Party.b,
        type: MessageType.text,
        content: '我不是要你证明，我只是希望你在乎我的感受。等一晚上的感觉很难受。',
      ),
      Message(
        conversationId: convId,
        sequence: 6,
        createdAt: now.subtract(const Duration(minutes: 30)),
        party: Party.a,
        type: MessageType.text,
        content: '我知道了……对不起，以后加班前我先跟你说一声。',
      ),
    ];
    await _db.customStatement(
      'INSERT OR REPLACE INTO cases (id, title, created_at, pinned_at, background, memory_finalized_at, is_imported, last_view) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        convId,
        null,
        now.subtract(const Duration(minutes: 40)).millisecondsSinceEpoch,
        null,
        null,
        BattleView.love.index,
      ],
    );
    for (final m in messages) {
      final row = cv.messageToRow(m);
      await _db.customStatement(
        'INSERT OR REPLACE INTO messages (id, conversation_id, sequence, created_at, party, type, content, asset_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          row['id'] as String,
          row['conversation_id'] as String,
          row['sequence'] as int,
          row['created_at'] as int,
          row['party'] as int,
          row['type'] as int,
          row['content'] as String,
          row['asset_path'] as String?,
        ],
      );
    }
    final battle = BattleState.initial();
    final brow = cv.battleStateToRow(convId, battle);
    await _db.customStatement(
      'INSERT OR REPLACE INTO battle_states (conversation_id, view, user_score, partner_score, user_hp, partner_hp, user_love, partner_love, justice_balance, headline, cards_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        brow['conversation_id'] as String,
        brow['view'] as int,
        brow['user_score'] as double,
        brow['partner_score'] as double,
        brow['user_hp'] as double,
        brow['partner_hp'] as double,
        brow['user_love'] as double,
        brow['partner_love'] as double,
        brow['justice_balance'] as double,
        brow['headline'] as String,
        brow['cards_json'] as String,
        brow['updated_at'] as int,
      ],
    );
    final memRow = cv.memoryProfileToRow(MemoryProfile.empty());
    await _db.customStatement(
      'INSERT OR REPLACE INTO memory_profiles (id, user_summary, partner_summary, relationship_summary, growth_summary, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        memRow['id'] as String,
        memRow['user_summary'] as String?,
        memRow['partner_summary'] as String?,
        memRow['relationship_summary'] as String?,
        memRow['growth_summary'] as String?,
        memRow['updated_at'] as int,
      ],
    );
  }

  Future<List<Case>> _loadCases() async {
    final rows = await _db.customSelect('SELECT * FROM cases').get();
    return rows.map((r) => cv.rowToCase(r.data)).toList();
  }

  Future<List<Message>> _loadMessages(String conversationId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM messages WHERE conversation_id = ? ORDER BY sequence ASC',
          variables: [Variable<String>(conversationId)],
        )
        .get();
    return rows.map((r) => cv.rowToMessage(r.data)).toList();
  }

  Future<List<Analysis>> _loadAnalyses(String conversationId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM analyses WHERE conversation_id = ? ORDER BY created_at ASC',
          variables: [Variable<String>(conversationId)],
        )
        .get();
    return rows.map((r) => cv.rowToAnalysis(r.data)).toList();
  }

  Future<BattleState> _loadBattle(String conversationId, BattleView view) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM battle_states WHERE conversation_id = ? AND view = ?',
          variables: [Variable<String>(conversationId), Variable<int>(view.index)],
        )
        .get();
    if (rows.isEmpty) return BattleState.initial(view);
    return cv.rowToBattleState(rows.first.data);
  }

  Future<MemoryProfile> _loadMemory() async {
    final prow = await _db.customSelect('SELECT * FROM memory_profiles LIMIT 1').get();
    final erows = await _db.customSelect('SELECT * FROM memory_entries').get();
    final entries = erows.map((r) => cv.rowToMemoryEntry(r.data)).toList();
    if (prow.isEmpty) return MemoryProfile.empty().copyWith(entries: entries);
    final data = prow.first.data;
    return MemoryProfile(
      id: data['id'] as String,
      userSummary: data['user_summary'] as String?,
      partnerSummary: data['partner_summary'] as String?,
      relationshipSummary: data['relationship_summary'] as String?,
      growthSummary: data['growth_summary'] as String?,
      entries: entries,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updated_at'] as int),
    );
  }

  Future<List<Asset>> _loadAssets() async {
    final rows = await _db.customSelect('SELECT * FROM assets ORDER BY created_at DESC').get();
    return rows.map((row) => cv.rowToAsset(row.data)).toList();
  }

  Future<AiConfig> _loadAiConfig() async {
    final rows = await _db.customSelect('SELECT * FROM ai_configs WHERE id = 1').get();
    if (rows.isEmpty) return const AiConfig();
    final config = cv.rowToAiConfig(rows.first.data);
    var key = await _secureStorage.read(key: _apiKeyStorageKey) ?? '';
    // 兼容安全存储接入前的旧版本：首次读取旧明文后立即迁移并清空数据库字段。
    if (key.isEmpty && config.apiKey.isNotEmpty) {
      key = config.apiKey;
      await _secureStorage.write(key: _apiKeyStorageKey, value: key);
      await _db.customStatement(
        'UPDATE ai_configs SET api_key = ? WHERE id = 1',
        [''],
      );
    }
    return config.copyWith(apiKey: key, enabled: key.isNotEmpty);
  }

  void _emitCases(List<Case> cases) {
    if (!_caseController.isClosed) _caseController.add(List.unmodifiable(cases));
  }

  void _emitMessages(String conversationId, List<Message> messages) {
    final c = _messageControllers[conversationId];
    if (c != null && !c.isClosed) c.add(List.unmodifiable(messages));
  }

  void _emitAnalyses(String conversationId, List<Analysis> analyses) {
    final c = _analysisControllers[conversationId];
    if (c != null && !c.isClosed) c.add(List.unmodifiable(analyses));
  }

  void _emitBattle(String conversationId, BattleState state) {
    final c = _battleControllers[conversationId];
    if (c != null && !c.isClosed) c.add(state);
  }

  void _emitMemory(MemoryProfile profile) {
    if (!_memoryController.isClosed) _memoryController.add(profile);
  }

  void _emitAiConfig(AiConfig config) {
    if (!_aiConfigController.isClosed) _aiConfigController.add(config);
  }

  void _emitAssets() {
    if (!_assetController.isClosed) {
      _loadAssets().then(_assetController.add);
    }
  }

  @override
  Stream<List<Asset>> watchAssets() async* {
    await _ensureReady();
    yield await _loadAssets();
    yield* _assetController.stream;
  }

  @override
  Future<Asset?> assetByPath(String path) async {
    await _ensureReady();
    final rows = await _db.customSelect(
      'SELECT * FROM assets WHERE path = ? LIMIT 1',
      variables: [Variable<String>(path)],
    ).get();
    return rows.isEmpty ? null : cv.rowToAsset(rows.first.data);
  }

  @override
  Future<void> saveAsset(Asset asset) async {
    await _ensureReady();
    final row = cv.assetToRow(asset);
    await _db.customStatement(
      'INSERT OR REPLACE INTO assets (id, path, title, created_at, size_bytes, mime_type) VALUES (?, ?, ?, ?, ?, ?)',
      [row['id'], row['path'], row['title'], row['created_at'], row['size_bytes'], row['mime_type']],
    );
    _emitAssets();
  }

  @override
  Future<void> renameAsset(String assetId, String title) async {
    await _ensureReady();
    await _db.customStatement('UPDATE assets SET title = ? WHERE id = ?', [title.trim(), assetId]);
    _emitAssets();
  }

  @override
  Future<void> deleteAssets(List<String> assetIds) async {
    await _ensureReady();
    for (final id in assetIds) {
      final rows = await _db.customSelect('SELECT path FROM assets WHERE id = ?', variables: [Variable<String>(id)]).get();
      if (rows.isNotEmpty) {
        final path = rows.first.data['path'] as String;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      await _db.customStatement('DELETE FROM assets WHERE id = ?', [id]);
    }
    _emitAssets();
  }

  @override
  Stream<List<Case>> watchCases() async* {
    await _ensureReady();
    yield await _loadCases();
    yield* _caseController.stream;
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    await _ensureReady();
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
    yield await _loadMessages(conversationId);
    yield* controller.stream;
  }

  @override
  Stream<List<Analysis>> watchAnalyses(String conversationId) async* {
    await _ensureReady();
    final controller = _analysisControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Analysis>>.broadcast(),
    );
    yield await _loadAnalyses(conversationId);
    yield* controller.stream;
  }

  @override
  Stream<BattleState> watchBattleState(String conversationId, BattleView view) async* {
    await _ensureReady();
    final controller = _battleControllers.putIfAbsent(
      conversationId,
      () => StreamController<BattleState>.broadcast(),
    );
    yield await _loadBattle(conversationId, view);
    yield* controller.stream;
  }

  @override
  Stream<MemoryProfile> watchMemory() async* {
    await _ensureReady();
    yield await _loadMemory();
    yield* _memoryController.stream;
  }

  @override
  Stream<AiConfig> watchAiConfig() async* {
    await _ensureReady();
    yield await _loadAiConfig();
    yield* _aiConfigController.stream;
  }

  @override
  Stream<DateTime> watchConversationStartedAt(String conversationId) async* {
    await _ensureReady();
    yield* watchCases().map((cases) {
      for (final c in cases) {
        if (c.id == conversationId) return c.createdAt;
      }
      return DateTime.now();
    });
  }

  @override
  Future<void> seedDemoData() async {
    await _ensureReady();
  }

  @override
  Future<Case> upsertCase(Case caseItem) async {
    await _ensureReady();
    await _db.customStatement(
      'INSERT OR REPLACE INTO cases (id, title, created_at, pinned_at, background, memory_finalized_at, is_imported, last_view) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        caseItem.id,
        caseItem.title,
        caseItem.createdAt.millisecondsSinceEpoch,
        caseItem.pinnedAt?.millisecondsSinceEpoch,
        caseItem.background,
        caseItem.memoryFinalizedAt?.millisecondsSinceEpoch,
        caseItem.isImported ? 1 : 0,
        caseItem.lastView.index,
      ],
    );
    final existing = await _db
        .customSelect(
          'SELECT 1 FROM battle_states WHERE conversation_id = ?',
          variables: [Variable<String>(caseItem.id)],
        )
        .get();
    if (existing.isEmpty) {
      final b = BattleState.initial();
      final row = cv.battleStateToRow(caseItem.id, b);
      await _db.customStatement(
        'INSERT INTO battle_states (conversation_id, view, user_score, partner_score, user_hp, partner_hp, user_love, partner_love, justice_balance, headline, cards_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          row['conversation_id'] as String,
          row['view'] as int,
          row['user_score'] as double,
          row['partner_score'] as double,
          row['user_hp'] as double,
          row['partner_hp'] as double,
          row['user_love'] as double,
          row['partner_love'] as double,
          row['justice_balance'] as double,
          row['headline'] as String,
          row['cards_json'] as String,
          row['updated_at'] as int,
        ],
      );
    }
    final cases = await _loadCases();
    _emitCases(cases);
    return caseItem;
  }

  @override
  Future<void> deleteEmptyConversation(String conversationId) async {
    await _ensureReady();
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS count FROM messages WHERE conversation_id = ?',
      variables: [Variable<String>(conversationId)],
    ).get();
    final count = (rows.first.data['count'] as int?) ?? 0;
    if (count == 0) {
      await _db.customStatement('DELETE FROM cases WHERE id = ?', [conversationId]);
      _emitCases(await _loadCases());
    }
  }

  @override
  Future<bool> cleanupEmptyConversation(String conversationId) async {
    await _ensureReady();
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS count FROM messages WHERE conversation_id = ?',
      variables: [Variable<String>(conversationId)],
    ).get();
    final count = (rows.first.data['count'] as int?) ?? 0;
    if (count == 0) {
      await _db.customStatement('DELETE FROM cases WHERE id = ?', [conversationId]);
      _emitCases(await _loadCases());
      return false;
    }
    return true;
  }

  @override
  Future<void> deleteCase(String conversationId) async {
    await _ensureReady();
    await _db.customStatement('DELETE FROM cases WHERE id = ?', [conversationId]);
    final imageRows = await _db.customSelect(
      'SELECT asset_path FROM messages WHERE conversation_id = ? AND asset_path IS NOT NULL',
      variables: [Variable<String>(conversationId)],
    ).get();
    await _db.customStatement('DELETE FROM messages WHERE conversation_id = ?', [conversationId]);
    for (final row in imageRows) {
      final path = row.data['asset_path'] as String?;
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 资产清理失败不阻止删除聊天记录。
      }
    }
    await _db.customStatement('DELETE FROM analyses WHERE conversation_id = ?', [conversationId]);
    await _db.customStatement('DELETE FROM battle_states WHERE conversation_id = ?', [conversationId]);
    final erows = await _db.customSelect('SELECT * FROM memory_entries').get();
    for (final row in erows) {
      final entry = cv.rowToMemoryEntry(row.data);
      if (entry.sources.any((source) => source.conversationId == conversationId)) {
        await _db.customStatement(
          'UPDATE memory_entries SET source_gone = 1 WHERE id = ?',
          [entry.id],
        );
      }
    }
    final cases = await _loadCases();
    _emitCases(cases);
    _messageControllers[conversationId]?.add(const []);
    _analysisControllers[conversationId]?.add(const []);
  }

  @override
  Future<Case> setCasePinned(String caseId, bool pinned) async {
    await _ensureReady();
    final cases = await _loadCases();
    final idx = cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) throw StateError('未找到对话 $caseId');
    final updated = cases[idx].copyWith(pinnedAt: pinned ? DateTime.now() : null);
    await _db.customStatement('UPDATE cases SET pinned_at = ? WHERE id = ?', [updated.pinnedAt?.millisecondsSinceEpoch, caseId]);
    final fresh = await _loadCases();
    _emitCases(fresh);
    return updated;
  }

  @override
  Future<Case> renameCase(String caseId, String title) async {
    await _ensureReady();
    final cases = await _loadCases();
    final idx = cases.indexWhere((c) => c.id == caseId);
    if (idx < 0) throw StateError('未找到对话 $caseId');
    final updated = cases[idx].copyWith(title: title);
    await _db.customStatement('UPDATE cases SET title = ? WHERE id = ?', [title, caseId]);
    final fresh = await _loadCases();
    _emitCases(fresh);
    return updated;
  }

  @override
  Future<void> deleteMemoryForConversation(String conversationId) async {
    await _ensureReady();
    final erows = await _db.customSelect('SELECT * FROM memory_entries').get();
    for (final r in erows) {
      final entry = cv.rowToMemoryEntry(r.data);
      if (entry.sources.any((s) => s.conversationId == conversationId)) {
        await _db.customStatement('DELETE FROM memory_entries WHERE id = ?', [entry.id]);
      }
    }
    _emitMemory(await _loadMemory());
  }

  @override
  Future<void> finalizeConversationsForMemory(List<String> conversationIds) async {
    if (conversationIds.isEmpty) return;
    await _ensureReady();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final convId in conversationIds) {
      await _db.customStatement(
        'UPDATE cases SET memory_finalized_at = ? WHERE id = ? AND memory_finalized_at IS NULL',
        [now, convId],
      );
    }
    _emitCases(await _loadCases());
  }

  @override
  Future<void> markAnalysesProcessed(List<String> analysisIds) async {
    if (analysisIds.isEmpty) return;
    await _ensureReady();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in analysisIds) {
      await _db.customStatement('UPDATE analyses SET memory_processed_at = ? WHERE id = ? AND memory_processed_at IS NULL', [now, id]);
    }
    for (final convId in _analysisControllers.keys.toList()) {
      _emitAnalyses(convId, await _loadAnalyses(convId));
    }
  }

  @override
  Future<int> nextMessageSequence(String conversationId) async {
    await _ensureReady();
    final rows = await _db.customSelect('SELECT MAX(sequence) AS m FROM messages WHERE conversation_id = ?', variables: [Variable<String>(conversationId)]).get();
    final m = rows.first.data['m'] as int?;
    return (m ?? 0) + 1;
  }

  @override
  Future<void> addMessage(Message message) async {
    await _ensureReady();
    final row = cv.messageToRow(message);
    await _db.customStatement(
      'INSERT OR REPLACE INTO messages (id, conversation_id, sequence, created_at, party, type, content, asset_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [row['id'] as String, row['conversation_id'] as String, row['sequence'] as int, row['created_at'] as int, row['party'] as int, row['type'] as int, row['content'] as String, row['asset_path'] as String?],
    );
    _emitMessages(message.conversationId, await _loadMessages(message.conversationId));
    if (message.assetPath != null) {
      final file = File(message.assetPath!);
      if (await file.exists() && await assetByPath(message.assetPath!) == null) {
        await saveAsset(Asset(
          path: message.assetPath!,
          sizeBytes: await file.length(),
          mimeType: _mimeTypeForPath(message.assetPath!),
        ));
      }
    }
  }

  @override
  Future<void> deleteMessage(String conversationId, int sequence) async {
    await _ensureReady();
    await _db.customStatement('DELETE FROM messages WHERE conversation_id = ? AND sequence = ?', [conversationId, sequence]);
    _emitMessages(conversationId, await _loadMessages(conversationId));
  }

  @override
  Future<void> saveAnalysis(Analysis analysis) async {
    await _ensureReady();
    final row = cv.analysisToRow(analysis);
    await _db.customStatement(
      'INSERT OR REPLACE INTO analyses (id, conversation_id, view, channel, model_name, content, cards_json, created_at, token_count, duration_micros, turn_id, memory_processed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [row['id'] as String, row['conversation_id'] as String, row['view'] as int, row['channel'] as int, row['model_name'] as String?, row['content'] as String, row['cards_json'] as String, row['created_at'] as int, row['token_count'] as int, row['duration_micros'] as int?, row['turn_id'] as String? ?? '', row['memory_processed_at'] as int?],
    );
    _emitAnalyses(analysis.conversationId, await _loadAnalyses(analysis.conversationId));
  }

  @override
  Future<void> saveMemory(MemoryProfile memory) async {
    await _ensureReady();
    final row = cv.memoryProfileToRow(memory);
    await _db.customStatement('INSERT OR REPLACE INTO memory_profiles (id, user_summary, partner_summary, relationship_summary, growth_summary, updated_at) VALUES (?, ?, ?, ?, ?, ?)', [row['id'] as String, row['user_summary'] as String?, row['partner_summary'] as String?, row['relationship_summary'] as String?, row['growth_summary'] as String?, row['updated_at'] as int]);
    await _db.customStatement('DELETE FROM memory_entries');
    for (final e in memory.entries) {
      final erow = cv.memoryEntryToRow(e);
      await _db.customStatement('INSERT OR REPLACE INTO memory_entries (id, kind, summary, sources_json, created_at, updated_at, is_deleted, source_gone) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [erow['id'] as String, erow['kind'] as int, erow['summary'] as String, erow['sources_json'] as String, erow['created_at'] as int, erow['updated_at'] as int?, erow['is_deleted'] as int, erow['source_gone'] as int]);
    }
    _emitMemory(await _loadMemory());
  }

  @override
  Future<void> saveAiConfig(AiConfig config) async {
    await _ensureReady();
    final key = config.apiKey.trim();
    if (key.isEmpty) {
      await _secureStorage.delete(key: _apiKeyStorageKey);
    } else {
      await _secureStorage.write(key: _apiKeyStorageKey, value: key);
    }
    final row = cv.aiConfigToRow(config.copyWith(apiKey: '', enabled: key.isNotEmpty));
    await _db.customStatement('INSERT OR REPLACE INTO ai_configs (id, provider, protocol, api_key, model, base_url, enabled) VALUES (?, ?, ?, ?, ?, ?, ?)', [row['id'] as int, row['provider'] as int, row['protocol'] as int, '', row['model'] as String, row['base_url'] as String, row['enabled'] as int]);
    _emitAiConfig(config.copyWith(apiKey: key, enabled: key.isNotEmpty));
  }

  @override
  Future<void> setBattleView(String conversationId, BattleView view) async {
    await _ensureReady();
    await _db.customStatement(
      'UPDATE cases SET last_view = ? WHERE id = ?',
      [view.index, conversationId],
    );
    // 检查该视角是否已有保存的分析卡片（之前运行过该视角分析）。
    final rows = await _db.customSelect(
      'SELECT * FROM battle_states WHERE conversation_id = ? AND view = ?',
      variables: [Variable<String>(conversationId), Variable<int>(view.index)],
    ).get();
    if (rows.isNotEmpty) {
      // 已有 BattleState，直接发射现有状态（保留已有的分析卡片）。
      final existing = cv.rowToBattleState(rows.first.data);
      _emitBattle(conversationId, existing);
    } else {
      // 首次进入该视角，创建空白状态。
      final initial = BattleState.initial(view);
      final row = cv.battleStateToRow(conversationId, initial);
      await _db.customStatement(
        'INSERT INTO battle_states (conversation_id, view, user_score, partner_score, user_hp, partner_hp, user_love, partner_love, justice_balance, headline, cards_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [row['conversation_id'] as String, row['view'] as int, row['user_score'] as double, row['partner_score'] as double, row['user_hp'] as double, row['partner_hp'] as double, row['user_love'] as double, row['partner_love'] as double, row['justice_balance'] as double, row['headline'] as String, row['cards_json'] as String, row['updated_at'] as int],
      );
      _emitBattle(conversationId, initial);
    }
  }

  @override
  Future<void> applyAnalysisToBattle({
    required Analysis analysis,
    required List<BattleCard> cards,
    String headline = '',
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
  }) async {
    await _ensureReady();
    final state = BattleState(
      view: analysis.view,
      userScore: 50,
      partnerScore: 50,
      userHp: 1,
      partnerHp: 1,
      userLove: 0.5,
      partnerLove: 0.5,
      justiceBalance: 0,
      headline: headline.isEmpty ? _headlineFor(analysis.view) : headline,
      cards: cards,
      updatedAt: DateTime.now(),
      thinkingContent: thinkingContent,
      thinkingStartedAt: thinkingStartedAt,
      thinkingFinishedAt: thinkingFinishedAt,
      thinkingActive: thinkingActive,
    );
    final row = cv.battleStateToRow(analysis.conversationId, state);
    await _db.customStatement(
      'INSERT OR REPLACE INTO battle_states '
      '(conversation_id, view, user_score, partner_score, user_hp, partner_hp, '
      'user_love, partner_love, justice_balance, headline, cards_json, updated_at, '
      'thinking_content, thinking_started_at, thinking_finished_at, thinking_active) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        row['conversation_id'] as String,
        row['view'] as int,
        row['user_score'] as double,
        row['partner_score'] as double,
        row['user_hp'] as double,
        row['partner_hp'] as double,
        row['user_love'] as double,
        row['partner_love'] as double,
        row['justice_balance'] as double,
        row['headline'] as String,
        row['cards_json'] as String,
        row['updated_at'] as int,
        row['thinking_content'] as String?,
        row['thinking_started_at'] as int?,
        row['thinking_finished_at'] as int?,
        row['thinking_active'] as int,
      ],
    );
    _emitBattle(analysis.conversationId, state);
  }

  @override
  Future<void> saveThinkingState({
    required String conversationId,
    required BattleView view,
    String? thinkingContent,
    DateTime? thinkingStartedAt,
    DateTime? thinkingFinishedAt,
    bool thinkingActive = false,
  }) async {
    await _ensureReady();
    final rows = await _db.customSelect(
      'SELECT * FROM battle_states WHERE conversation_id = ? AND view = ?',
      variables: [Variable<String>(conversationId), Variable<int>(view.index)],
    ).get();
    if (rows.isEmpty) return;
    final existing = cv.rowToBattleState(rows.first.data);
    final updated = existing.copyWith(
      thinkingContent: thinkingContent,
      thinkingStartedAt: thinkingStartedAt,
      thinkingFinishedAt: thinkingFinishedAt,
      thinkingActive: thinkingActive,
      updatedAt: DateTime.now(),
    );
    final row = cv.battleStateToRow(conversationId, updated);
    await _db.customStatement(
      'UPDATE battle_states SET '
      'thinking_content = ?, thinking_started_at = ?, '
      'thinking_finished_at = ?, thinking_active = ?, updated_at = ? '
      'WHERE conversation_id = ? AND view = ?',
      [
        row['thinking_content'] as String?,
        row['thinking_started_at'] as int?,
        row['thinking_finished_at'] as int?,
        row['thinking_active'] as int,
        row['updated_at'] as int,
        conversationId,
        view.index,
      ],
    );
    _emitBattle(conversationId, updated);
  }

  String _headlineFor(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '先看看这段对话里的在乎、需求，以及还有多少修复空间。';
      case BattleView.right:
        return '把事实和表达分开看，不急着给任何一方下结论。';
      case BattleView.win:
        return '看看谁暂时占了上风，以及这场胜负真正的代价。';
    }
  }

  @override
  void dispose() {
    _caseController.close();
    _memoryController.close();
    _aiConfigController.close();
    for (final c in _messageControllers.values) c.close();
    for (final c in _analysisControllers.values) c.close();
    for (final c in _battleControllers.values) c.close();
    _assetController.close();
    _db.close();
  }
}
