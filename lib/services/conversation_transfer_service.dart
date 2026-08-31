import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';

/// 聊天记录完整导入导出（.sowhat.zip）：JSON manifest + 对话/分析数据 +
/// 本地图片资产。
///
/// 健壮性（v0.16）：
/// - manifest 带 SHA-256 校验和，导入先验后解，包损坏/截断直接拒绝；
/// - 导入先完整解析 + 校验、再写文件、最后一次性入库（[AppRepository.importCaseData]
///   单事务），任一步失败都不留半套数据；
/// - 内容指纹去重：同一对话重复导入直接返回已有对话，不产生副本；
/// - 分析数据完整恢复：含卡片、战场状态（切视角即可见）、已消化标记。
class ConversationTransferService {
  const ConversationTransferService();

  /// 当前格式版本。v2 起 manifest 含 checksum_sha256；导入兼容 v1（无校验和）。
  static const formatVersion = 2;

  static const _formatName = 'so_what_conversation';

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
      'format': _formatName,
      'version': formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'conversation_id': conversationId,
      'view_mapping': {'a': 'you', 'b': 'partner'},
      'contains_api_key': false,
      'message_count': messageRows.length,
      'analysis_count': analyses.length,
      // 占位：打包完成后对全部内容文件重算填入（不含 manifest 自身）。
      'checksum_sha256': '',
    };
    archive.addFile(_utf8File('manifest.json', manifest));
    archive.addFile(_utf8File('conversation.json', {
      'id': caseItem.id,
      'title': caseItem.title,
      'created_at': caseItem.createdAt.toIso8601String(),
      'pinned': caseItem.pinnedAt != null,
      'background': caseItem.background,
      'last_view': caseItem.lastView.index,
    }));
    archive.addFile(_utf8File('messages.json', messageRows));
    archive.addFile(_utf8File(
      'analyses.json',
      analyses.map(_analysisMap).toList(),
    ));
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    // 重算校验和（覆盖除 manifest 外的全部文件，按文件名排序保证确定性）。
    final checksum = _archiveChecksum(archive);
    archive
      ..clear()
      ..addFile(_utf8File('manifest.json', {...manifest, 'checksum_sha256': checksum}))
      ..addFile(_utf8File('conversation.json', {
        'id': caseItem.id,
        'title': caseItem.title,
        'created_at': caseItem.createdAt.toIso8601String(),
        'pinned': caseItem.pinnedAt != null,
        'background': caseItem.background,
        'last_view': caseItem.lastView.index,
      }))
      ..addFile(_utf8File('messages.json', messageRows))
      ..addFile(_utf8File(
        'analyses.json',
        analyses.map(_analysisMap).toList(),
      ));
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final output = await getTemporaryDirectory();
    final safeTitle = (caseItem.title?.trim().isNotEmpty ?? false)
        ? caseItem.title!.trim()
        : 'conversation';
    final file = File(p.join(output.path, '$safeTitle.sowhat.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  /// 导入一段对话，返回导入后的对话 id（重复导入时返回已存在的那条）。
  Future<String> importConversation({
    required AppRepository repository,
    required File archiveFile,
  }) async {
    final bytes = await archiveFile.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('导入包损坏：不是有效的 ZIP 文件。');
    }

    final manifest = _jsonFile(archive, 'manifest.json');
    if (manifest['format'] != _formatName) {
      throw const FormatException('不是 So What 聊天导入包（格式标识不符）。');
    }
    final version = (manifest['version'] as num?)?.toInt() ?? 0;
    if (version != 1 && version != formatVersion) {
      throw FormatException('不支持的导入包版本（$version），请升级 App 后再试。');
    }
    // v2 起校验完整性：先验后解，损坏/截断的包直接拒绝，不写任何数据。
    if (version >= 2) {
      final expected = manifest['checksum_sha256']?.toString() ?? '';
      if (expected.isEmpty) {
        throw const FormatException('导入包缺少校验和，文件可能不完整。');
      }
      final actual = _archiveChecksum(archive);
      if (actual != expected) {
        throw const FormatException('导入包校验和不一致，文件已损坏或传输不完整，请重新导出。');
      }
    }

    // ── 先完整解析 + 校验，全部通过后才开始写任何文件 / 数据 ──
    final conversation = _jsonFile(archive, 'conversation.json');
    final sourceId = conversation['id']?.toString() ?? '';
    final createdAt =
        DateTime.tryParse(conversation['created_at']?.toString() ?? '') ??
        DateTime.now();
    final title = conversation['title']?.toString();

    final messageList = _jsonFile(archive, 'messages.json');
    if (messageList is! List) {
      throw const FormatException('导入包 messages.json 结构异常。');
    }
    final analysisList = _jsonFile(archive, 'analyses.json');
    if (analysisList is! List) {
      throw const FormatException('导入包 analyses.json 结构异常。');
    }

    final parsedMessages = <Message>[];
    final fingerprintParts = <String>[];
    for (final raw in messageList) {
      if (raw is! Map) continue;
      final message = Message(
        conversationId: '', // 导入后统一改为新 id
        sequence: (raw['sequence'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
            DateTime.now(),
        party: _enumValue(Party.values, raw['party']),
        type: _enumValue(MessageType.values, raw['type']),
        content: raw['content']?.toString() ?? '',
        assetPath: null,
      );
      parsedMessages.add(message);
      // 内容指纹：party|sequence|created_at|content|资源文件名。
      fingerprintParts.add(
        '${message.party.index}|${message.sequence}|${message.createdAt.toIso8601String()}|${message.content}|${raw['asset']?.toString() ?? ''}',
      );
    }

    // 重复导入去重：与已有对话的内容指纹比对，一致则直接复用，不产生副本。
    final fingerprint =
        sha256.convert(utf8.encode(fingerprintParts.join('\n'))).toString();
    final existingCases = await repository.watchCases().first;
    for (final existing in existingCases) {
      final existingMessages =
          await repository.watchMessages(existing.id).first;
      final existingParts = existingMessages
          .map(
            (m) =>
                '${m.party.index}|${m.sequence}|${m.createdAt.toIso8601String()}|${m.content}|${m.assetPath == null ? '' : p.basename(m.assetPath!)}',
          )
          .toList();
      if (sha256.convert(utf8.encode(existingParts.join('\n'))).toString() ==
          fingerprint) {
        return existing.id;
      }
    }

    final parsedAnalyses = <Analysis>[];
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
                .where(
                  (card) =>
                      card.title.isNotEmpty && card.conclusion.isNotEmpty,
                )
                .toList()
          : <AnalysisCard>[];
      parsedAnalyses.add(
        Analysis(
          conversationId: '', // 导入后统一改为新 id
          view: _enumValue(BattleView.values, raw['view']),
          channel: _enumValue(AiChannel.values, raw['channel']),
          modelName: raw['model_name']?.toString(),
          content: raw['content']?.toString() ?? '',
          cards: cards,
          createdAt:
              DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
              DateTime.now(),
          tokenCount: (raw['token_count'] as num?)?.toInt() ?? 0,
          duration: raw['duration_micros'] == null
              ? null
              : Duration(microseconds: (raw['duration_micros'] as num).toInt()),
          turnId: raw['turn_id']?.toString() ?? '',
          memoryProcessedAt:
              DateTime.tryParse(raw['memory_processed_at']?.toString() ?? ''),
          summary: raw['summary']?.toString(),
        ),
      );
    }

    // ── 解析校验通过：分配新 id，写图片文件 ──
    final generatedId = const Uuid().v4();
    final id = sourceId.isEmpty ? generatedId : '$sourceId-$generatedId';
    final imported = Case(
      id: id,
      title: title,
      createdAt: createdAt,
      background: conversation['background']?.toString(),
      isImported: true,
      lastView: _enumValue(BattleView.values, conversation['last_view']),
    );

    final assetDirectory = await getApplicationDocumentsDirectory();
    final importedAssets = Directory(
      p.join(assetDirectory.path, 'assets', 'imports'),
    );
    await importedAssets.create(recursive: true);

    // 先写文件、失败清理；再入库（单事务）。文件写入发生在事务前，
    // 若入库失败删除已写文件，不留孤儿资源。
    final writtenFiles = <File>[];
    try {
      for (var i = 0; i < parsedMessages.length; i++) {
        final message = parsedMessages[i];
        final raw = messageList[i];
        if (raw is! Map) continue;
        final asset = raw['asset']?.toString();
        if (asset == null) continue;
        final file = archive.findFile(asset);
        if (file == null) continue;
        final target = File(
          p.join(
            importedAssets.path,
            '${const Uuid().v4()}${p.extension(asset)}',
          ),
        );
        await target.writeAsBytes(file.content as List<int>, flush: true);
        writtenFiles.add(target);
        parsedMessages[i] = message.copyWith(
          conversationId: id,
          assetPath: target.path,
        );
      }
      // 无图片消息 / 分析统一改绑新对话 id。
      for (var i = 0; i < parsedMessages.length; i++) {
        if (parsedMessages[i].conversationId != id) {
          parsedMessages[i] = parsedMessages[i].copyWith(conversationId: id);
        }
      }
      for (var i = 0; i < parsedAnalyses.length; i++) {
        parsedAnalyses[i] = parsedAnalyses[i].copyWith(conversationId: id);
      }

      await repository.importCaseData(
        caseItem: imported,
        messages: parsedMessages,
        analyses: parsedAnalyses,
      );
    } catch (error) {
      // 入库失败：删除已写资源文件，保证不留半套导入数据。
      for (final file in writtenFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // 清理失败不掩盖原始错误。
        }
      }
      rethrow;
    }
    return id;
  }

  ArchiveFile _utf8File(String name, Object json) {
    final bytes = utf8.encode(jsonEncode(json));
    return ArchiveFile(name, bytes.length, bytes);
  }

  /// 全部内容文件（不含 manifest）按文件名排序后拼接的 SHA-256，用于
  /// 导入前校验包完整性。
  String _archiveChecksum(Archive archive) {
    final names = archive.files
        .map((f) => f.name)
        .where((name) => name != 'manifest.json')
        .toList()
      ..sort();
    final bytes = <int>[];
    for (final name in names) {
      final file = archive.findFile(name);
      if (file == null) continue;
      bytes.addAll(file.content as List<int>);
    }
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> _analysisMap(Analysis analysis) => {
        'id': analysis.id,
        'view': analysis.view.index,
        'channel': analysis.channel.index,
        'model_name': analysis.modelName,
        'content': analysis.content,
        'created_at': analysis.createdAt.toIso8601String(),
        'token_count': analysis.tokenCount,
        'duration_micros': analysis.duration?.inMicroseconds,
        'turn_id': analysis.turnId,
        'memory_processed_at': analysis.memoryProcessedAt?.toIso8601String(),
        'summary': analysis.summary,
        'cards': analysis.cards
            .map(
              (card) => {
                'title': card.title,
                'conclusion': card.conclusion,
                'evidence': card.evidence,
                'speculation': card.speculation,
              },
            )
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
