import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/conversation_transfer_service.dart';
import '../../providers/app_providers.dart';
import '../../screens/ai_config_screen.dart';
import '../../theme/mode_theme.dart';
import '../../utils/format.dart';

/// 各模式的危险色（删除、危险操作）。
Color _modeDanger(ModeTheme mode) {
  switch (mode.view) {
    case BattleView.love:
      return const Color(0xFFB5543F); // 为爱：暖陶红
    case BattleView.right:
      return const Color(0xFFC4645A); // 论对错：暗金红
    case BattleView.win:
      return const Color(0xFFE5484D); // 比输赢：纯红
  }
}

/// 卡片表面装饰（底色 / 圆角 / 边框 / 阴影），用于菜单、弹窗等浮层。
BoxDecoration _cardSurface(ModeTheme mode) {
  return BoxDecoration(
    color: mode.cardBackground,
    borderRadius: mode.cardRadius,
    border: Border.all(color: mode.cardBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (mode.cardShadowAlpha + 0.08).clamp(0, 1),
        ),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

/// 菜单项分割线（跟随模式的卡片边框色）。
Widget _menuDivider(ModeTheme mode) {
  return Divider(
    height: 1,
    thickness: 1,
    color: mode.cardBorder.withValues(alpha: 0.55),
    indent: 14,
    endIndent: 14,
  );
}

/// 设置页（产品文档 3.1「设置」入口展开后的左侧 3/4 面板）。
///
/// 结构自上而下：搜索框 → 配置 API → 新建对话 → 聊天记录列表。
/// 聊天记录一行一个、以日期命名（重命名后显示自定义名称）；点击切换对话，
/// **长按**弹出主题样式的操作菜单（置顶 / 重命名 / 删除）。
///
/// 视觉完全由 `ModeTheme` 驱动：面板底色用 `surface`，搜索框 / 列表行用
/// `cardBackground`，保证三套模式（共育之树 / 法庭之秤 / 胜负之局）下文字
/// 均可读、风格各自独立。
class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({
    super.key,
    required this.mode,
    required this.onClose,
    required this.onNewConversation,
    required this.onSelectConversation,
  });

  final ModeTheme mode;

  /// 收起设置面板（返回聊天页）。
  final VoidCallback onClose;

  /// 新建一段对话并跳转过去。
  final VoidCallback onNewConversation;

  /// 点击某条聊天记录，切换到该对话。
  final ValueChanged<String> onSelectConversation;

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  /// 打开「配置 AI 接口」全屏页（保存由页面内完成）。
  void _openAiConfig() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AiConfigScreen(),
      ),
    );
  }

  /// 搜索命中范围：自定义名称 + 日期时间（重命名后仍可按原日期时间搜到）。
  static String _searchableText(Case caseItem) {
    final label = dateTimeLabel(caseItem.createdAt);
    return '${caseItem.title ?? ''} $label'.toLowerCase();
  }

  /// 置顶优先，其次按创建时间倒序。
  static int _compareCases(Case a, Case b) {
    final aPinned = a.pinnedAt;
    final bPinned = b.pinnedAt;
    if (aPinned != null && bPinned != null) return bPinned.compareTo(aPinned);
    if (aPinned != null) return -1;
    if (bPinned != null) return 1;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final cases = ref.watch(casesProvider).valueOrNull ?? const <Case>[];
    final currentId = ref.watch(selectedConversationIdProvider);
    final aiConfig =
        ref.watch(aiConfigProvider).valueOrNull ?? const AiConfig();

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? cases
        : cases.where((c) => _searchableText(c).contains(query)).toList();
    // 置顶专区：置顶的记录按置顶时间倒序，单独一组；其余按创建时间倒序。
    final pinned = filtered.where((c) => c.isPinned).toList()
      ..sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
    final others = filtered.where((c) => !c.isPinned).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Container(
      decoration: BoxDecoration(
        color: mode.surface,
        border: Border(
          right: BorderSide(color: mode.textMuted.withValues(alpha: 0.45)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      child: SafeArea(
        // 与聊天页一致的「全屏内容 + 浮层控制」：聊天记录全屏滚动，
        // 搜索框 / 新建按钮悬浮在顶部，底部有渐变遮罩。
        child: Stack(
          children: [
            Positioned.fill(
              child: pinned.isEmpty && others.isEmpty
                  ? _EmptyHistory(mode: mode, hasQuery: query.isNotEmpty)
                  : ListView(
                      // 顶部留白避开悬浮控件，底部留白避开渐变遮罩。
                      padding: const EdgeInsets.fromLTRB(16, 268, 16, 220),
                      children: [
                        if (pinned.isNotEmpty) ...[
                          _HistorySectionLabel(mode: mode, text: '置顶'),
                          const SizedBox(height: 8),
                          ...pinned.map(
                            (caseItem) => _ConversationRow(
                              mode: mode,
                              caseItem: caseItem,
                              isActive: caseItem.id == currentId,
                              onTap: () =>
                                  widget.onSelectConversation(caseItem.id),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _HistorySectionLabel(mode: mode, text: '聊天记录'),
                        const SizedBox(height: 8),
                        ...others.map(
                          (caseItem) => _ConversationRow(
                            mode: mode,
                            caseItem: caseItem,
                            isActive: caseItem.id == currentId,
                            onTap: () =>
                                widget.onSelectConversation(caseItem.id),
                          ),
                        ),
                      ],
                    ),
            ),
            // 顶部渐隐：聊天记录滚动到浮层控件下方时过渡淡出。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 268,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        mode.surface.withValues(alpha: 1),
                        mode.surface.withValues(alpha: 0.92),
                        mode.surface.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 底部渐变遮罩：滚动内容到底部时淡出。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        mode.surface.withValues(alpha: 1),
                        mode.surface.withValues(alpha: 0.85),
                        mode.surface.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 顶部浮层控件：标题 + 搜索框 + 配置 API + 新建对话。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsHeader(mode: mode),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: _SettingsSearchField(
                      mode: mode,
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      onClear: _clearSearch,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _SecondaryActionButton(
                      mode: mode,
                      icon: Icons.key_rounded,
                      label: '配置 API',
                      statusOn: aiConfig.isConfigured,
                      onTap: _openAiConfig,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _PrimaryActionButton(
                      mode: mode,
                      icon: Icons.add_rounded,
                      label: '新建对话',
                      onTap: widget.onNewConversation,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: _SecondaryActionButton(
                mode: mode,
                icon: Icons.photo_library_outlined,
                label: '资产管理',
                onTap: () => _showAssetManagementPlaceholder(context, mode),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssetManagementPlaceholder(BuildContext context, ModeTheme mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AssetManagementScreen(mode: mode),
      ),
    );
  }
}

/// 长按聊天记录弹出的操作菜单：跟随手指位置、卡片视觉跟随模式。
class _RowActionMenu extends StatelessWidget {
  const _RowActionMenu({
    required this.mode,
    required this.touch,
    required this.canUnpin,
  });

  final ModeTheme mode;

  /// 手指按下的全局坐标。
  final Offset touch;
  final bool canUnpin;

  static const _width = 192.0;
  static const _itemHeight = 46.0;

  static Future<String?> show(
    BuildContext context, {
    required ModeTheme mode,
    required Offset touch,
    required bool canUnpin,
  }) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          _RowActionMenu(mode: mode, touch: touch, canUnpin: canUnpin),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = 4 * _itemHeight;
    // 贴近手指弹出，右 / 下越界时自动收回来。
    final left = touch.dx + _width > size.width - 10
        ? size.width - _width - 10
        : touch.dx;
    final top = touch.dy + height > size.height - 10
        ? size.height - height - 10
        : touch.dy;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: mode.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: mode.cardRadius,
              side: BorderSide(color: mode.cardBorder, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 12,
            shadowColor: Colors.black.withValues(
              alpha: (mode.cardShadowAlpha + 0.08).clamp(0, 1),
            ),
            child: SizedBox(
              width: _width,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MenuAction(
                  mode: mode,
                  icon: canUnpin
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: canUnpin ? '取消置顶' : '置顶',
                  onTap: () => Navigator.of(context).pop('pin'),
                ),
                _menuDivider(mode),
                _MenuAction(
                  mode: mode,
                  icon: Icons.edit_outlined,
                  label: '重命名',
                  onTap: () => Navigator.of(context).pop('rename'),
                ),
                _menuDivider(mode),
                _MenuAction(
                  mode: mode,
                  icon: Icons.ios_share_rounded,
                  label: '分享',
                  onTap: () => Navigator.of(context).pop('share'),
                ),
                _menuDivider(mode),
                _MenuAction(
                  mode: mode,
                  icon: Icons.delete_outline_rounded,
                  label: '删除',
                  accent: _modeDanger(mode),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 菜单单项：主色图标 + 小字号文字，危险项用模式危险色。
class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.mode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 非空时整体使用该颜色（如危险红）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? mode.primary;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _RowActionMenu._itemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: accent ?? mode.cardBody,
                  fontSize: 13.5,
                  fontWeight: mode.strongWeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 删除确认弹窗：主题化卡片，危险色图标 + 危险色主按钮；
/// 显著提示「连同记忆一起删除」勾选项（记忆不可单独清除，源记录删除时二选一）。
class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({required this.mode});

  final ModeTheme mode;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  bool _withMemory = false;

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final danger = _modeDanger(mode);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: _cardSurface(mode),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              mode: mode,
              icon: Icons.delete_outline_rounded,
              title: '删除这段对话？',
              accent: danger,
            ),
            const SizedBox(height: 10),
            Text(
              '聊天记录与截图将一并删除，此操作无法恢复。',
              style: TextStyle(color: mode.cardMuted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            // 显著提示块：危险色底 + 危险色描边，勾选则连同记忆一起删除。
            Container(
              decoration: BoxDecoration(
                color: danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _withMemory,
                    activeColor: danger,
                    side: BorderSide(color: danger.withValues(alpha: 0.6)),
                    onChanged: (value) =>
                        setState(() => _withMemory = value ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '连同记忆一起删除',
                            style: TextStyle(
                              color: mode.cardBody,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '不勾选：由这段对话产生的记忆保留，标记「源记录已删除」',
                            style: TextStyle(
                              color: mode.cardMuted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DialogGhostButton(
                    mode: mode,
                    label: '取消',
                    onTap: () => Navigator.of(context).pop((false, false)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogDangerButton(
                    mode: mode,
                    label: '删除',
                    onTap: () =>
                        Navigator.of(context).pop((true, _withMemory)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗头部：色块图标 + 标题（标题字号适中，不夸张）。
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.mode,
    required this.icon,
    required this.title,
    this.accent,
  });

  final ModeTheme mode;
  final IconData icon;
  final String title;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? mode.primary;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: mode.cardTitle,
            fontSize: 16,
            fontWeight: mode.strongWeight,
          ),
        ),
      ],
    );
  }
}

/// 次要按钮：透明底 + 弱化文字，圆角/切角跟随模式。
class _DialogGhostButton extends StatelessWidget {
  const _DialogGhostButton({required this.mode, required this.label, required this.onTap});

  final ModeTheme mode;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: mode.chipRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 主操作按钮：模式主色填充，圆角/切角跟随模式。
class _DialogPrimaryButton extends StatelessWidget {
  const _DialogPrimaryButton({
    required this.mode,
    required this.label,
    required this.onTap,
  });

  final ModeTheme mode;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.primary,
      borderRadius: mode.chipRadius,
      child: InkWell(
        borderRadius: mode.chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mode.onPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 危险按钮：模式危险色填充，圆角/切角跟随模式。
class _DialogDangerButton extends StatelessWidget {
  const _DialogDangerButton({required this.mode, required this.label, required this.onTap});

  final ModeTheme mode;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _modeDanger(mode),
      borderRadius: mode.chipRadius,
      child: InkWell(
        borderRadius: mode.chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 面板顶部：仅标题「设置」（模式名不展示，收起靠遮罩 / 系统返回键）。
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        '设置',
        style: TextStyle(
          color: mode.text,
          fontSize: 20,
          fontWeight: mode.strongWeight,
        ),
      ),
    );
  }
}

/// 搜索框（样式跟随模式：圆角 / 直角 / 斜切）。
class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.mode,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final ModeTheme mode;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // 比输赢模式：深色底 + 白色输入文字（保证可见）；其余模式用卡片色组。
    final isWin = mode.view == BattleView.win;
    final fieldBackground = isWin ? mode.surface : mode.cardBackground;
    final fieldText = isWin ? mode.text : mode.cardBody;
    final fieldMuted = isWin ? mode.textMuted : mode.cardMuted;

    return Container(
      decoration: BoxDecoration(
        color: fieldBackground,
        borderRadius: mode.inputRadius,
        border: Border.all(color: mode.cardBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: fieldText, fontSize: 14),
        cursorColor: isWin ? mode.text : mode.primary,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索聊天记录',
          hintStyle: TextStyle(color: fieldMuted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: fieldMuted,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空',
                icon: Icon(Icons.close_rounded, size: 18, color: fieldMuted),
                onPressed: onClear,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 主要操作（新建对话）：主色填充，三模式分别为绿 / 金 / 白底反色。
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.mode,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.actionChipBackground,
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(color: mode.actionChipBorder, width: 1),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: mode.chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: mode.actionChipForeground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mode.actionChipForeground,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 次要操作（配置 API）：表面色底 + 模式主色图标，比主按钮矮一档；
/// 已配置时文字后带主色圆点状态提示。
class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.mode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.statusOn = false,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 是否已配置（显示主色状态点）。
  final bool statusOn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.chipBackground,
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(color: mode.chipBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: mode.chipRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: mode.primary),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mode.cardBody,
                    fontSize: 13.5,
                    fontWeight: mode.strongWeight,
                  ),
                ),
              ),
              if (statusOn) ...[
                const SizedBox(width: 7),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: mode.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条聊天记录：以日期命名（重命名后显示自定义名称），右侧显示开始时间；
/// 点击切换对话，长按弹出主题样式操作菜单（置顶 / 重命名 / 删除）。
class _AssetManagementScreen extends ConsumerStatefulWidget {
  const _AssetManagementScreen({required this.mode});

  final ModeTheme mode;

  @override
  ConsumerState<_AssetManagementScreen> createState() => _AssetManagementScreenState();
}

class _AssetManagementScreenState extends ConsumerState<_AssetManagementScreen> {
  bool _sortByTitle = false;
  final Set<String> _selected = {};

  Future<List<_AssetRecord>> _loadAssets() async {
    final repository = ref.read(appRepositoryProvider);
    final cases = await repository.watchCases().first;
    final assets = await repository.watchAssets().first;
    final records = <_AssetRecord>[];
    for (final asset in assets) {
      final related = <Case>[];
      for (final caseItem in cases) {
        final messages = await repository.watchMessages(caseItem.id).first;
        if (messages.any((message) => message.assetPath == asset.path)) related.add(caseItem);
      }
      for (final caseItem in related) {
        records.add(_AssetRecord(asset: asset, caseItem: caseItem));
      }
    }
    records.sort((a, b) => _sortByTitle
        ? a.displayTitle.compareTo(b.displayTitle)
        : b.createdAt.compareTo(a.createdAt));
    return records;
  }

  Future<void> _deleteSelected(List<_AssetRecord> assets) async {
    final repository = ref.read(appRepositoryProvider);
    final ids = <String>[];
    for (final asset in assets.where((item) => _selected.contains(item.path))) {
      final saved = await repository.assetByPath(asset.path);
      if (saved != null) ids.add(saved.id);
    }
    await repository.deleteAssets(ids);
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return Scaffold(
      backgroundColor: mode.background,
      appBar: AppBar(
        backgroundColor: mode.background,
        foregroundColor: mode.text,
        title: const Text('资产管理'),
        actions: [
          IconButton(
            tooltip: '按标题排序',
            onPressed: () => setState(() => _sortByTitle = !_sortByTitle),
            icon: Icon(_sortByTitle ? Icons.sort_by_alpha : Icons.schedule),
          ),
        ],
      ),
      body: FutureBuilder<List<_AssetRecord>>(
        future: _loadAssets(),
        builder: (context, snapshot) {
          final assets = snapshot.data ?? const <_AssetRecord>[];
          final total = assets.fold<int>(0, (sum, item) => sum + item.size);
          final byConversation = <String, int>{};
          for (final item in assets) {
            byConversation[item.caseItem.id] =
                (byConversation[item.caseItem.id] ?? 0) + item.size;
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Text(
                  '图片 ${_formatSize(total)} · ${assets.length} 张 · ${byConversation.length} 个对话',
                  style: TextStyle(color: mode.textMuted, fontSize: 12),
                ),
              ),
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _deleteSelected(assets),
                      icon: Icon(Icons.delete_outline, color: _modeDanger(mode)),
                      label: Text('删除所选', style: TextStyle(color: _modeDanger(mode))),
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final caseItem in byConversation.keys.map((id) => assets.firstWhere((a) => a.caseItem.id == id).caseItem)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(
                          '${caseItem.displayTitle} · ${_formatSize(byConversation[caseItem.id] ?? 0)}',
                          style: TextStyle(color: mode.text, fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final asset in assets.where((a) => a.caseItem.id == caseItem.id))
                        _AssetTile(
                          asset: asset,
                          mode: mode,
                          selected: _selected.contains(asset.path),
                          onSelected: (value) => setState(() => value ? _selected.add(asset.path) : _selected.remove(asset.path)),
                          onRename: (title) async {
                            final current = await ref.read(appRepositoryProvider).assetByPath(asset.path);
                            if (current != null) {
                              await ref.read(appRepositoryProvider).renameAsset(current.id, title);
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _AssetRecord {
  const _AssetRecord({required this.asset, required this.caseItem});
  final Asset asset;
  final Case caseItem;
  String get path => asset.path;
  DateTime get createdAt => asset.createdAt;
  int get size => asset.sizeBytes;
  String get displayTitle => asset.displayTitle;
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.mode, required this.selected, required this.onSelected, required this.onRename});
  final _AssetRecord asset;
  final ModeTheme mode;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: mode.cardBackground,
      child: ListTile(
        leading: GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: Image.file(
                File(asset.path),
                errorBuilder: (_, _, _) => _MissingAssetIcon(mode: mode),
              ),
            ),
          ),
          child: Image.file(
            File(asset.path),
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            // 文件可能已被移动/删除：显示占位图标而不是报错。
            errorBuilder: (_, _, _) => _MissingAssetIcon(mode: mode),
          ),
        ),
        title: Text(asset.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mode.cardTitle)),
        subtitle: Text('${_formatDateTime(asset.createdAt)} · ${asset.size ~/ 1024} KB', style: TextStyle(color: mode.cardMuted, fontSize: 11)),
        trailing: Checkbox(value: selected, onChanged: (value) => onSelected(value ?? false)),
        onLongPress: () async {
          final controller = TextEditingController(text: asset.displayTitle);
          final title = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('重命名资产'), content: TextField(controller: controller), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存'))]));
          if (title != null && title.isNotEmpty) onRename(title);
        },
      ),
    );
  }

  String _formatDateTime(DateTime value) => '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

/// 图片文件缺失时的占位图标（资产已被移动/删除时展示，不中断列表渲染）。
class _MissingAssetIcon extends StatelessWidget {
  const _MissingAssetIcon({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      color: mode.cardBorder.withValues(alpha: 0.35),
      child: Icon(Icons.broken_image_outlined, size: 22, color: mode.cardMuted),
    );
  }
}

class _ConversationRow extends ConsumerStatefulWidget {
  const _ConversationRow({
    required this.mode,
    required this.caseItem,
    required this.isActive,
    required this.onTap,
  });

  final ModeTheme mode;
  final Case caseItem;
  final bool isActive;
  final VoidCallback onTap;

  @override
  ConsumerState<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends ConsumerState<_ConversationRow> {
  ModeTheme get mode => widget.mode;
  Case get caseItem => widget.caseItem;
  bool get isActive => widget.isActive;

  @override
  Widget build(BuildContext context) {
    // 比输赢模式走黑白对决：选中=灰色、未选中=黑色；其余模式沿用主题高亮。
    final isWin = mode.view == BattleView.win;
    final Color rowBackground;
    final Color titleColor;
    final Color timeColor;
    if (isWin) {
      rowBackground = isActive ? mode.cardBackground : mode.surface;
      titleColor = isActive ? mode.cardTitle : mode.text;
      timeColor = isActive ? mode.cardMuted : mode.textMuted;
    } else {
      rowBackground = isActive ? mode.primary : mode.cardBackground;
      titleColor = isActive ? mode.onPrimary : mode.cardTitle;
      timeColor = isActive
          ? mode.onPrimary.withValues(alpha: 0.78)
          : mode.cardMuted;
    }
    final rowBorder = isActive
        ? (isWin ? mode.primary : mode.onPrimary.withValues(alpha: 0.35))
        : mode.cardBorder;

    final hasName = caseItem.title != null && caseItem.title!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        // 长按跟随手指位置弹出操作菜单（InkWell 不暴露长按起点，需外层手势接管）。
        onLongPressStart: _showRowMenu,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: mode.cardRadius,
            onTap: widget.onTap,
            child: Container(
              // 左侧留白比右侧多，文字整体右移。
              padding: const EdgeInsets.fromLTRB(20, 7, 14, 7),
              decoration: BoxDecoration(
                color: rowBackground,
                borderRadius: mode.cardRadius,
                border: Border.all(color: rowBorder, width: 1),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Row(
                      children: [
                        if (caseItem.isImported) ...[
                          Text(
                            '导入',
                            style: TextStyle(
                              color: timeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            hasName
                                ? caseItem.title!
                                : formatDate(caseItem.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 15,
                              fontWeight: mode.strongWeight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatTime(caseItem.createdAt),
                    style: TextStyle(color: timeColor, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 长按：在手指位置弹出主题样式的操作菜单（跟随模式的卡片视觉语言）。
  Future<void> _showRowMenu(LongPressStartDetails details) async {
    final action = await _RowActionMenu.show(
      context,
      mode: mode,
      touch: details.globalPosition,
      canUnpin: caseItem.isPinned,
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'pin':
        await _togglePinned();
      case 'rename':
        await _showRenameDialog();
      case 'share':
        await _shareConversation();
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _shareConversation() async {
    try {
      final file = await const ConversationTransferService().exportConversation(
        repository: ref.read(appRepositoryProvider),
        conversationId: caseItem.id,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'So What 聊天记录分享包',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$error')),
        );
      }
    }
  }

  Future<void> _togglePinned() async {
    try {
      await ref
          .read(repositoryActionsProvider)
          .setConversationPinned(caseItem.id, !caseItem.isPinned);
    } catch (_) {
      _showError('操作失败，请稍后重试。');
    }
  }

  Future<void> _showRenameDialog() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        mode: mode,
        initialName: caseItem.title ?? '',
      ),
    );
    if (title == null || title.isEmpty || title == caseItem.title) return;
    try {
      await ref
          .read(repositoryActionsProvider)
          .renameConversation(caseItem.id, title);
    } catch (_) {
      _showError('重命名失败，请稍后重试。');
    }
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<(bool, bool)>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(mode: mode),
    );
    if (result == null || !result.$1 || !mounted) return;
    final deleteMemory = result.$2;

    try {
      final actions = ref.read(repositoryActionsProvider);
      final repository = ref.read(appRepositoryProvider);
      final wasCurrent = ref.read(selectedConversationIdProvider) == caseItem.id;
      await actions.deleteConversation(caseItem.id, deleteMemory: deleteMemory);

      // 删的是当前打开的对话时，切到最近一条；没有剩余则新建一段空白对话。
      if (wasCurrent) {
        final remaining = (await repository.watchCases().first).toList()
          ..sort(_SettingsPanelState._compareCases);
        if (remaining.isNotEmpty) {
          ref.read(selectedConversationIdProvider.notifier).state =
              remaining.first.id;
        } else {
          final fresh = await actions.createConversation();
          ref.read(selectedConversationIdProvider.notifier).state = fresh.id;
        }
      }
    } catch (_) {
      _showError('删除失败，请稍后重试。');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _HistorySectionLabel extends StatelessWidget {
  const _HistorySectionLabel({required this.mode, required this.text});

  final ModeTheme mode;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: mode.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

/// 空态：没有聊天记录，或搜索无结果。
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.mode, required this.hasQuery});

  final ModeTheme mode;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.chat_rounded,
              size: 34,
              color: mode.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              hasQuery ? '没有找到相关聊天记录' : '还没有聊天记录',
              style: TextStyle(
                color: mode.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (!hasQuery) ...[
              const SizedBox(height: 6),
              Text(
                '点上方「新建对话」开始一段新的记录。',
                style: TextStyle(color: mode.textMuted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 重命名弹窗：主题化卡片（跟随模式卡片视觉），自己持有输入控制器，
/// 在路由完全关闭后释放，避免「Controller used after being disposed」。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.mode, required this.initialName});

  final ModeTheme mode;
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final isWin = mode.view == BattleView.win;
    final inputText = isWin ? mode.text : mode.cardBody;
    final inputMuted = isWin ? mode.textMuted : mode.cardMuted;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 292,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: _cardSurface(mode),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              mode: mode,
              icon: Icons.edit_outlined,
              title: '重命名对话',
            ),
            const SizedBox(height: 10),
            Text(
              '自定义名称会替代日期显示，原日期时间仍可搜索。',
              style: TextStyle(color: mode.cardMuted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: mode.surface,
                borderRadius: mode.inputRadius,
                border: Border.all(color: mode.cardBorder),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                // 用格式化器限制长度，不显示计数器，避免撑高输入框破坏胶囊圆角。
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                style: TextStyle(color: inputText, fontSize: 14),
                cursorColor: isWin ? mode.text : mode.primary,
                decoration: InputDecoration(
                  hintText: '输入新名称',
                  hintStyle: TextStyle(color: inputMuted, fontSize: 12.5),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DialogGhostButton(
                    mode: mode,
                    label: '取消',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DialogPrimaryButton(
                    mode: mode,
                    label: '确定',
                    onTap: () =>
                        Navigator.of(context).pop(_controller.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
