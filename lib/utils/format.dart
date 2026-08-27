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
