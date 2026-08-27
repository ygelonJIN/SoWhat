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
  }) async {
    final http = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await _buildRequest(config, system, user, images);
      final httpRequest = await http.postUrl(request.uri);
      httpRequest.headers.contentType = ContentType.json;
      request.headers.forEach(httpRequest.headers.set);
      httpRequest.add(utf8.encode(jsonEncode(request.body)));

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
    } on SocketException {
      throw const AiRequestException('无法连接服务器，请检查网络或接口地址。');
    } catch (error) {
      throw AiRequestException('请求失败：$error');
    } finally {
      http.close(force: true);
    }
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
    List<MessageImage> images,
  ) async {
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
          'max_tokens': 4096,
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
        'max_tokens': 4096,
        'temperature': 0.4,
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
  Future<List<Map<String, dynamic>>> _imageContent(
    AiProtocol protocol,
    List<MessageImage> images,
  ) async {
    final blocks = <Map<String, dynamic>>[];
    for (final image in images) {
      final file = File(image.path);
      if (!await file.exists()) {
        throw AiRequestException('图片文件不存在，可能已被移动或删除：${image.path}');
      }
      final bytes = await file.readAsBytes();
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

    if (protocol == AiProtocol.openai) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first is Map ? choices.first['message'] : null;
        final content = message is Map ? message['content'] : null;
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } else {
      final content = decoded['content'];
      if (content is List && content.isNotEmpty) {
        final first = content.first;
        if (first is Map && first['text'] is String) {
          return (first['text'] as String).trim();
        }
      }
    }
    throw const AiRequestException('响应缺少文本内容。');
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
