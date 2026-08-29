import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// 一张待发送的本地图片（截图 / 相册原图）。
class MessageImage {
  final String path;

  const MessageImage(this.path);
}

/// 直接调用模型厂商 HTTP 接口（BYOK，产品文档 6.1 通道 B）。
///
/// 本期支持小米 MiMo（mimo-v2.5-pro），同一厂商可选两种兼容协议：
/// - OpenAI 兼容：`POST {base}/chat/completions`，`Authorization: Bearer`
/// - Anthropic 兼容：`POST {base}/v1/messages`，`x-api-key`
///
/// 只做「发请求 → 取文本」，结构化解析交给调用方（分析卡片 / 记忆生成）。
class AiClient {
  const AiClient();

  static const _connectTimeout = Duration(seconds: 20);
  static const _responseTimeout = Duration(seconds: 90);

  /// 官方限制：单张图片的 Base64 字符串不能超过 50 MB。
  static const _maxBase64ImageBytes = 50 * 1024 * 1024;

  /// 发一轮对话，返回模型回复的纯文本。
  ///
  /// [images] 为本地图片路径：读取字节 → base64 → 按协议拼进用户消息
  /// （Anthropic 用 image source 块，OpenAI 用 image_url data URL），
  /// 图片与文字按顺序同时发给模型。
  ///
  /// 失败时抛出 [AiRequestException]（含状态码与错误摘要，可直接展示给用户）。
  Future<String> chat({
    required AiConfig config,
    required String system,
    required String user,
    List<MessageImage> images = const [],
    int maxTokens = 4096,
  }) async {
    final http = HttpClient()..connectionTimeout = _connectTimeout;
    var payloadBytes = 0;
    try {
      final request = await _buildRequest(config, system, user, images,
          maxTokens: maxTokens);
      final httpRequest = await http.postUrl(request.uri);
      httpRequest.headers.contentType = ContentType.json;
      request.headers.forEach(httpRequest.headers.set);
      final body = utf8.encode(jsonEncode(request.body));
      payloadBytes = body.length;
      httpRequest.add(body);

      final response =
          await httpRequest.close().timeout(_responseTimeout);
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw AiRequestException(
          '接口返回 ${response.statusCode}：${_errorSnippet(text)}',
        );
      }
      return _extractText(config.protocol, text);
    } on AiRequestException {
      rethrow;
    } on TimeoutException {
      throw const AiRequestException('请求超时，请检查网络后重试。');
    } on SocketException catch (error) {
      throw AiRequestException(_connectionError(error, payloadBytes: payloadBytes));
    } on HttpException catch (error) {
      throw AiRequestException(_connectionError(error, payloadBytes: payloadBytes));
    } on HandshakeException catch (error) {
      throw AiRequestException(_connectionError(error, payloadBytes: payloadBytes));
    } catch (error) {
      throw AiRequestException('请求失败：$error');
    } finally {
      http.close(force: true);
    }
  }

  /// 流式对话（SSE）：增量回调思考过程与正文，最终返回完整正文。
  ///
  /// - [onThinking] 收到增量 thinking（reasoning_content / thinking_delta 等）
  /// - [onContent] 收到增量正文
  /// 不支持流式的服务端会回退为普通 JSON，直接一次性回调。
  ///
  /// 连接层失败（部分服务端拒绝 `stream: true` 或长连接被重置）时，
  /// 自动回退为非流式请求重试一次，保证分析可用；重试仍失败才抛出错误。
  Future<String> chatStream({
    required AiConfig config,
    required String system,
    required String user,
    List<MessageImage> images = const [],
    int maxTokens = 4096,
    void Function(String deltaThinking)? onThinking,
    void Function(String deltaContent)? onContent,
  }) async {
    try {
      return await _chatStreamOnce(
        config: config,
        system: system,
        user: user,
        images: images,
        maxTokens: maxTokens,
        onThinking: onThinking,
        onContent: onContent,
      );
    } on _ConnectionException catch (error) {
      onThinking?.call('\n流式连接失败，已自动切换为一次性请求重试…');
      return _fallbackPlain(
        config: config,
        system: system,
        user: user,
        images: images,
        maxTokens: maxTokens,
        onThinking: onThinking,
        onContent: onContent,
        payloadBytes: error.payloadBytes,
      );
    } on _ServerRejectException catch (error) {
      onThinking?.call('\n流式请求被服务端拒绝，已自动切换为一次性请求重试…');
      return _fallbackPlain(
        config: config,
        system: system,
        user: user,
        images: images,
        onThinking: onThinking,
        onContent: onContent,
        payloadBytes: error.payloadBytes,
      );
    }
  }

  Future<String> _chatStreamOnce({
    required AiConfig config,
    required String system,
    required String user,
    required List<MessageImage> images,
    int maxTokens = 4096,
    void Function(String deltaThinking)? onThinking,
    void Function(String deltaContent)? onContent,
  }) async {
    final http = HttpClient()..connectionTimeout = _connectTimeout;
    var payloadBytes = 0;
    try {
      final request = await _buildRequest(
        config,
        system,
        user,
        images,
        stream: true,
        maxTokens: maxTokens,
      );
      final httpRequest = await http.postUrl(request.uri);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set('Accept', 'text/event-stream');
      request.headers.forEach(httpRequest.headers.set);
      final body = utf8.encode(jsonEncode(request.body));
      payloadBytes = body.length;
      httpRequest.add(body);

      final response = await httpRequest.close().timeout(_responseTimeout);
      final isEventStream =
          (response.headers.value('content-type') ?? '').contains('text/event-stream');

      if (response.statusCode != 200) {
        final text = await response.transform(utf8.decoder).join();
        throw _ServerRejectException(
          response.statusCode,
          _errorSnippet(text),
          payloadBytes: payloadBytes,
        );
      }

      if (!isEventStream) {
        final text = await response.transform(utf8.decoder).join();
        final thinking = _extractThinking(config.protocol, text);
        if (thinking != null && thinking.isNotEmpty) onThinking?.call(thinking);
        final content = _extractText(config.protocol, text);
        if (content.isNotEmpty) onContent?.call(content);
        return content;
      }

      final contentBuf = StringBuffer();
      var buffer = '';
      var receivedThinking = false;
      var finishedByLength = false;
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        // 保留最后不完整的一行
        buffer = lines.removeLast();
        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          if (line.startsWith('event:')) continue;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          final dynamic decoded;
          try {
            decoded = jsonDecode(data);
          } catch (_) {
            continue;
          }
          if (decoded is! Map) continue;
          final thinkingDelta = _extractStreamThinking(config.protocol, decoded);
          if (thinkingDelta != null && thinkingDelta.isNotEmpty) {
            receivedThinking = true;
            onThinking?.call(thinkingDelta);
          }
          final contentDelta = _extractStreamContent(config.protocol, decoded);
          if (contentDelta != null && contentDelta.isNotEmpty) {
            contentBuf.write(contentDelta);
            onContent?.call(contentDelta);
          }
          final finish = decoded['finish_reason'] ?? decoded['stop_reason'];
          if (finish is String && finish == 'length') finishedByLength = true;
        }
      }
      // tail
      final tail = buffer.trim();
      if (tail.startsWith('data:')) {
        final data = tail.substring(5).trim();
        if (data.isNotEmpty && data != '[DONE]') {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map) {
              final thinkingDelta = _extractStreamThinking(config.protocol, decoded);
              if (thinkingDelta != null && thinkingDelta.isNotEmpty) {
                receivedThinking = true;
                onThinking?.call(thinkingDelta);
              }
              final contentDelta = _extractStreamContent(config.protocol, decoded);
              if (contentDelta != null && contentDelta.isNotEmpty) {
                contentBuf.write(contentDelta);
                onContent?.call(contentDelta);
              }
              final finish = decoded['finish_reason'] ?? decoded['stop_reason'];
              if (finish is String && finish == 'length') finishedByLength = true;
            }
          } catch (_) {}
        }
      }
      final finalContent = contentBuf.toString().trim();
      if (finalContent.isEmpty) {
        if (finishedByLength) {
          throw const AiRequestException('响应被截断：输出达到长度上限，正文为空。请重试或减少本轮输入。');
        }
        if (receivedThinking) {
          throw const AiRequestException('模型只输出了思考、没有生成正文。可能是思考过长占满了输出上限，请重试。');
        }
        throw const AiRequestException('响应缺少文本内容。');
      }
      return finalContent;
    } on AiRequestException {
      rethrow;
    } on TimeoutException {
      throw const AiRequestException('请求超时，请检查网络后重试。');
    } on SocketException catch (error) {
      throw _ConnectionException(error, payloadBytes: payloadBytes);
    } on HttpException catch (error) {
      throw _ConnectionException(error, payloadBytes: payloadBytes);
    } on HandshakeException catch (error) {
      throw _ConnectionException(error, payloadBytes: payloadBytes);
    } catch (error) {
      throw AiRequestException('请求失败：$error');
    } finally {
      http.close(force: true);
    }
  }

  /// 流式请求在连接层失败后的回退：改发一次性（非流式）请求重试。
  ///
  /// 部分服务端不认 `stream: true` 会在连接阶段直接断开；回退后分析仍可用，
  /// 思考内容改为响应返回后一次性回调。
  Future<String> _fallbackPlain({
    required AiConfig config,
    required String system,
    required String user,
    required List<MessageImage> images,
    int maxTokens = 4096,
    void Function(String deltaThinking)? onThinking,
    void Function(String deltaContent)? onContent,
    int payloadBytes = 0,
  }) async {
    try {
      final text = await chat(
        config: config,
        system: system,
        user: user,
        images: images,
        maxTokens: maxTokens,
      );
      final thinking = _extractThinking(config.protocol, text);
      if (thinking != null && thinking.isNotEmpty) onThinking?.call(thinking);
      if (text.isNotEmpty) onContent?.call(text);
      return text;
    } on AiRequestException catch (error) {
      throw AiRequestException('${error.message}（已自动重试普通请求，仍失败）');
    } catch (error) {
      throw AiRequestException(
          '${_connectionError(error, payloadBytes: payloadBytes)}（已自动重试普通请求，仍失败）');
    }
  }

  /// 把连接层异常转成用户可读的错误信息，附带底层原因便于排查。
  ///
  /// [payloadBytes] 非 0 时附带请求体大小：若失败由请求体过大导致，
  /// 可通过这个数值精确判断服务端限制。
  String _connectionError(Object error, {int payloadBytes = 0}) {
    final rawDetail = switch (error) {
      SocketException(:final message) => message,
      HttpException(:final message) => message,
      HandshakeException(:final message) => message,
      _ => error.toString(),
    };
    final detail = rawDetail.trim().isEmpty ? '未知连接错误' : rawDetail;
    final payloadHint = payloadBytes > 0
        ? '，请求体约 ${(payloadBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '';
    // 尺寸提示只在真正发起了 body 后才可信；0.0MB 多半是连接层(TCP/TLS/DNS)
    // 就失败了，需要把底层异常完整透出便于定位（证书 / 网关 / 地址）。
    return '无法连接服务器，请检查网络或接口地址。\n底层原因：$detail$payloadHint';
  }

  /// 测试连接：发一条最小请求，验证 Key / 地址 / 模型可用。
  Future<String> ping(AiConfig config) async {
    return chat(
      config: config,
      system: '你是一个连接测试助手。请只回复「连接成功」四个字，不要其他内容。',
      user: 'ping',
    );
  }

  /// 组装请求：按协议返回地址、请求头与请求体。
  Future<({Uri uri, Map<String, String> headers, Map<String, dynamic> body})>
      _buildRequest(
    AiConfig config,
    String system,
    String user,
    List<MessageImage> images, {
    bool stream = false,
    int maxTokens = 4096,
  }) async {
    final base = config.effectiveBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final apiKey = config.apiKey.trim();
    final imageContent = await _imageContent(config.protocol, images);

    if (config.protocol == AiProtocol.anthropic) {
      return (
        uri: Uri.parse('$base/v1/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          'model': config.effectiveModel,
          'max_tokens': maxTokens,
          'temperature': 0.4,
          'system': system,
          'messages': [
            {
              'role': 'user',
              'content': [
                ...imageContent,
                {'type': 'text', 'text': user},
              ],
            },
          ],
          if (stream) 'stream': true,
        },
      );
    }

    return (
      uri: Uri.parse('$base/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
      },
      body: {
        'model': config.effectiveModel,
        'max_tokens': maxTokens,
        'temperature': 0.4,
        if (stream) 'stream': true,
        'messages': [
          {'role': 'system', 'content': system},
          {
            'role': 'user',
            'content': [
              ...imageContent,
              {'type': 'text', 'text': user},
            ],
          },
        ],
      },
    );
  }

  /// 把本地图片读成 base64，按协议转成 content 块（无图时返回空列表）。
  ///
  /// 文件已被移动/删除、读取失败、或 Base64 超过官方 50 MB 单张限制时，
  /// 跳过该张，不阻塞整轮分析。
  Future<List<Map<String, dynamic>>> _imageContent(
    AiProtocol protocol,
    List<MessageImage> images,
  ) async {
    final blocks = <Map<String, dynamic>>[];
    for (final image in images) {
      final file = File(image.path);
      if (!await file.exists()) continue;
      // 官方限制针对单张 Base64 字符串；先按字节数预估过滤。
      final base64Size = (await file.length() + 2) ~/ 3 * 4;
      if (base64Size > _maxBase64ImageBytes) continue;
      final List<int> bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        continue;
      }
      final data = base64Encode(bytes);
      final mediaType = _mediaType(image.path);

      if (protocol == AiProtocol.anthropic) {
        blocks.add({
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': data},
        });
      } else {
        blocks.add({
          'type': 'image_url',
          'image_url': {'url': 'data:$mediaType;base64,$data'},
        });
      }
    }
    return blocks;
  }

  String _mediaType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _extractText(AiProtocol protocol, String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const AiRequestException('响应不是有效 JSON，可能被截断。');
    }
    if (decoded is! Map) {
      throw const AiRequestException('响应结构异常。');
    }

    // 从「单个 content 值」里取出正文：可能是字符串，也可能是数组（多模态
    // 模型常见 `[{type: text, text: ...}]`），也可能包含其它块类型。
    String? textFrom(Object? content) {
      if (content is String) {
        final t = content.trim();
        return t.isEmpty ? null : t;
      }
      if (content is List) {
        final parts = <String>[];
        for (final block in content) {
          if (block is! Map) continue;
          final type = block['type'];
          if (type == 'text' && block['text'] is String) {
            parts.add(block['text'] as String);
          } else if (type == 'output_text' && block['text'] is String) {
            // Anthropic Messages 的 text 块使用 type=text，这里兼容
            // 个别服务端用 output_text。/ thinking_delta 已单独处理。
            parts.add(block['text'] as String);
          } else if (type == 'text' && block['content'] is String) {
            parts.add(block['content'] as String);
          }
        }
        final joined = parts.join('\n').trim();
        return joined.isEmpty ? null : joined;
      }
      return null;
    }

    Object? messageContent;
    if (protocol == AiProtocol.openai) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first is Map ? choices.first['message'] : null;
        messageContent = message is Map ? message['content'] : null;
      }
    } else {
      messageContent = decoded['content'];
    }

    final text = textFrom(messageContent);
    if (text != null) return text;

    // 正文确实为空：给出可定位的提示，而不是笼统的「缺少文本」。
    // 若响应里存在思考内容（reasoning/思考块），说明是「只思考、未产出
    // 正文」，常见于 max_tokens 被思考挤满，提示用户重试或调大上限。
    final hasReasoning = _containsReasoning(decoded);
    if (hasReasoning) {
      throw const AiRequestException('模型只输出了思考、没有生成正文。可能是思考过长占满了输出上限，请重试。');
    }
    throw const AiRequestException('响应缺少文本内容，请重试。');
  }

  /// 判断解码后的响应体里是否含思考内容（reasoning / thinking 等）。
  bool _containsReasoning(Object? node) {
    if (node is String) {
      return node.contains('reasoning');
    }
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key == 'reasoning' ||
            entry.key == 'thinking' ||
            entry.key == 'reasoning_content' ||
            entry.key == 'thought') {
          if (entry.value is String && (entry.value as String).isNotEmpty) {
            return true;
          }
        }
        if (entry.key == 'type' && entry.value == 'thinking') return true;
        if (_containsReasoning(entry.value)) return true;
      }
    }
    if (node is List) {
      for (final item in node) {
        if (_containsReasoning(item)) return true;
      }
    }
    return false;
  }

  String? _extractThinking(AiProtocol protocol, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _extractStreamThinking(protocol, decoded);
    } catch (_) {
      return null;
    }
  }

  String? _extractStreamThinking(AiProtocol protocol, Map<dynamic, dynamic> decoded) {
    if (protocol == AiProtocol.openai) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final delta = first['delta'] is Map ? first['delta'] as Map : null;
          final message = first['message'] is Map ? first['message'] as Map : null;
          for (final src in [delta, message]) {
            if (src == null) continue;
            for (final k in ['reasoning_content', 'reasoning', 'thinking', 'thought']) {
              final v = src[k];
              if (v is String && v.isNotEmpty) return v;
            }
          }
          final deltaContent = delta?['content'];
          if (deltaContent is List) {
            for (final b in deltaContent) {
              if (b is Map && b['type'] == 'thinking' && b['thinking'] is String) {
                return b['thinking'] as String;
              }
            }
          }
        }
      }
      for (final k in ['reasoning_content', 'reasoning', 'thinking', 'thought']) {
        final v = decoded[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }
    final type = decoded['type'];
    if (type == 'content_block_delta') {
      final delta = decoded['delta'];
      if (delta is Map && delta['type'] == 'thinking_delta' && delta['thinking'] is String) {
        return delta['thinking'] as String;
      }
    }
    if (type == 'content_block_start') {
      final block = decoded['content_block'];
      if (block is Map && block['type'] == 'thinking' && block['thinking'] is String) {
        return block['thinking'] as String;
      }
    }
    for (final k in ['thinking', 'reasoning', 'reasoning_content']) {
      final v = decoded[k];
      if (v is String && v.isNotEmpty) return v;
    }
    final content = decoded['content'];
    if (content is List) {
      for (final b in content) {
        if (b is Map && b['type'] == 'thinking' && b['thinking'] is String) {
          return b['thinking'] as String;
        }
      }
    }
    return null;
  }

  String? _extractStreamContent(AiProtocol protocol, Map<dynamic, dynamic> decoded) {
    if (protocol == AiProtocol.openai) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final delta = first['delta'] is Map ? first['delta'] as Map : null;
          if (delta != null) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) return content;
            final fromList = _textFromContentBlocks(content);
            if (fromList != null) return fromList;
          }
          final message = first['message'] is Map ? first['message'] as Map : null;
          if (message != null) {
            final content = message['content'];
            if (content is String && content.isNotEmpty) return content;
            final fromList = _textFromContentBlocks(content);
            if (fromList != null) return fromList;
          }
        }
      }
      final content = decoded['content'];
      if (content is String && content.isNotEmpty) return content;
      final fromList = _textFromContentBlocks(content);
      if (fromList != null) return fromList;
      return null;
    }
    final type = decoded['type'];
    if (type == 'content_block_delta') {
      final delta = decoded['delta'];
      if (delta is Map && delta['type'] == 'text_delta' && delta['text'] is String) {
        return delta['text'] as String;
      }
    }
    final content = decoded['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map && first['text'] is String) return first['text'] as String;
    }
    final text = decoded['text'];
    if (text is String && text.isNotEmpty) return text;
    return null;
  }

  /// 从多模态 content 数组里取文本（`[{type: text, text: ...}]` /
  /// `output_text` 块），拼接后返回；取不到返回 null。
  String? _textFromContentBlocks(Object? content) {
    if (content is! List) return null;
    final parts = <String>[];
    for (final block in content) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type != null && type != 'text' && type != 'output_text') continue;
      final text = block['text'] ?? block['content'];
      if (text is String && text.isNotEmpty) parts.add(text);
    }
    if (parts.isEmpty) return null;
    final joined = parts.join('\n').trim();
    return joined.isEmpty ? null : joined;
  }

  /// 从错误响应体里截取一段可读的错误信息。
  String _errorSnippet(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '空响应';
    if (trimmed.length > 160) return '${trimmed.substring(0, 160)}…';
    return trimmed;
  }
}

/// AI 请求异常：message 面向用户可直接展示。
class AiRequestException implements Exception {
  final String message;
  const AiRequestException(this.message);

  @override
  String toString() => message;
}

/// 连接层失败（SocketException / HttpException / HandshakeException）的内部标记，
/// 由 chatStream 捕获后触发非流式回退，不直接暴露给 UI。
class _ConnectionException implements Exception {
  final Object cause;
  final int payloadBytes;
  const _ConnectionException(this.cause, {this.payloadBytes = 0});

  @override
  String toString() => cause.toString();
}

/// 服务端对流式请求返回非 2xx 的内部标记（如不支持 `stream` 参数返回 400），
/// 由 chatStream 捕获后触发非流式回退。
class _ServerRejectException implements Exception {
  final int statusCode;
  final String detail;
  final int payloadBytes;
  const _ServerRejectException(this.statusCode, this.detail,
      {this.payloadBytes = 0});

  @override
  String toString() => '接口返回 $statusCode：$detail';
}
