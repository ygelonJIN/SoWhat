import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../repositories/memory_app_repository.dart';
import '../services/prompt_service.dart';
import '../theme/mode_theme.dart';
import '../widgets/battle/battle_canvas.dart';
import '../widgets/battle/image_fan_gallery.dart';

/// 主聊天界面（产品文档 3.1）。
///
/// 现在是“全屏聊天 + 浮层控制”：顶部设置/日期、模式切换、输入框都悬浮在
/// 聊天内容上方，不再占用页面布局高度。
class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _conversationId = MemoryAppRepository.currentConversationId;
  final _imagePicker = ImagePicker();
  final _promptService = const PromptService();

  final _fanGalleryKey = GlobalKey<ImageFanGalleryState>();
  final _inputFocusNode = FocusNode();
  bool _isFanPeeked = false;
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_handleInputFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runAnalysis();
    });
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_handleInputFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleInputFocusChanged() {
    if (!mounted) return;
    final visible = _inputFocusNode.hasFocus;
    if (visible != _keyboardVisible) {
      setState(() => _keyboardVisible = visible);
    }
  }

  void _dismissKeyboardFromCanvas() {
    if (_keyboardVisible) {
      FocusScope.of(context).unfocus();
    }
  }

  void _onFanPeekChanged(bool peeked) {
    if (mounted && _isFanPeeked != peeked) {
      setState(() => _isFanPeeked = peeked);
    }
  }

  void _collapseFanOnScroll() {
    _collapseFan();
  }

  void _collapseFan() {
    if (_isFanPeeked) {
      _fanGalleryKey.currentState?.collapse();
      setState(() => _isFanPeeked = false);
    }
  }

  void _dismissFanAndKeyboard() {
    FocusScope.of(context).unfocus();
    _collapseFan();
  }

  Future<void> _deleteAllScreenshots() async {
    _collapseFan();
    try {
      final messages = await ref
          .read(appRepositoryProvider)
          .watchMessages(_conversationId)
          .first;
      final imageMessages = messages.where((message) => message.assetPath != null).toList();
      for (final message in imageMessages) {
        await ref.read(repositoryActionsProvider).deleteMessage(
              conversationId: _conversationId,
              sequence: message.sequence,
            );
      }
      await _runAnalysis();
    } catch (error) {
      _showError('删除截图失败，请稍后重试。', error);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || ref.read(isAnalyzingProvider)) return;
    try {
      await ref
          .read(repositoryActionsProvider)
          .addMessage(
            conversationId: _conversationId,
            party: Party.a,
            content: text,
          );
      _messageController.clear();
      await _runAnalysis();
      _scrollToBottom();
    } catch (_) {
      _showError('发送失败，请稍后重试。');
    }
  }

  Future<void> _pickImages() async {
    if (ref.read(isAnalyzingProvider)) return;
    try {
      final images = await _imagePicker.pickMultiImage();
      if (images.isEmpty) return;
      for (int i = 0; i < images.length; i++) {
        await ref
            .read(repositoryActionsProvider)
            .addMessage(
              conversationId: _conversationId,
              party: Party.a,
              type: MessageType.image,
              content: '截图 ${i + 1}：${images[i].name}',
              assetPath: images[i].path,
            );
      }
      await _runAnalysis();
      _scrollToBottom();
    } catch (error) {
      _showError('截图导入失败，请检查相册权限。', error);
    }
  }

  Future<void> _runAnalysis() async {
    if (ref.read(isAnalyzingProvider)) return;
    try {
      await ref.read(repositoryActionsProvider).runAnalysis(_conversationId);
    } catch (error) {
      _showError('分析失败，请稍后重试。', error);
    }
  }

  Future<void> _selectView(BattleView view) async {
    if (ref.read(isAnalyzingProvider)) return;
    ref.read(selectedBattleViewProvider.notifier).state = view;
    try {
      await ref.read(repositoryActionsProvider).setBattleView(view);
      await _runAnalysis();
    } catch (error) {
      _showError('切换视角失败，请稍后重试。', error);
    }
  }

  Future<void> _exportPrompt() async {
    final view = ref.read(selectedBattleViewProvider);
    final repository = ref.read(appRepositoryProvider);
    final memory = await repository.watchMemory().first;
    final messages = await repository.watchMessages(_conversationId).first;

    if (messages.isEmpty) {
      _showSnackBar('还没有对话内容，先贴一段对话进来吧。');
      return;
    }

    try {
      final pkg = _promptService.buildExportPackage(
        view: view,
        memory: memory,
        messages: messages,
      );
      await Clipboard.setData(ClipboardData(text: pkg.fullText));
      if (mounted) {
        _showSnackBar('分析包已复制！可以粘贴到 Kimi / 豆包 / DeepSeek 等免费 AI 分析。');
      }
    } catch (error) {
      _showError('复制分析包失败，请稍后重试。', error);
    }
  }

  void _showSettingsPlaceholder() {
    _showSnackBar('设置功能将在后续版本开放。');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String message, [Object? error]) {
    if (!mounted) return;
    _showSnackBar(error == null ? message : '$message（$error）');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final battleAsync = ref.watch(battleStateProvider);
    final selectedView = ref.watch(selectedBattleViewProvider);
    final messagesAsync = ref.watch(
      conversationMessagesProvider(_conversationId),
    );
    final isAnalyzing = ref.watch(isAnalyzingProvider);
    final conversationStartedAt =
        ref.watch(conversationStartedAtProvider).valueOrNull ??
        DateTime.now();

    final mode = ModeThemes.of(selectedView);
    final messages = messagesAsync.valueOrNull ?? const [];
    final screenshotPaths = messages
        .where((m) => m.isImageType && m.assetPath != null)
        .map((m) => m.assetPath!)
        .toList();

    return Theme(
      data: mode.themeData,
      child: Scaffold(
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: mode.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Stack(
            children: [
              Positioned.fill(child: Container(color: mode.background)),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _dismissKeyboardFromCanvas,
                  child: BattleCanvas(
                    state: battleAsync.valueOrNull ??
                        BattleState.initial(selectedView),
                    messages: messages,
                    scrollController: _scrollController,
                    onScroll: _collapseFanOnScroll,
                  ),
                ),
              ),
              if (_isFanPeeked)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: const SizedBox.expand(),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _FloatingTopChrome(
                          mode: mode,
                          startedAt: conversationStartedAt,
                          onExportPrompt: _exportPrompt,
                          onSettings: _showSettingsPlaceholder,
                          isAnalyzing: isAnalyzing,
                        ),
                        if (screenshotPaths.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ImageFanGallery(
                              key: _fanGalleryKey,
                              paths: screenshotPaths,
                              mode: mode,
                              onPeekChanged: _onFanPeekChanged,
                              onRemove: _deleteAllScreenshots,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 176,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          mode.background.withValues(alpha: 1.0),
                          mode.background.withValues(alpha: 0.9),
                          mode.background.withValues(alpha: 0.48),
                          mode.background.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.34, 0.72, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FloatingModePicker(
                          mode: mode,
                          selectedView: selectedView,
                          onSelected: _selectView,
                          isAnalyzing: isAnalyzing,
                        ),
                        const SizedBox(height: 10),
                        _ChatComposer(
                          mode: mode,
                          controller: _messageController,
                          focusNode: _inputFocusNode,
                          onSend: _sendMessage,
                          onAttach: _pickImages,
                          onInputTap: _collapseFan,
                          isAnalyzing: isAnalyzing,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmIdentity() {
    ref.read(userIdentityProvider.notifier).state = true;
    _showSnackBar('已确认：「我」= 你，「TA」= 对方');
  }
}

class _FloatingTopChrome extends StatelessWidget {
  const _FloatingTopChrome({
    required this.mode,
    required this.startedAt,
    required this.onExportPrompt,
    required this.onSettings,
    required this.isAnalyzing,
  });

  final ModeTheme mode;
  final DateTime startedAt;
  final VoidCallback onExportPrompt;
  final VoidCallback onSettings;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    final start = startedAt;
    final date =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}  '
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        PopupMenuButton<String>(
          tooltip: '菜单',
          onSelected: (value) {
            if (value == 'export') {
              onExportPrompt();
            } else if (value == 'settings') {
              onSettings();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'export',
              child: Text('复制分析包（粘贴到免费 AI 分析）'),
            ),
            PopupMenuItem(value: 'settings', child: Text('设置（占位）')),
          ],
          child: _PillButton(
            mode: mode,
            icon: Icons.menu_rounded,
            label: '设置',
            highlight: isAnalyzing,
          ),
        ),
        const Spacer(),
        _PillButton(
          mode: mode,
          icon: Icons.calendar_today_rounded,
          label: date,
          compact: true,
        ),
      ],
    );
  }
}

class _FloatingModePicker extends StatelessWidget {
  const _FloatingModePicker({
    required this.mode,
    required this.selectedView,
    required this.onSelected,
    required this.isAnalyzing,
  });

  final ModeTheme mode;
  final BattleView selectedView;
  final ValueChanged<BattleView> onSelected;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _FloatModeButton(
          mode: mode,
          label: '为爱',
          selected: selectedView == BattleView.love,
          onTap: () => onSelected(BattleView.love),
          disabled: isAnalyzing,
        ),
        const SizedBox(width: 10),
        _FloatModeButton(
          mode: mode,
          label: '论对错',
          selected: selectedView == BattleView.right,
          onTap: () => onSelected(BattleView.right),
          disabled: isAnalyzing,
        ),
        const SizedBox(width: 10),
        _FloatModeButton(
          mode: mode,
          label: '比输赢',
          selected: selectedView == BattleView.win,
          onTap: () => onSelected(BattleView.win),
          disabled: isAnalyzing,
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.mode,
    required this.icon,
    required this.label,
    this.highlight = false,
    this.compact = false,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final bool highlight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = highlight
        ? scheme.onPrimary
        : scheme.onSurface.withValues(alpha: 0.74);

    return Material(
      color: highlight ? scheme.primary : scheme.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(
          color: (highlight ? scheme.primary : mode.textMuted).withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: InkWell(
        borderRadius: mode.chipRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 9 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatModeButton extends StatelessWidget {
  const _FloatModeButton({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final ModeTheme mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWinMode = mode.view == BattleView.win;
    final foreground = selected
        ? scheme.onPrimary
        : isWinMode
            ? const Color(0xFF6F6F78)
            : scheme.onSurface.withValues(alpha: 0.74);
    final background = selected
        ? scheme.primary
        : isWinMode
            ? const Color(0xFFD6D6DC)
            : scheme.surface.withValues(alpha: 0.92);
    final borderColor = selected
        ? scheme.primary
        : isWinMode
            ? const Color(0xFFBCBCC5)
            : mode.textMuted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: mode.chipRadius,
          side: BorderSide(
            color: borderColor.withValues(alpha: selected ? 0.8 : 0.55),
            width: 1,
          ),
        ),
        elevation: selected ? 5 : 2,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: mode.chipRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius =
        (Theme.of(context).cardTheme.shape as RoundedRectangleBorder?)
            ?.borderRadius ??
        BorderRadius.circular(16);

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '哪边是你？「我」= 你，「TA」= 对方。确认后 AI 会一直记得。',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('确认'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.mode,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    required this.onInputTap,
    this.isAnalyzing = false,
  });

  final ModeTheme mode;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onInputTap;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: mode.inputRadius,
          side: BorderSide(
            color: mode.textMuted.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: mode.inputRadius,
            border: mode.inputBorderWidth > 0
                ? Border.all(
                    color: mode.inputBorderColor,
                    width: mode.inputBorderWidth,
                  )
                : null,
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(
              color: mode.text,
              fontSize: 16,
              fontWeight: mode.view == BattleView.win
                  ? FontWeight.w500
                  : FontWeight.w400,
            ),
            cursorColor: mode.primary,
            textInputAction: TextInputAction.newline,
            onTap: onInputTap,
            decoration: InputDecoration(
              hintText: '上传截图，或把对话贴进来',
              hintStyle: TextStyle(color: mode.textMuted, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
                child: _AttachButton(
                  mode: mode,
                  onPressed: isAnalyzing ? null : onAttach,
                ),
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                child: _SendButton(
                  mode: mode,
                  onPressed: isAnalyzing ? null : onSend,
                ),
              ),
            ),
            onSubmitted: (_) {
              if (!isAnalyzing) onSend();
            },
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.mode, required this.onPressed});

  final ModeTheme mode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.view == BattleView.win
          ? Colors.white
          : onPressed == null
              ? mode.primary.withValues(alpha: 0.38)
              : mode.primary,
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(
          color: mode.view == BattleView.win
              ? Colors.white
              : mode.primary.withValues(alpha: onPressed == null ? 0.4 : 0.8),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: mode.chipRadius,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.photo_library_rounded,
            size: 20,
            color: mode.view == BattleView.win ? Colors.black : mode.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.mode, required this.onPressed});

  final ModeTheme mode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.view == BattleView.win
          ? Colors.white
          : onPressed == null
              ? mode.primary.withValues(alpha: 0.38)
              : mode.primary,
      shape: RoundedRectangleBorder(
        borderRadius: mode.chipRadius,
        side: BorderSide(
          color: mode.view == BattleView.win
              ? Colors.white
              : mode.primary.withValues(alpha: onPressed == null ? 0.4 : 0.8),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: mode.chipRadius,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 20,
            color: mode.view == BattleView.win ? Colors.black : mode.onPrimary,
          ),
        ),
      ),
    );
  }
}
