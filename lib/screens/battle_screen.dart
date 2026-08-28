import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../screens/memory_screen.dart';
import '../theme/mode_theme.dart';
import '../utils/format.dart';
import '../widgets/battle/battle_canvas.dart';
import '../widgets/battle/image_fan_gallery.dart';
import '../widgets/buttons/float_mode_button.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/input/chat_composer.dart';
import '../widgets/settings/settings_panel.dart';

/// 主聊天界面（产品文档 3.1）。
///
/// 「全屏聊天 + 浮层控制」：顶部设置/日期、模式切换、输入框都悬浮在聊天
/// 内容上方。点左上角「设置」后整页右移，只留原本左侧 1/4 可见，左侧 3/4
/// 展开设置页（搜索框 / 新建对话 / 聊天记录）。
class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  final _fanGalleryKey = GlobalKey<ImageFanGalleryState>();
  final _inputFocusNode = FocusNode();
  bool _isFanPeeked = false;
  bool _keyboardVisible = false;
  bool _settingsOpen = false;

  /// 暂存的待发送图片（选图后先挂在这里，点「发送」才写入对话并发给模型）。
  final List<String> _stagedImages = [];

  /// 当前打开的对话 id（设置页切换对话 / 新建对话时变化）。
  String get _conversationId => ref.read(selectedConversationIdProvider);

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_handleInputFocusChanged);
    // 打开时只恢复该对话保存的模式，不自动触发思考。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreConversationMode(_conversationId);
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

  // ─── 设置页（左侧 3/4 面板） ───────────────────────────────────────────────

  void _openSettings() {
    if (_settingsOpen) return;
    FocusScope.of(context).unfocus();
    _collapseFan();
    setState(() => _settingsOpen = true);
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    FocusScope.of(context).unfocus();
    setState(() => _settingsOpen = false);
  }

  // ─── 记忆档案（独立全屏页） ───────────────────────────────────────────────

  void _openMemory() {
    FocusScope.of(context).unfocus();
    _collapseFan();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MemoryScreen()),
    );
  }

  Future<void> _createNewConversation() async {
    try {
      final caseItem = await ref
          .read(repositoryActionsProvider)
          .createConversation();
      ref.read(selectedConversationIdProvider.notifier).state = caseItem.id;
      _closeSettings();
    } catch (e, st) {
      // 透出真实错误，定位数据库初始化失败原因
      // ignore: avoid_print
      print('[BattleScreen] _createNewConversation error: $e\n$st');
      _showError('新建对话失败：$e');
    }
  }

  void _selectConversation(String conversationId) {
    if (conversationId == _conversationId) {
      _closeSettings();
      return;
    }
    ref.read(selectedConversationIdProvider.notifier).state = conversationId;
    _closeSettings();
  }

  void _onConversationChanged() {
    FocusScope.of(context).unfocus();
    _collapseFan();
    // 切换对话：直接停止上一个对话正在进行的分析，不再自动触发新分析。
    ref.read(repositoryActionsProvider).cancelCurrentAnalysis();
    if (_stagedImages.isNotEmpty) {
      setState(() => _stagedImages.clear());
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _restoreConversationMode(_conversationId);
  }

  /// 每个对话隔离：切换到某段对话时，恢复它自己保存的模式（为爱 / 论对错 / 比输赢）。
  Future<void> _restoreConversationMode(String conversationId) async {
    try {
      final cases = await ref.read(casesProvider.future);
      Case? caseItem;
      for (final item in cases) {
        if (item.id == conversationId) {
          caseItem = item;
          break;
        }
      }
      if (!mounted) return;
      if (ref.read(selectedConversationIdProvider) != conversationId) return;
      if (caseItem != null) {
        ref.read(selectedBattleViewProvider.notifier).state = caseItem.lastView;
        ref.read(repositoryActionsProvider).syncThinkingToView(
          conversationId,
          caseItem.lastView,
        );
      }
    } catch (_) {
      // 读取失败保持当前模式即可。
    }
  }

  // ─── 对话操作 ───────────────────────────────────────────────────────────────

  /// 清除暂存的图片（点扇面展开后的 ✕）；尚未发送，不触碰对话数据。
  void _clearStagedImages() {
    _collapseFan();
    if (_stagedImages.isEmpty) return;
    setState(() => _stagedImages.clear());
    ref.read(debugStatusProvider.notifier).state = '已清除暂存图片';
  }

  /// 发送：文字 + 暂存图片一起写入对话，并触发分析（图片此时才真正发给模型）。
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final hasImages = _stagedImages.isNotEmpty;
    if (text.isEmpty && !hasImages) return;
    try {
      // 允许并行分析：不再先取消上一轮分析。
      ref.read(debugStatusProvider.notifier).state =
          hasImages ? '发送文字 + ${_stagedImages.length} 张图片…' : '发送消息并触发分析…';
      if (text.isNotEmpty) {
        await ref
            .read(repositoryActionsProvider)
            .addMessage(
              conversationId: _conversationId,
              party: Party.a,
              content: text,
            );
      }
      for (var i = 0; i < _stagedImages.length; i++) {
        await ref
            .read(repositoryActionsProvider)
            .addMessage(
              conversationId: _conversationId,
              party: Party.a,
              type: MessageType.image,
              content: '截图 ${i + 1}',
              assetPath: _stagedImages[i],
            );
      }
      _messageController.clear();
      setState(() => _stagedImages.clear());
      await _runAnalysis();
      _scrollToBottom();
    } catch (_) {
      _showError('发送失败，请稍后重试。');
    }
  }

  /// 选图：只暂存，不写入对话、不触发分析；点「发送」才会发出。
  Future<void> _pickImages() async {
    if (ref.read(isAnalyzingProvider)) return;
    try {
      ref.read(debugStatusProvider.notifier).state = '正在选择图片…';
      final images = await _imagePicker.pickMultiImage();
      if (images.isEmpty) {
        ref.read(debugStatusProvider.notifier).state = '未选择图片';
        return;
      }
      final existing = _stagedImages.toSet();
      final added = images
          .map((image) => image.path)
          .where((path) => existing.add(path))
          .toList();
      setState(() => _stagedImages.addAll(added));
      ref.read(debugStatusProvider.notifier).state =
          '已暂存 ${_stagedImages.length} 张图片，点「发送」才真正发出';
    } catch (error) {
      _showError('截图导入失败，请检查相册权限。', error);
    }
  }

  Future<void> _runAnalysis() async {
    ref.read(debugStatusProvider.notifier).state = '正在准备分析…';
    try {
      final turnId = DateTime.now().millisecondsSinceEpoch.toString();
      await ref.read(repositoryActionsProvider).runAnalysis(_conversationId, turnId: turnId);
    } catch (error) {
      ref.read(debugStatusProvider.notifier).state = '分析失败：$error';
      _showError('分析失败，请稍后重试。', error);
    }
  }

  Future<void> _selectView(BattleView view) async {
    if (view == ref.read(selectedBattleViewProvider)) return;
    ref.read(selectedBattleViewProvider.notifier).state = view;
    ref.read(repositoryActionsProvider).syncThinkingToView(_conversationId, view);
    try {
      await ref
          .read(repositoryActionsProvider)
          .setBattleView(_conversationId, view);
    } catch (error) {
      _showError('切换视角失败，请稍后重试。', error);
    }
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

  // ─── 界面 ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedView = ref.watch(selectedBattleViewProvider);
    final battleAsync = ref.watch(
      battleStateProvider((conversationId: _conversationId, view: selectedView)),
    );
    final conversationId = ref.watch(selectedConversationIdProvider);
    final messagesAsync = ref.watch(conversationMessagesProvider(conversationId));
    final isAnalyzing = ref.watch(isAnalyzingProvider);
    final conversationStartedAt =
        ref.watch(conversationStartedAtProvider(conversationId)).valueOrNull ??
        DateTime.now();

    ref.listen(selectedConversationIdProvider, (previous, next) {
      if (previous == next) return;
      _onConversationChanged();
    });

    final mode = ModeThemes.of(selectedView);
    final messages = messagesAsync.valueOrNull ?? const [];
    // 扇面展示的是「暂存的待发送图片」；发送后图片进入对话历史，扇面收起。
    final screenshotPaths = List<String>.unmodifiable(_stagedImages);

    return Theme(
      data: mode.themeData,
      child: PopScope(
        canPop: !_settingsOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _settingsOpen) _closeSettings();
        },
        child: Scaffold(
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: mode.isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final settingsWidth = width * 0.75;

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // 聊天主内容：设置展开时右移 75%，仅左侧 1/4 可见。
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      left: _settingsOpen ? settingsWidth : 0,
                      top: 0,
                      bottom: 0,
                      width: width,
                      child: _buildBattleBody(
                        mode: mode,
                        selectedView: selectedView,
                        battleState:
                            battleAsync.valueOrNull ??
                            BattleState.initial(selectedView),
                        messages: messages,
                        screenshotPaths: screenshotPaths,
                        isAnalyzing: isAnalyzing,
                        conversationStartedAt: conversationStartedAt,
                      ),
                    ),
                    // 遮罩：盖住可见的聊天区，点击收起设置。
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_settingsOpen,
                        child: AnimatedOpacity(
                          opacity: _settingsOpen ? 1 : 0,
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutCubic,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeSettings,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.26),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 设置页（左侧 3/4），从左侧滑入。
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      left: _settingsOpen ? 0 : -settingsWidth,
                      top: 0,
                      bottom: 0,
                      width: settingsWidth,
                      child: SettingsPanel(
                        mode: mode,
                        onClose: _closeSettings,
                        onNewConversation: _createNewConversation,
                        onSelectConversation: _selectConversation,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 聊天主内容（全屏聊天 + 浮层控制）的完整布局。
  Widget _buildBattleBody({
    required ModeTheme mode,
    required BattleView selectedView,
    required BattleState battleState,
    required List<Message> messages,
    required List<String> screenshotPaths,
    required bool isAnalyzing,
    required DateTime conversationStartedAt,
  }) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: mode.background)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboardFromCanvas,
            child: BattleCanvas(
              state: battleState,
              messages: messages,
              mode: mode,
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
                    onSettings: _openSettings,
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
                        onRemove: _clearStagedImages,
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PillButton(
                        mode: mode,
                        icon: Icons.auto_stories_rounded,
                        label: '记忆',
                        highlight: true,
                        onTap: _openMemory,
                      ),
                    ),
                  ),
                  _FloatingModePicker(
                    mode: mode,
                    selectedView: selectedView,
                    onSelected: _selectView,
                  ),
                  const SizedBox(height: 8),
                  // 调试状态栏：实时显示当前正在干什么（测试用，可移除）。
                  _DebugStatusBar(mode: mode),
                  const SizedBox(height: 6),
                  ChatComposer(
                    mode: mode,
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    onSend: _sendMessage,
                    onAttach: _pickImages,
                    onInputTap: _collapseFan,
                    isAnalyzing: isAnalyzing,
                    pendingCount: _stagedImages.length,
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

/// 浮动顶栏：左上角「设置」按钮（直接展开设置页，样式跟随当前选中的模式按钮），
/// 右上角本次对话开始时间。
class _FloatingTopChrome extends StatelessWidget {
  const _FloatingTopChrome({
    required this.mode,
    required this.startedAt,
    required this.onSettings,
  });

  final ModeTheme mode;
  final DateTime startedAt;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final start = startedAt;
    final date = '${formatDate(start)}  ${formatTime(start)}';

    return Row(
      children: [
        PillButton(
          mode: mode,
          icon: Icons.menu_rounded,
          label: '设置',
          highlight: true,
          onTap: onSettings,
        ),
        const Spacer(),
        PillButton(
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
  });

  final ModeTheme mode;
  final BattleView selectedView;
  final ValueChanged<BattleView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatModeButton(
          mode: mode,
          label: '为爱',
          selected: selectedView == BattleView.love,
          onTap: () => onSelected(BattleView.love),
        ),
        const SizedBox(width: 10),
        FloatModeButton(
          mode: mode,
          label: '论对错',
          selected: selectedView == BattleView.right,
          onTap: () => onSelected(BattleView.right),
        ),
        const SizedBox(width: 10),
        FloatModeButton(
          mode: mode,
          label: '比输赢',
          selected: selectedView == BattleView.win,
          onTap: () => onSelected(BattleView.win),
        ),
      ],
    );
  }
}

/// 调试状态栏：实时显示当前正在干什么（[debugStatusProvider]），
/// 空闲时显示「就绪」；测试用，正式版可移除。
class _DebugStatusBar extends ConsumerWidget {
  const _DebugStatusBar({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(debugStatusProvider);
    final idle = status.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: idle ? mode.textMuted : mode.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              idle ? '[调试] 就绪' : '[调试] $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: idle ? mode.textMuted.withValues(alpha: 0.6) : mode.textMuted,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
