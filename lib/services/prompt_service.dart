import '../models/models.dart';

/// 生成三模式系统提示词与导出包（产品文档第 6 章）。
///
/// 三个模式共用同一份「公共铁律 + 对话内容 + 长期记忆」，只换分析视角指令。
class PromptService {
  const PromptService();

  /// 公共铁律（三个模式共用）。
  String commonIronLaw({
    required MemoryProfile memory,
    required String conversation,
    String? background,
  }) {
    final memoryBlock = _memoryBlock(memory);
    final backgroundBlock = background == null || background.trim().isEmpty
        ? ''
        : '\n\n背景补充（用户提供）：<background>\n$background\n</background>';
    return '''
你是一位长期陪伴一对情侣的情感沟通分析师。你长期认识这两个人——记得他们的
性格、表达方式、在乎什么、害怕什么，以及一路走来的矛盾与成长。

铁律：
1. 不使用「男方/女方」或任何性别、角色标签，一律用「双方」「你」「TA」。
2. 只基于对话内容与双方补充的背景分析，不编造对话里不存在的信息。
3. 每个结论尽量对应到具体对话；无法对应到证据的判断，标注为「推测」。
4. 不站队、不迎合任何一方：指出双方的合理之处，也指出双方的问题。
5. 语气克制、有同理心，不煽动、不贴标签、不人身攻击。
6. 本轮分析结束后，把值得记住的新观察更新进长期记忆（双方画像 / 关系状态 / 成长轨迹）。

长期记忆（关于这对情侣）：<memory>
$memoryBlock
</memory>$backgroundBlock
本轮对话：<chat content>
$conversation
''';
  }

  /// 模式指令：争对错（7 维）。
  String rightModeInstruction() {
    return '''
按「争对错」视角分析本轮对话，从以下 7 个维度逐条展开，每条给出「结论 + 证据引用 + 推测标注」：
1. 事实陈述 —— 事实是否准确完整？有无夸大、删减、选择性记忆、张冠李戴？
2. 逻辑推理 —— 论证是否成立？有无以偏概全（「你总是/你从来」）、偷换概念、非黑即白、滑坡谬误？
3. 归因责任 —— 责任被归于谁？是单方面指责、推卸，还是能承认自己那部分责任？
4. 沟通方式 —— 语气是否攻击性？有无人身攻击、贴标签（「你就是这种人」）、打断、翻旧账？
5. 视角立场 —— 是否只站在自己视角？能否看到并承认对方的立场和事实？
6. 时间取向 —— 着眼当下问题，还是纠缠过去、翻旧账、或用未来做要挟？
7. 解决方案 —— 是否提出可执行的解决方式？还是只列罪状、只要求对方改变？

结尾给「战况小结」：天平偏向谁（谁更占理）、双方各自最需要调整的一点。
''';
  }

  /// 模式指令：争爱（8 维）。
  String loveModeInstruction() {
    return '''
按「争爱」视角分析本轮对话，从以下 8 个维度逐条展开，每条给出「结论 + 证据引用 + 推测标注」：
1. 动机初衷 —— 开战的出发点是爱/关心/在乎，还是控制/权力/发泄？
2. 核心需求 —— 情绪背后的真实需求是什么？被看见、被尊重、被重视、被需要、安全感、陪伴、理解？
3. 情绪表达 —— 是否真实、真诚地表达感受？还是压抑、攻击、冷暴力、装没事？
4. 共情能力 —— 能否站到对方位置理解 TA？能否接住对方的情绪而不是推开？
5. 关系投资 —— 争吵中有没有爱的动作：主动破冰、道歉、哄、妥协、示弱？
6. 依恋安全感 —— 是否触发了「不被爱/被抛弃」的恐惧？双方的依恋模式（焦虑型/回避型/安全型）？
7. 情感账户 —— 平时积累的信任和爱有多少余额？这次争吵是在透支还是在补充？
8. 修复意愿 —— 愿不愿意和好？愿不愿意放下对错来保住关系？

结尾给「战况小结」：共育之树的状态（抽芽 / 活着 / 枯萎）、双方各做一个什么爱的动作最能修复。
''';
  }

  /// 模式指令：争输赢（8 维）。
  String winModeInstruction() {
    return '''
按「争输赢」视角分析本轮对话，从以下 8 个维度逐条展开，每条给出「结论 + 证据引用 + 推测标注」：
1. 气势掌控 —— 谁主导节奏和氛围？谁被压制、被牵着走？
2. 攻击效力 —— 谁的论点、语言更有杀伤力？谁能更准地戳中对方要害？
3. 面子自尊 —— 谁更在乎输赢和面子？谁更难先低头、先认错？
4. 主动权 —— 谁掌握主动权（发起、升级、终止、要不要冷战）？
5. 筹码资源 —— 谁手里筹码更多：翻旧账、把柄、冷战、分手威胁、让别人站队？
6. 耐力持久 —— 谁更耗得起冷战？谁先破防、先崩溃、先撑不住？
7. 代价收益 —— 表面赢了的人实际付出了什么？输的人又得到了什么？
8. 战局结果 —— 最终真的分出输赢了吗？还是双输、双赢、或者根本没有胜者？

结尾给「战况小结」：比分与血条状态、以及真正的代价是什么。
''';
  }

  /// 生成一份完整提示词（公共铁律 + 指定模式指令）。
  String buildSystemPrompt({
    required BattleView view,
    required MemoryProfile memory,
    required String conversation,
    String? background,
  }) {
    final law = commonIronLaw(
      memory: memory,
      conversation: conversation,
      background: background,
    );
    final mode = switch (view) {
      BattleView.right => rightModeInstruction(),
      BattleView.love => loveModeInstruction(),
      BattleView.win => winModeInstruction(),
    };
    return '$law\n\n$mode';
  }

  /// 导出分析包（V1 通道 A）：一份可直接复制到免费 AI 的完整提示词。
  PromptPackage buildExportPackage({
    required BattleView view,
    required MemoryProfile memory,
    required List<Message> messages,
    String? background,
  }) {
    final conversation = _formatConversation(messages);
    final prompt = buildSystemPrompt(
      view: view,
      memory: memory,
      conversation: conversation,
      background: background,
    );
    return PromptPackage(
      title: '爱·对·赢 · ${_viewLabel(view)}分析包',
      view: view,
      prompt: prompt,
      footer: '—— 由「爱·对·赢」生成，结果可直接粘贴回 App 存档。',
    );
  }

  /// 把消息列表转成给 AI 看的对话文本（不做解析器，直接呈现）。
  String formatConversation(List<Message> messages) =>
      _formatConversation(messages);

  String _formatConversation(List<Message> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer.writeln('[${message.partyLabel}] ${message.content}');
    }
    return buffer.toString();
  }

  String _memoryBlock(MemoryProfile memory) {
    final parts = <String>[];
    if (memory.userSummary?.isNotEmpty ?? false) {
      parts.add('你（用户）的画像：${memory.userSummary}');
    }
    if (memory.partnerSummary?.isNotEmpty ?? false) {
      parts.add('TA 的画像：${memory.partnerSummary}');
    }
    if (memory.relationshipSummary?.isNotEmpty ?? false) {
      parts.add('关系状态：${memory.relationshipSummary}');
    }
    for (final entry in memory.entries.where((e) => !e.isDeleted)) {
      final source = entry.source == null ? '' : '（出处：${entry.source}）';
      parts.add('${_kindLabel(entry.kind)}：${entry.summary}$source');
    }
    if (parts.isEmpty) return '（尚无长期记忆）';
    return parts.join('\n');
  }

  String _kindLabel(MemoryKind kind) {
    switch (kind) {
      case MemoryKind.profile:
        return '双方画像';
      case MemoryKind.relationship:
        return '关系状态';
      case MemoryKind.growth:
        return '成长轨迹';
    }
  }

  String _viewLabel(BattleView view) {
    switch (view) {
      case BattleView.love:
        return '争爱';
      case BattleView.right:
        return '争对错';
      case BattleView.win:
        return '争输赢';
    }
  }
}

/// 一份可复制/分享的完整提示词包。
class PromptPackage {
  final String title;
  final BattleView view;
  final String prompt;
  final String footer;

  const PromptPackage({
    required this.title,
    required this.view,
    required this.prompt,
    required this.footer,
  });

  /// 复制到剪贴板用的完整文本。
  String get fullText => '$title\n\n$prompt\n\n$footer';
}
