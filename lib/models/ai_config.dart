import 'enums.dart';

/// BYOK 接入配置（产品文档 6.1 通道 B、3.1.2 设置页「配置 API」）。
///
/// 用户在设置页填写自己的厂商、API Key、模型名与自定义端点；保存到本地
/// 仓库，仅发起分析 / 记忆生成时由本机直连对应厂商。
///
/// 本期只支持小米 MiMo（mimo-v2.5-pro），同一次配置可选择 OpenAI 兼容或
/// Anthropic 兼容协议（决定接口地址与请求格式），其余厂商为后续扩展。
class AiConfig {
  final AiProvider provider;
  final AiProtocol protocol;
  final String apiKey;
  final String model;
  final String baseUrl;
  final bool enabled;

  const AiConfig({
    this.provider = AiProvider.xiaomi,
    this.protocol = AiProtocol.openai,
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
    this.enabled = false,
  });

  /// 是否已填写可用的 API Key。
  bool get isConfigured => apiKey.trim().isNotEmpty;

  /// 实际使用的模型名：用户填写优先，留空用该厂商默认。
  String get effectiveModel {
    final value = model.trim();
    return value.isNotEmpty ? value : defaultModel;
  }

  String get defaultModel {
    switch (provider) {
      case AiProvider.xiaomi:
        // mimo-v2.5 是多模态模型（可读图）；v2.5-pro 是纯文本模型。
        return 'mimo-v2.5';
      case AiProvider.claude:
        return 'claude-sonnet-4-5';
      case AiProvider.openai:
        return 'gpt-4o';
      case AiProvider.deepseek:
        return 'deepseek-chat';
      case AiProvider.gemini:
        return 'gemini-2.5-flash';
    }
  }

  /// 实际使用的接口地址：用户自定义端点优先，留空用该厂商 / 协议的默认地址。
  String get effectiveBaseUrl {
    final value = baseUrl.trim();
    return value.isNotEmpty ? value : defaultBaseUrl;
  }

  String get defaultBaseUrl {
    switch (provider) {
      case AiProvider.xiaomi:
        // 小米 MiMo 双协议地址（OpenAI 兼容 / Anthropic 兼容）。
        return protocol == AiProtocol.openai
            ? 'https://api.xiaomimimo.com/v1'
            : 'https://api.xiaomimimo.com/anthropic';
      case AiProvider.claude:
        return 'https://api.anthropic.com';
      case AiProvider.openai:
        return 'https://api.openai.com';
      case AiProvider.deepseek:
        return 'https://api.deepseek.com';
      case AiProvider.gemini:
        return 'https://generativelanguage.googleapis.com';
    }
  }

  AiConfig copyWith({
    AiProvider? provider,
    AiProtocol? protocol,
    String? apiKey,
    String? model,
    String? baseUrl,
    bool? enabled,
  }) {
    return AiConfig(
      provider: provider ?? this.provider,
      protocol: protocol ?? this.protocol,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
    );
  }
}
