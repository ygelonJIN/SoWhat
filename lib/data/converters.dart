import 'dart:convert';

import '../models/models.dart';

int _epoch(DateTime dt) => dt.millisecondsSinceEpoch;
DateTime _fromEpoch(int v) => DateTime.fromMillisecondsSinceEpoch(v);

// ── BattleView / AiChannel / enums ↔ int ────────────────────────────────

BattleView _viewFrom(int v) => BattleView.values[v];
int _viewTo(BattleView v) => v.index;

AiChannel _channelFrom(int v) => AiChannel.values[v];
int _channelTo(AiChannel c) => c.index;

Party _partyFrom(int v) => Party.values[v];
int _partyTo(Party p) => p.index;

MessageType _typeFrom(int v) => MessageType.values[v];
int _typeTo(MessageType t) => t.index;

MemoryKind _kindFrom(int v) => MemoryKind.values[v];
int _kindTo(MemoryKind k) => k.index;

AiProvider _providerFrom(int v) => AiProvider.values[v];
int _providerTo(AiProvider p) => p.index;

AiProtocol _protocolFrom(int v) => AiProtocol.values[v];
int _protocolTo(AiProtocol p) => p.index;

// ── JSON helpers ────────────────────────────────────────────────────────

String _encode(Object v) => jsonEncode(v);
dynamic _decode(String s) => jsonDecode(s);

// ── Case ────────────────────────────────────────────────────────────────

Map<String, dynamic> caseToRow(Case c) => {
  'id': c.id,
  'title': c.title,
  'created_at': _epoch(c.createdAt),
  'pinned_at': c.pinnedAt == null ? null : _epoch(c.pinnedAt!),
  'background': c.background,
  'memory_finalized_at': c.memoryFinalizedAt == null
      ? null
      : _epoch(c.memoryFinalizedAt!),
  'is_imported': c.isImported ? 1 : 0,
  'last_view': _viewTo(c.lastView),
};

Case rowToCase(Map<String, dynamic> row) => Case(
  id: row['id'] as String,
  title: row['title'] as String?,
  createdAt: _fromEpoch(row['created_at'] as int),
  pinnedAt: row['pinned_at'] == null
      ? null
      : _fromEpoch(row['pinned_at'] as int),
  background: row['background'] as String?,
  memoryFinalizedAt: row['memory_finalized_at'] == null
      ? null
      : _fromEpoch(row['memory_finalized_at'] as int),
  isImported: (row['is_imported'] as int? ?? 0) != 0,
  lastView: row['last_view'] == null
      ? BattleView.love
      : _viewFrom(row['last_view'] as int),
);

// ── Message ─────────────────────────────────────────────────────────────

Map<String, dynamic> messageToRow(Message m) => {
  'id': m.id,
  'conversation_id': m.conversationId,
  'sequence': m.sequence,
  'created_at': _epoch(m.createdAt),
  'party': _partyTo(m.party),
  'type': _typeTo(m.type),
  'content': m.content,
  'asset_path': m.assetPath,
};

Message rowToMessage(Map<String, dynamic> row) => Message(
  id: row['id'] as String,
  conversationId: row['conversation_id'] as String,
  sequence: row['sequence'] as int,
  createdAt: _fromEpoch(row['created_at'] as int),
  party: _partyFrom(row['party'] as int),
  type: _typeFrom(row['type'] as int),
  content: row['content'] as String,
  assetPath: row['asset_path'] as String?,
);

// ── Analysis ────────────────────────────────────────────────────────────

String _cardsJson(List<AnalysisCard> cards) => _encode(
  cards
      .map(
        (c) => {
          'title': c.title,
          'conclusion': c.conclusion,
          'evidence': c.evidence,
          'speculation': c.speculation,
        },
      )
      .toList(),
);

List<AnalysisCard> _parseCards(String s) {
  final list = _decode(s) as List;
  return list
      .map(
        (e) => AnalysisCard(
          title: (e['title'] ?? '') as String,
          conclusion: (e['conclusion'] ?? '') as String,
          evidence: e['evidence'] as String?,
          speculation: e['speculation'] as String?,
        ),
      )
      .toList();
}

Map<String, dynamic> analysisToRow(Analysis a) => {
  'id': a.id,
  'conversation_id': a.conversationId,
  'view': _viewTo(a.view),
  'channel': _channelTo(a.channel),
  'model_name': a.modelName,
  'content': a.content,
  'cards_json': _cardsJson(a.cards),
  'created_at': _epoch(a.createdAt),
  'token_count': a.tokenCount,
  'duration_micros': a.duration?.inMicroseconds,
  'turn_id': a.turnId,
  'memory_processed_at': a.memoryProcessedAt == null
      ? null
      : _epoch(a.memoryProcessedAt!),
};

Analysis rowToAnalysis(Map<String, dynamic> row) => Analysis(
  id: row['id'] as String,
  conversationId: row['conversation_id'] as String,
  view: _viewFrom(row['view'] as int),
  channel: _channelFrom(row['channel'] as int),
  modelName: row['model_name'] as String?,
  content: row['content'] as String,
  cards: _parseCards(row['cards_json'] as String),
  createdAt: _fromEpoch(row['created_at'] as int),
  tokenCount: row['token_count'] as int,
  duration: row['duration_micros'] == null
      ? null
      : Duration(microseconds: row['duration_micros'] as int),
  turnId: row['turn_id'] as String? ?? '',
  memoryProcessedAt: row['memory_processed_at'] == null
      ? null
      : _fromEpoch(row['memory_processed_at'] as int),
);

// ── BattleState / BattleCard ────────────────────────────────────────────

String _battleCardsJson(List<BattleCard> cards) => _encode(
  cards
      .map(
        (c) => {
          'title': c.title,
          'conclusion': c.conclusion,
          'evidence': c.evidence,
          'speculation': c.speculation,
        },
      )
      .toList(),
);

List<BattleCard> _parseBattleCards(String s) {
  final list = _decode(s) as List;
  return list
      .map(
        (e) => BattleCard(
          title: (e['title'] ?? '') as String,
          conclusion: (e['conclusion'] ?? '') as String,
          evidence: (e['evidence'] ?? '') as String,
          speculation: e['speculation'] as String?,
        ),
      )
      .toList();
}

Map<String, dynamic> battleStateToRow(String conversationId, BattleState b) =>
    {
      'conversation_id': conversationId,
      'view': _viewTo(b.view),
      'user_score': b.userScore,
      'partner_score': b.partnerScore,
      'user_hp': b.userHp,
      'partner_hp': b.partnerHp,
      'user_love': b.userLove,
      'partner_love': b.partnerLove,
      'justice_balance': b.justiceBalance,
      'headline': b.headline,
      'cards_json': _battleCardsJson(b.cards),
      'updated_at': _epoch(b.updatedAt),
      'thinking_content': b.thinkingContent,
      'thinking_started_at':
          b.thinkingStartedAt == null ? null : _epoch(b.thinkingStartedAt!),
      'thinking_finished_at':
          b.thinkingFinishedAt == null ? null : _epoch(b.thinkingFinishedAt!),
      'thinking_active': b.thinkingActive ? 1 : 0,
    };

BattleState rowToBattleState(Map<String, dynamic> row) => BattleState(
  view: _viewFrom(row['view'] as int),
  userScore: (row['user_score'] as num).toDouble(),
  partnerScore: (row['partner_score'] as num).toDouble(),
  userHp: (row['user_hp'] as num).toDouble(),
  partnerHp: (row['partner_hp'] as num).toDouble(),
  userLove: (row['user_love'] as num).toDouble(),
  partnerLove: (row['partner_love'] as num).toDouble(),
  justiceBalance: (row['justice_balance'] as num).toDouble(),
  headline: row['headline'] as String,
  cards: _parseBattleCards(row['cards_json'] as String),
  updatedAt: _fromEpoch(row['updated_at'] as int),
  thinkingContent: row['thinking_content'] as String?,
  thinkingStartedAt: row['thinking_started_at'] == null
      ? null
      : _fromEpoch(row['thinking_started_at'] as int),
  thinkingFinishedAt: row['thinking_finished_at'] == null
      ? null
      : _fromEpoch(row['thinking_finished_at'] as int),
  thinkingActive: (row['thinking_active'] as int? ?? 0) != 0,
);

// ── MemoryEntry ─────────────────────────────────────────────────────────

String _sourcesJson(List<MemorySourceRef> sources) => _encode(
  sources
      .map(
        (s) => {
          'conversation_id': s.conversationId,
          'analysis_id': s.analysisId,
          'happened_at': _epoch(s.happenedAt),
        },
      )
      .toList(),
);

List<MemorySourceRef> _parseSources(String s) {
  final list = _decode(s) as List;
  return list
      .map(
        (e) => MemorySourceRef(
          conversationId: e['conversation_id'] as String,
          analysisId: e['analysis_id'] as String?,
          happenedAt: _fromEpoch(e['happened_at'] as int),
        ),
      )
      .toList();
}

Map<String, dynamic> memoryEntryToRow(MemoryEntry e) => {
  'id': e.id,
  'kind': _kindTo(e.kind),
  'summary': e.summary,
  'sources_json': _sourcesJson(e.sources),
  'created_at': _epoch(e.createdAt),
  'updated_at': e.updatedAt == null ? null : _epoch(e.updatedAt!),
  'is_deleted': e.isDeleted ? 1 : 0,
  'source_gone': e.sourceGone ? 1 : 0,
};

MemoryEntry rowToMemoryEntry(Map<String, dynamic> row) => MemoryEntry(
  id: row['id'] as String,
  kind: _kindFrom(row['kind'] as int),
  summary: row['summary'] as String,
  sources: _parseSources(row['sources_json'] as String),
  createdAt: _fromEpoch(row['created_at'] as int),
  updatedAt: row['updated_at'] == null
      ? null
      : _fromEpoch(row['updated_at'] as int),
  isDeleted: (row['is_deleted'] as int) != 0,
  sourceGone: (row['source_gone'] as int? ?? 0) != 0,
);

// ── MemoryProfile ───────────────────────────────────────────────────────

Map<String, dynamic> memoryProfileToRow(MemoryProfile p) => {
  'id': p.id,
  'user_summary': p.userSummary,
  'partner_summary': p.partnerSummary,
  'relationship_summary': p.relationshipSummary,
  'growth_summary': p.growthSummary,
  'updated_at': _epoch(p.updatedAt),
};

// ── Asset ───────────────────────────────────────────────────────────────

Map<String, dynamic> assetToRow(Asset asset) => {
  'id': asset.id,
  'path': asset.path,
  'title': asset.title,
  'created_at': _epoch(asset.createdAt),
  'size_bytes': asset.sizeBytes,
  'mime_type': asset.mimeType,
};

Asset rowToAsset(Map<String, dynamic> row) => Asset(
  id: row['id'] as String,
  path: row['path'] as String,
  title: row['title'] as String? ?? '',
  createdAt: _fromEpoch(row['created_at'] as int),
  sizeBytes: row['size_bytes'] as int? ?? 0,
  mimeType: row['mime_type'] as String? ?? 'image/jpeg',
);

// ── AiConfig ────────────────────────────────────────────────────────────

Map<String, dynamic> aiConfigToRow(AiConfig c) => {
  'id': 1,
  'provider': _providerTo(c.provider),
  'protocol': _protocolTo(c.protocol),
  'api_key': c.apiKey,
  'model': c.model,
  'base_url': c.baseUrl,
  'enabled': c.enabled ? 1 : 0,
};

AiConfig rowToAiConfig(Map<String, dynamic> row) => AiConfig(
  provider: _providerFrom(row['provider'] as int),
  protocol: _protocolFrom(row['protocol'] as int),
  apiKey: row['api_key'] as String,
  model: row['model'] as String,
  baseUrl: row['base_url'] as String,
  enabled: (row['enabled'] as int) != 0,
);
