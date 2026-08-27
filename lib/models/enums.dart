/// 全局枚举定义（对应产品文档第 3、4、6、8 章）
library;

/// 导入来源（3.4 导入：截图 / 复制）
enum ImportSource { screenshot, paste }

/// 说话人（内部标识：区分两个人；界面统一显示为「我 / TA」，不用 A/B 或任何性别标签）
enum Party { a, b }

/// 消息类型
enum MessageType { text, image, sticker, voice }

/// AI 通道（6.1 双通道设计）
enum AiChannel { byok, promptExport }

/// AI 厂商
enum AiProvider { claude, openai, deepseek, gemini, xiaomi }

/// 厂商兼容协议（小米 MiMo 同时支持两种格式）
enum AiProtocol { openai, anthropic }

/// 分析视角（3.2 三模式：争爱 / 争对错 / 争输赢）
enum BattleView { love, right, win }

/// 长期记忆条目类型（4.2 九板块：画像 / 关系 / 成长 / 触发点 / 沟通库 /
/// 里程碑 / 雷区 / 未解决问题 / 承诺跟踪）。
enum MemoryKind {
  profile,
  relationship,
  growth,
  trigger,
  commLib,
  milestone,
  minefield,
  openIssue,
  promise,
}
