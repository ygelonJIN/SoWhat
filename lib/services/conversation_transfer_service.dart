import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';

/// 聊天记录完整导入导出：JSON manifest + 对话/分析数据 + 本地图片资产。
class ConversationTransferService {
  const ConversationTransferService();

  static const formatVersion = 1;

  Future<File> exportConversation({
    required AppRepository repository,
    required String conversationId,
  }) async {
    final cases = await repository.watchCases().first;
    final caseItem = cases.firstWhere((item) => item.id == conversationId);
    final messages = await repository.watchMessages(conversationId).first;
    final analyses = await repository.watchAnalyses(conversationId).first;
    final files = <String, List<int>>{};
    final messageRows = <Map<String, dynamic>>[];

    for (final message in messages) {
      final row = {
        'id': message.id,
        'sequence': message.sequence,
        'created_at': message.createdAt.toIso8601String(),
        'party': message.party.index,
        'type': message.type.index,
        'content': message.content,
      };
      final assetPath = message.assetPath;
      if (assetPath != null && assetPath.isNotEmpty) {
        final file = File(assetPath);
        if (await file.exists()) {
          final name = 'assets/${p.basename(assetPath)}';
          files[name] = await file.readAsBytes();
          row['asset'] = name;
        }
      }
      messageRows.add(row);
    }

    final archive = Archive();
    final manifest = {
      'format': 'so_what_conversation',
      'version': formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'conversation_id': conversationId,
      'view_mapping': {'a': 'you', 'b': 'partner'},
      'contains_api_key': false,
    };
    final manifestJson = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson));
    final conversationJson = utf8.encode(jsonEncode({
      'id': caseItem.id,
      'title': caseItem.title,
      'created_at': caseItem.createdAt.toIso8601String(),
      'pinned': caseItem.pinnedAt != null,
      'background': caseItem.background,
      'last_view': caseItem.lastView.index,
    }));
    archive.addFile(ArchiveFile('conversation.json', conversationJson.length, conversationJson));
    final messagesJson = utf8.encode(jsonEncode(messageRows));
    archive.addFile(ArchiveFile('messages.json', messagesJson.length, messagesJson));
    final analysesJson = utf8.encode(jsonEncode(analyses.map(_analysisMap).toList()));
    archive.addFile(ArchiveFile('analyses.json', analysesJson.length, analysesJson));
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final output = await getTemporaryDirectory();
    final safeTitle = (caseItem.title?.trim().isNotEmpty ?? false)
        ? caseItem.title!.trim()
        : 'conversation';
    final file = File(p.join(output.path, '$safeTitle.lrw.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  Future<String> importConversation({
    required AppRepository repository,
    required File archiveFile,
  }) async {
    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = _jsonFile(archive, 'manifest.json');
    if (manifest['format'] != 'so_what_conversation' ||
        manifest['version'] != formatVersion) {
      throw const FormatException('不支持的聊天导入包版本');
    }
    final conversation = _jsonFile(archive, 'conversation.json');
    final sourceId = conversation['id']?.toString() ?? '';
    final generatedId = const Uuid().v4();
    final id = sourceId.isEmpty ? generatedId : '$sourceId-${generatedId.substring(0, 8)}';
    final createdAt = DateTime.tryParse(conversation['created_at']?.toString() ?? '') ?? DateTime.now();
    final imported = Case(
      id: id,
      title: conversation['title']?.toString(),
      createdAt: createdAt,
      background: conversation['background']?.toString(),
      isImported: true,
      lastView: _enumValue(BattleView.values, conversation['last_view']),
    );
    await repository.upsertCase(imported);

    final assetDirectory = await getApplicationDocumentsDirectory();
    final importedAssets = Directory(p.join(assetDirectory.path, 'assets', 'imports'));
    await importedAssets.create(recursive: true);
    final analysisList = _jsonFile(archive, 'analyses.json');
    if (analysisList is List) {
      for (final raw in analysisList) {
        if (raw is! Map) continue;
        final cards = raw['cards'] is List
            ? (raw['cards'] as List)
                  .whereType<Map>()
                  .map(
                    (card) => AnalysisCard(
                      title: card['title']?.toString() ?? '',
                      conclusion: card['conclusion']?.toString() ?? '',
                      evidence: card['evidence']?.toString(),
                      speculation: card['speculation']?.toString(),
                    ),
                  )
                  .where((card) => card.title.isNotEmpty && card.conclusion.isNotEmpty)
                  .toList()
            : <AnalysisCard>[];
        await repository.saveAnalysis(
          Analysis(
            conversationId: id,
            view: _enumValue(BattleView.values, raw['view']),
            channel: _enumValue(AiChannel.values, raw['channel']),
            modelName: raw['model_name']?.toString(),
            content: raw['content']?.toString() ?? '',
            cards: cards,
            createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? '') ?? DateTime.now(),
          ),
        );
      }
    }
    final messageList = _jsonFile(archive, 'messages.json');
    if (messageList is List) {
      for (final raw in messageList) {
        if (raw is! Map) continue;
        String? assetPath;
        final asset = raw['asset']?.toString();
        if (asset != null) {
          final file = archive.findFile(asset);
          if (file != null) {
            final target = File(p.join(importedAssets.path, '${const Uuid().v4()}${p.extension(asset)}'));
            await target.writeAsBytes(file.content as List<int>);
            assetPath = target.path;
          }
        }
        await repository.addMessage(Message(
          conversationId: id,
          sequence: (raw['sequence'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? '') ?? DateTime.now(),
          party: _enumValue(Party.values, raw['party']),
          type: _enumValue(MessageType.values, raw['type']),
          content: raw['content']?.toString() ?? '',
          assetPath: assetPath,
        ));
      }
    }
    return id;
  }

  Map<String, dynamic> _analysisMap(Analysis analysis) => {
        'id': analysis.id,
        'view': analysis.view.index,
        'channel': analysis.channel.index,
        'model_name': analysis.modelName,
        'content': analysis.content,
        'created_at': analysis.createdAt.toIso8601String(),
        'cards': analysis.cards
            .map((card) => {
                  'title': card.title,
                  'conclusion': card.conclusion,
                  'evidence': card.evidence,
                  'speculation': card.speculation,
                })
            .toList(),
      };

  dynamic _jsonFile(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) throw FormatException('导入包缺少 $path');
    return jsonDecode(utf8.decode(file.content as List<int>));
  }

  T _enumValue<T>(List<T> values, dynamic value) {
    final index = (value as num?)?.toInt() ?? 0;
    return values[index.clamp(0, values.length - 1)];
  }
}
