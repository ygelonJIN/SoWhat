import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/conversation_transfer_service.dart';
import '../../providers/app_providers.dart';
import '../../screens/ai_config_screen.dart';
import '../../theme/fold_decoration.dart';
import '../../theme/mode_theme.dart';
import '../../utils/format.dart';
import '../feedback/feedback.dart';

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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AiConfigScreen()));
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
                      padding: const EdgeInsets.fromLTRB(16, 268, 16, 330),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SecondaryActionButton(
                    mode: mode,
                    icon: Icons.photo_library_rounded,
                    label: '资产管理',
                    onTap: () => _showAssetManagementPlaceholder(context, mode),
                  ),
                  const SizedBox(height: 10),
                  // 清空所有数据：与资产管理同款次按钮，主色图标 + 主色文字。
                  _SecondaryActionButton(
                    mode: mode,
                    icon: Icons.delete_sweep_outlined,
                    label: '清空所有数据',
                    onTap: () => _confirmWipeAllData(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 清空全部用户数据：二次确认后调用仓库清空，并重置当前对话选择。
  /// 确认按钮使用模式主色（与「清空所有数据」按钮的主色一致）。
  Future<void> _confirmWipeAllData(BuildContext context) async {
    final mode = widget.mode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: CutBox(
          width: 300,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          fold: mode.cornerFold,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(
                mode: mode,
                icon: Icons.delete_forever_outlined,
                title: '清空所有数据？',
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Text(
                    '将删除：\n· 全部聊天记录与消息\n· 全部模式分析卡片\n· 长期记忆档案\n· 全部上传图片\n\n保留：AI 接口配置（API Key）。\n\n此操作不可撤销。',
                    style: TextStyle(color: mode.cardBody, height: 1.6),
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
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogPrimaryButton(
                      mode: mode,
                      label: '清空',
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(appRepositoryProvider).wipeUserData();
      // 重置当前对话选择与思考状态，让界面回到全新空白态。
      ref.read(selectedConversationIdProvider.notifier).state = null;
      ref.invalidate(casesProvider);
      ref.invalidate(memoryProfileProvider);
      ref.invalidate(assetsProvider);
      if (!context.mounted) return;
      FeedbackDialog.show(context, mode, message: '已清空全部数据');
    } catch (e, st) {
      debugPrint('[SettingsPanel] 清空数据失败: $e\n$st');
      if (!context.mounted) return;
      FeedbackDialog.error(context, mode, '清空失败，请稍后重试。');
    }
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

/// 长按聊天记录弹出的操作菜单：跟随手指位置、卡片视觉跟随模式。
///
/// 每个操作一项：主色瓷片图标 + 文字，危险项（删除）用模式危险色；
/// 菜单项之间用细分割线，圆角 / 描边 / 阴影跟随模式卡片语言。
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

  static const _width = 208.0;
  static const _itemHeight = 52.0;

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
            shape: FoldShape(
              borderRadius: mode.cardRadius,
              side: BorderSide(color: mode.cardBorder, width: 1),
              fold: mode.cornerFold,
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 14,
            shadowColor: Colors.black.withValues(
              alpha: (mode.cardShadowAlpha + 0.10).clamp(0, 1),
            ),
            child: SizedBox(
              width: _width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuAction(
                    mode: mode,
                    icon: Icons.push_pin_rounded,
                    label: canUnpin ? '取消置顶' : '置顶',
                    onTap: () => Navigator.of(context).pop('pin'),
                  ),
                  _menuDivider(mode),
                  _MenuAction(
                    mode: mode,
                    icon: Icons.edit_rounded,
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
                    icon: Icons.delete_outlined,
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

/// 菜单单项：主色瓷片图标 + 文字，危险项整体用模式危险色。
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
    final chipBackground = color.withValues(alpha: 0.10);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _RowActionMenu._itemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: chipBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
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
      child: CutBox(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        fold: mode.cornerFold,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              mode: mode,
              icon: Icons.delete_outlined,
              title: '删除这段对话？',
              accent: danger,
            ),
            const SizedBox(height: 10),
            Text(
              '聊天记录与截图将一并删除，此操作无法恢复。',
              style: TextStyle(
                color: mode.cardMuted,
                fontSize: 12,
                height: 1.5,
              ),
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
                    onTap: () => Navigator.of(context).pop((true, _withMemory)),
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
  const _DialogGhostButton({
    required this.mode,
    required this.label,
    required this.onTap,
  });

  final ModeTheme mode;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: FoldShape(borderRadius: mode.chipRadius, fold: mode.cornerFold),
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
      shape: FoldShape(borderRadius: mode.chipRadius, fold: mode.cornerFold),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: mode.cornerFold ? null : mode.chipRadius,
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
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
  const _DialogDangerButton({
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
      color: _modeDanger(mode),
      shape: FoldShape(borderRadius: mode.chipRadius, fold: mode.cornerFold),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: mode.cornerFold ? null : mode.chipRadius,
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
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

/// 搜索框（与输入框统一：chip 底色 + 描边 + 模式圆角，三模式通用）。
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
    return CutBox(
      fold: mode.cornerFold,
      color: mode.chipBackground,
      borderRadius: mode.inputRadius,
      border: Border.all(color: mode.chipBorder),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: mode.text, fontSize: 14),
        cursorColor: mode.primary,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索聊天记录',
          hintStyle: TextStyle(color: mode.textMuted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          prefixIcon: Icon(
            Icons.search_outlined,
            size: 20,
            color: mode.textMuted,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空',
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: mode.textMuted,
                ),
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
      shape: FoldShape(
        borderRadius: mode.chipRadius,
        side: BorderSide(color: mode.actionChipBorder, width: 1),
        fold: mode.cornerFold,
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: mode.cornerFold ? null : mode.chipRadius,
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
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
      shape: FoldShape(
        borderRadius: mode.chipRadius,
        side: BorderSide(color: mode.chipBorder, width: 1),
        fold: mode.cornerFold,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: mode.cornerFold ? null : mode.chipRadius,
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
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
  ConsumerState<_AssetManagementScreen> createState() =>
      _AssetManagementScreenState();
}

/// 资产管理按「对话」组织：一行一个对话（按日期时间命名），点击展开该对话的
/// 全部图片缩略图；只支持按对话整组删除，不支持逐张删除。
class _AssetManagementScreenState
    extends ConsumerState<_AssetManagementScreen> {
  /// 当前展开显示缩略图的对话 id 集合。
  final Set<String> _expanded = {};

  Future<List<_ConversationAssets>> _loadGroups() async {
    final repository = ref.read(appRepositoryProvider);
    final cases = await repository.watchCases().first;
    final assets = await repository.watchAssets().first;
    final byPath = <String, Asset>{for (final a in assets) a.path: a};

    // 对话 id -> 消息里出现过的资产缩略图列表（按消息顺序）。
    final groups = <_ConversationAssets>[];
    for (final caseItem in cases) {
      final messages = await repository.watchMessages(caseItem.id).first;
      final images = <_AssetRecord>[];
      for (final message in messages) {
        final path = message.assetPath;
        if (path == null || path.isEmpty || !message.isImageType) continue;
        final asset = byPath[path];
        if (asset == null) continue;
        // 同一路径可能多次出现，只在第一个出现的位置计入列表。
        if (images.any((r) => r.path == path)) continue;
        images.add(_AssetRecord(asset: asset, caseItem: caseItem));
      }
      if (images.isNotEmpty) groups.add(_ConversationAssets(caseItem, images));
    }

    // 按对话创建时间倒序。
    groups.sort((a, b) => b.caseItem.createdAt.compareTo(a.caseItem.createdAt));
    return groups;
  }

  /// 整组删除：删除该对话涉及的全部资产文件与记录（资产可能被多个对话共用，
  /// 删除时只删掉「本对话」用到的资产记录，但物理文件仅在无其它对话引用时删除）。
  Future<void> _deleteGroup(_ConversationAssets group) async {
    final repository = ref.read(appRepositoryProvider);
    final mode = widget.mode;
    // 确认后再删除；确认按钮沿用模式危险红。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: CutBox(
          width: 300,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          fold: mode.cornerFold,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(
                mode: mode,
                icon: Icons.delete_outlined,
                title: '删除这段对话的图片？',
                accent: _modeDanger(mode),
              ),
              const SizedBox(height: 10),
              Text(
                '将删除「${group.label}」下的 ${group.images.length} 张图片记录，此操作无法恢复。',
                style: TextStyle(color: mode.cardBody, height: 1.5),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DialogGhostButton(
                      mode: mode,
                      label: '取消',
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogDangerButton(
                      mode: mode,
                      label: '删除',
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final ids = <String>[];
    for (final image in group.images) {
      final saved = await repository.assetByPath(image.path);
      if (saved != null) ids.add(saved.id);
    }
    await repository.deleteAssets(ids);
    if (mounted) setState(() => _expanded.remove(group.caseItem.id));
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
      ),
      body: FutureBuilder<List<_ConversationAssets>>(
        future: _loadGroups(),
        builder: (context, snapshot) {
          final groups = snapshot.data ?? const <_ConversationAssets>[];
          final totalCount = groups.fold<int>(
            0,
            (sum, g) => sum + g.images.length,
          );
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 34,
                    color: mode.textMuted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '还没有上传的图片',
                    style: TextStyle(color: mode.textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '共 ${groups.length} 个对话 · $totalCount 张图片',
                  style: TextStyle(color: mode.textMuted, fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  '按对话整组管理，展开即可查看该对话的全部图片；删除按对话进行。',
                  style: TextStyle(
                    color: mode.textMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    for (final group in groups) ...[
                      _ConversationAssetGroup(
                        mode: mode,
                        group: group,
                        expanded: _expanded.contains(group.caseItem.id),
                        onToggle: () => setState(() {
                          if (!_expanded.remove(group.caseItem.id)) {
                            _expanded.add(group.caseItem.id);
                          }
                        }),
                        onDelete: () => _deleteGroup(group),
                      ),
                      const SizedBox(height: 10),
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
}

/// 可读的体积格式化。
String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// 一个对话组（对话 + 该对话用到的图片）。
class _ConversationAssets {
  const _ConversationAssets(this.caseItem, this.images);
  final Case caseItem;
  final List<_AssetRecord> images;

  /// 按日期时间命名（与聊天记录一致）；有自定义名称时优先显示自定义名称。
  String get label {
    final hasName = caseItem.title != null && caseItem.title!.isNotEmpty;
    if (hasName) return caseItem.title!;
    return dateTimeLabel(caseItem.createdAt);
  }

  int get totalSizeBytes => images.fold<int>(0, (sum, r) => sum + r.size);
}

class _AssetRecord {
  const _AssetRecord({required this.asset, required this.caseItem});
  final Asset asset;
  final Case caseItem;
  String get path => asset.path;
  DateTime get createdAt => asset.createdAt;
  int get size => asset.sizeBytes;
}

/// 单个对话资产组：收起时一行展示「日期名称 + 图片数 + 大小」；
/// 展开后横向滚动展示全部缩略图（点击看大图），并附带「整组删除」。
class _ConversationAssetGroup extends StatefulWidget {
  const _ConversationAssetGroup({
    required this.mode,
    required this.group,
    required this.expanded,
    required this.onToggle,
    required this.onDelete,
  });

  final ModeTheme mode;
  final _ConversationAssets group;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  State<_ConversationAssetGroup> createState() =>
      _ConversationAssetGroupState();
}

class _ConversationAssetGroupState extends State<_ConversationAssetGroup> {
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final group = widget.group;

    return Material(
      color: mode.cardBackground,
      shape: FoldShape(
        borderRadius: mode.cardRadius,
        side: BorderSide(color: mode.cardBorder, width: 1),
        fold: mode.cornerFold,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: mode.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 18,
                      color: mode.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mode.cardTitle,
                            fontSize: 15,
                            fontWeight: mode.strongWeight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${group.images.length} 张 · ${_formatSize(group.totalSizeBytes)}',
                          style: TextStyle(color: mode.cardMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 整组删除：主色描边小按钮，与展开箭头并列、间距加大。
                  _GroupDeleteButton(mode: mode, onDelete: widget.onDelete),
                  const SizedBox(width: 2),
                  Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: mode.cardMuted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _GroupContent(mode: mode, images: group.images),
            crossFadeState: widget.expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// 整组删除小按钮：主色描边 + 主色图标（危险操作不再用突兀的大红块）。
class _GroupDeleteButton extends StatelessWidget {
  const _GroupDeleteButton({required this.mode, required this.onDelete});

  final ModeTheme mode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: FoldShape(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: mode.primary.withValues(alpha: 0.35)),
        fold: mode.cornerFold,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDelete,
        borderRadius: mode.cornerFold ? null : BorderRadius.circular(10),
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outlined, size: 15, color: mode.primary),
              const SizedBox(width: 5),
              Text(
                '删除图片',
                style: TextStyle(
                  color: mode.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对话组展开后的内容：横向缩略图。
class _GroupContent extends StatelessWidget {
  const _GroupContent({required this.mode, required this.images});

  final ModeTheme mode;
  final List<_AssetRecord> images;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: mode.cardBorder.withValues(alpha: 0.6),
        ),
        // 缩略图 + 序号文字高约 79（图片 64 + 间距 2 + 文字）；高度与内边距
        // 留足，确保底部序号文字与卡片下沿有间距，不会被裁切或贴边。
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final record = images[index];
              return _AssetThumb(
                mode: mode,
                asset: record.asset,
                index: index,
                total: images.length,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 对话内单张缩略图：点击放大预览；显示序号与文件名（超出省略）。
class _AssetThumb extends StatelessWidget {
  const _AssetThumb({
    required this.mode,
    required this.asset,
    required this.index,
    required this.total,
  });

  final ModeTheme mode;
  final Asset asset;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final name = asset.displayTitle.length > 18
        ? '${asset.displayTitle.substring(0, 18)}…'
        : asset.displayTitle;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(asset.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _MissingAssetIcon(mode: mode),
                ),
              ),
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(asset.path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              // 文件可能已被移动/删除：显示占位图标而不是报错。
              errorBuilder: (_, _, _) => _MissingAssetIcon(mode: mode),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 64,
            child: Text(
              '${index + 1}/$total · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: mode.cardMuted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图片文件缺失时的占位图标（资产已被移动/删除时展示，不中断列表渲染）。
class _MissingAssetIcon extends StatelessWidget {
  const _MissingAssetIcon({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      color: mode.cardBorder.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, size: 24, color: mode.cardMuted),
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
    // 选中 = 主色填充（比输赢为黑底白字），未选中 = 卡片色，三模式同一逻辑。
    final rowBackground = isActive ? mode.primary : mode.cardBackground;
    final titleColor = isActive ? mode.onPrimary : mode.cardTitle;
    final timeColor = isActive
        ? mode.onPrimary.withValues(alpha: 0.78)
        : mode.cardMuted;
    final rowBorder = isActive
        ? mode.onPrimary.withValues(alpha: 0.35)
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
            borderRadius: mode.cornerFold ? null : mode.cardRadius,
            customBorder: mode.cornerFold
                ? FoldShape(
                    borderRadius: BorderRadius.zero,
                    side: BorderSide.none,
                    fold: true,
                  )
                : null,
            onTap: widget.onTap,
            child: CutBox(
              // 左侧留白比右侧多，文字整体右移。
              padding: const EdgeInsets.fromLTRB(20, 7, 14, 7),
              fold: mode.cornerFold,
              color: rowBackground,
              borderRadius: mode.cardRadius,
              border: Border.all(color: rowBorder, width: 1),
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
        ShareParams(files: [XFile(file.path)], text: 'So What 聊天记录分享包'),
      );
    } catch (error) {
      if (mounted) {
        FeedbackDialog.error(context, mode, '分享失败：$error');
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
      builder: (_) =>
          _RenameDialog(mode: mode, initialName: caseItem.title ?? ''),
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
      final wasCurrent =
          ref.read(selectedConversationIdProvider) == caseItem.id;
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
    FeedbackDialog.error(context, mode, message);
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
              hasQuery ? Icons.search_off_outlined : Icons.chat_outlined,
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: CutBox(
        width: 292,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        fold: mode.cornerFold,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(mode: mode, icon: Icons.edit_rounded, title: '重命名对话'),
            const SizedBox(height: 10),
            Text(
              '自定义名称会替代日期显示，原日期时间仍可搜索。',
              style: TextStyle(
                color: mode.cardMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            CutBox(
              fold: mode.cornerFold,
              color: mode.chipBackground,
              borderRadius: mode.inputRadius,
              border: Border.all(color: mode.chipBorder),
              child: TextField(
                controller: _controller,
                autofocus: true,
                // 用格式化器限制长度，不显示计数器，避免撑高输入框破坏胶囊圆角。
                inputFormatters: [LengthLimitingTextInputFormatter(30)],
                style: TextStyle(color: mode.text, fontSize: 14),
                cursorColor: mode.primary,
                decoration: InputDecoration(
                  hintText: '输入新名称',
                  hintStyle: TextStyle(color: mode.textMuted, fontSize: 12.5),
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
