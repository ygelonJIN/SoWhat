/// 日期 / 时间格式化工具（聊天记录以日期命名、新建对话标题等共用）。
library;

/// 2026-08-27
String formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// 21:05
String formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// 2026-08-27 21:05（新建对话的默认标题）
String dateTimeLabel(DateTime dt) => '${formatDate(dt)} ${formatTime(dt)}';

/// 去掉 AI 偶尔给记忆文本加上的 markdown / 格式残留符号
/// （**粗体** / *斜体* / _下划线_ / ~删除线~ / `代码` / # 标题 / 列表符 /
/// 成对 `$…$` 行内数学），以及杂散的 `$`、`*` 等。
///
/// 界面里记忆条目 / 概况都是纯文本展示。
/// - 金额符号保留：`$` 与数字相邻（`$100`、`100$`）视为正文内容；
/// - 全角 `＄`（AI 编号伪标点）与孤立的 `$`（前后都不是数字）按残留删除；
/// - 行首形如 `1. $1：`、`* ＄1：`、`*$1：` 的「编号 + $N + 冒号」伪标签整体删掉。
String cleanMemoryText(String text) {
  var s = text;
  // 全角 ＄ / ￥（格式残留，非货币符号）删除
  s = s.replaceAll(RegExp(r'[＄￥]'), '');
  // 「编号头 + $N：正文」两行合并：AI 常输出独占一行的「1. $1：」编号头，
  // 下一行才是「$1：正文」。把编号头保留下来拼到正文前，变成「1. 正文」，
  // 避免悬空编号行，也保留列表顺序感。
  s = s.replaceAllMapped(
    RegExp(
      r'^[ \t]*([0-9]+[.、)）]?)[ \t]*\$?[ \t]*[0-9]*[ \t]*[：:][ \t]*\r?\n'
      r'[ \t]*\$[0-9]+[ \t]*[：:][ \t]*',
      multiLine: true,
    ),
    (m) => '${m.group(1)} ',
  );
  // 行首的「(编号/项目符) + $N + 冒号」伪标签，如：1. $1： / * 1： / *$1：
  s = s.replaceAll(
    RegExp(
      r'^[ \t]*(?:[*\-+]|(?:[0-9]+[.、)）]?))[ \t]*\$?[ \t]*[0-9]+[ \t]*[：:][ \t]*',
      multiLine: true,
    ),
    '',
  );
  // 裸的「$N：」行首伪标签（AI 常直接以 $1： 开头、没有前置编号）
  s = s.replaceAll(
    RegExp(r'^[ \t]*\$[0-9]+[ \t]*[：:][ \t]*', multiLine: true),
    '',
  );
  // 独立成行的小节标记：编号 + 我/TA/双方（可带「（即…）」注解），
  // 如「2 我」「2 我（即 green 方/一方）」——概况正文里的 AI 残留。
  s = s.replaceAll(
    RegExp(
      r'^[ \t]*[0-9]+[ \t]+(?:我|TA|双方)(?:[ \t]*[（(]即[^）)]*[）)])?[ \t]*$',
      multiLine: true,
    ),
    '',
  );
  // 独立成行的「（即 …）」注解行（如「（即 green 方/一方）」）
  s = s.replaceAll(
    RegExp(r'^[ \t]*[（(]即[^）)]*[）)]$', multiLine: true),
    '',
  );
  // 行首块结构：Markdown 标题 #、引用 >、无序列表 * - +（逐行匹配）
  s = s.replaceAll(
    RegExp(r'^[ \t]*(#{1,6}[ \t]+|>[ \t]*|[*\-+][ \t]+)', multiLine: true),
    '',
  );
  // 中文项目符号 •
  s = s.replaceAll(RegExp(r'^[ \t]*\u2022', multiLine: true), '');
  // 成对强调：先 ** 后单 *
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'(?<!\*)\*([^*\n]+)\*(?!\*)'), r'$1');
  s = s.replaceAll(RegExp(r'_([^\s_][^_\n]*?[^\s_])_'), r'$1');
  s = s.replaceAll(RegExp(r'~([^~\n]+)~'), r'$1');
  s = s.replaceAll('`', '');
  // 成对 $…$ / $$…$$（行内数学 / LaTeX 定界符）
  s = s.replaceAll(RegExp(r'\$\$([^$]+)\$\$'), r'$1');
  s = s.replaceAll(RegExp(r'(?<!\$)\$([^$\n]+)\$(?!\$)'), r'$1');
  // 孤立的美金符号：前后都不挨数字才删（$100 / 100$ 保留）
  s = s.replaceAll(RegExp(r'(?<!\$)(?<![0-9])\$(?!\$)(?![0-9])'), '');
  // 收敛多余空白与空行
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r' *\n *'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// 记忆条目开头的「仍在 / 变化 / 新观察」变化标签（记忆生成契约里要求用这
/// 几种前缀开头），抽出来单独渲染成小标签；不是这几种前缀时原样返回文本。
({String? label, String text}) splitMemoryEntryLabel(String summary) {
  final text = summary.trim();
  final match = RegExp(
    r'^(仍在|变化|新观察)[：:\s,，]?[\s]*(.*)$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return (label: null, text: text);
  final rest = (match.group(2) ?? '').trim();
  if (rest.isEmpty) return (label: null, text: text);
  return (label: match.group(1), text: rest);
}
