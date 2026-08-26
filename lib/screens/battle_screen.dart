import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../repositories/memory_app_repository.dart';
import '../services/prompt_service.dart';
import '../widgets/battle/battle_canvas.dart';

/// 主聊天界面（产品文档 3.1）。
///
/// 打开即此页。输入框 + 三模式切换 + 战场视觉 + 分析留白区。
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runAnalysis();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── 发送文本 ──────────────────────────────────────────────────────────

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

  // ─── 上传截图 ──────────────────────────────────────────────────────────

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

  // ─── 运行分析 ──────────────────────────────────────────────────────────

  Future<void> _runAnalysis() async {
    if (ref.read(isAnalyzingProvider)) return;
    try {
      await ref.read(repositoryActionsProvider).runAnalysis(_conversationId);
    } catch (error) {
      _showError('分析失败，请稍后重试。', error);
    }
  }

  // ─── 切换视角（触发重分析） ────────────────────────────────────────────

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

  // ─── 导出分析包（V1 通道 A，复制到剪贴板） ────────────────────────────

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

  // ─── 构建 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final battleAsync = ref.watch(battleStateProvider);
    final selectedView = ref.watch(selectedBattleViewProvider);
    final messagesAsync = ref.watch(
      conversationMessagesProvider(_conversationId),
    );
    final isAnalyzing = ref.watch(isAnalyzingProvider);
    final identityConfirmed = ref.watch(userIdentityProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            _ChatTopBar(
              onExportPrompt: _exportPrompt,
              isAnalyzing: isAnalyzing,
            ),

            // 主区域
            Expanded(
              child: battleAsync.when(
                data: (battle) => BattleCanvas(
                  state: battle,
                  messages: messagesAsync.valueOrNull ?? const [],
                  scrollController: _scrollController,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('加载失败：$error')),
              ),
            ),

            // 身份确认（首次使用）
            if (!identityConfirmed)
              _IdentityBanner(onConfirm: _confirmIdentity),

            // 模式选择 + 分析中指示
            _ModePicker(
              selectedView: selectedView,
              onSelected: _selectView,
              isAnalyzing: isAnalyzing,
            ),

            // 输入框
            _ChatComposer(
              controller: _messageController,
              onSend: _sendMessage,
              onAttach: _pickImages,
              isAnalyzing: isAnalyzing,
            ),
          ],
        ),
      ),
    );
  }

  void _confirmIdentity() {
    // 默认：用户是 Party.a（我），对方是 Party.b（TA）
    ref.read(userIdentityProvider.notifier).state = true;
    _showSnackBar('已确认：「我」= 你，「TA」= 对方');
  }
}

// ─── 顶栏 ─────────────────────────────────────────────────────────────────

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({required this.onExportPrompt, required this.isAnalyzing});

  final VoidCallback onExportPrompt;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 18, 8),
      child: Row(
        children: [
          // 导出分析包按钮（V1 核心通道）
          IconButton(
            onPressed: onExportPrompt,
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制分析包（粘贴到免费 AI 分析）',
          ),
          const SizedBox(width: 4),
          Text(
            '爱·对·赢',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (isAnalyzing) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const Spacer(),
          Text(
            date,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

// ─── 身份确认横幅 ─────────────────────────────────────────────────────────

class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '哪边是你？「我」= 你，「TA」= 对方。确认后 AI 会一直记得。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onConfirm,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('确认'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 模式选择器 ────────────────────────────────────────────────────────────

class _ModePicker extends StatelessWidget {
  const _ModePicker({
    required this.selectedView,
    required this.onSelected,
    required this.isAnalyzing,
  });

  final BattleView selectedView;
  final ValueChanged<BattleView> onSelected;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          const Spacer(),
          // 三种模式直接切换按钮
          _ViewChip(
            label: '争爱',
            icon: Icons.favorite_outline_rounded,
            selected: selectedView == BattleView.love,
            onTap: () => onSelected(BattleView.love),
            disabled: isAnalyzing,
          ),
          const SizedBox(width: 6),
          _ViewChip(
            label: '争对错',
            icon: Icons.balance_rounded,
            selected: selectedView == BattleView.right,
            onTap: () => onSelected(BattleView.right),
            disabled: isAnalyzing,
          ),
          const SizedBox(width: 6),
          _ViewChip(
            label: '争输赢',
            icon: Icons.sports_kabaddi_rounded,
            selected: selectedView == BattleView.win,
            onTap: () => onSelected(BattleView.win),
            disabled: isAnalyzing,
          ),
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = selected;
    return Material(
      color: isActive ? scheme.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isActive
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? scheme.primary : scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 输入框 ────────────────────────────────────────────────────────────────

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    this.isAnalyzing = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isAnalyzing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: '把对话贴进来，或发一张截图…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: isAnalyzing ? null : onAttach,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: '上传截图',
                ),
                IconButton(
                  onPressed: isAnalyzing ? null : onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: '发送',
                ),
              ],
            ),
          ),
          onSubmitted: (_) => isAnalyzing ? null : onSend(),
        ),
      ),
    );
  }
}
