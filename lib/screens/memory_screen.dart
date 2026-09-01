import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/ai_client.dart';
import '../theme/fold_decoration.dart';
import '../theme/mode_theme.dart';
import '../utils/format.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/feedback/feedback.dart';
import '../widgets/thinking/thinking_panel.dart';
import 'ai_config_screen.dart';

/// 内容区顶部/底部留白：避开顶部浮层（返回 + 标题）与底部悬浮条
/// （快捷滑动条 + 更新记忆）。空态垂直居中也按它计算。
const double _kMemoryListTopInset = 130;
const double _kMemoryListBottomInset = 210;

/// 长期记忆档案页（产品文档第 4 章，主打功能）。
///
/// 全屏独立页面，沿用全局规范「全屏内容 + 浮层控制」：
/// 顶部「更新记忆」按钮（已接入真实 AI）→ 生成中显示可折叠思考框 →
/// 档案概况 + 九板块条目。
/// 记忆不可单独清除；删除对话时可勾选「连同记忆一起删除」。
class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  static const _kinds = [
    MemoryKind.profile,
    MemoryKind.relationship,
    MemoryKind.growth,
    MemoryKind.trigger,
    MemoryKind.commLib,
    MemoryKind.milestone,
    MemoryKind.minefield,
    MemoryKind.openIssue,
    MemoryKind.promise,
  ];

  /// 记忆生成中的思考过程（与聊天页思考框同款，可折叠）。
  ThinkingStatus _memoryStatus = ThinkingStatus.idle;
  String _memoryContent = '';
  bool _memoryExpanded = false;
  DateTime? _memoryStartedAt;
  DateTime? _memoryFinishedAt;
  bool _memoryGenerating = false;

  /// 底部「快捷滑动条」是否展开（展示除当前外其他板块的小标题）。
  bool _navExpanded = false;

  /// 内容滚动控制器：跟踪当前浏览到的板块，让快捷滑动条跟随变化。
  final _scrollController = ScrollController();

  /// 各板块标题的定位锚点（按板块 id 缓存，供滚动定位与跳转）。
  final Map<String, GlobalKey> _sectionKeys = {};

  /// 当前浏览到的板块标题（快捷滑动条上显示的小标题）。
  String _currentSection = '';

  /// 本次渲染的板块导航列表（按页面顺序排列）。
  List<({String id, String label, GlobalKey key})> _sections = const [];

  GlobalKey _sectionKey(String id) =>
      _sectionKeys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onMemoryScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedView = ref.watch(selectedBattleViewProvider);
    final mode = ModeThemes.of(selectedView);
    final memory =
        ref.watch(memoryProfileProvider).valueOrNull ?? MemoryProfile.empty();
    final cases = ref.watch(casesProvider).valueOrNull ?? const <Case>[];
    final existingIds = cases.map((c) => c.id).toSet();

    // 按对话时间（来源时间）倒序：同一对话的多条条目聚在一起，最新对话在最上。
    final entries = memory.entries.where((e) => !e.isDeleted).toList()
      ..sort((a, b) {
        final at = a.sources.isEmpty ? a.createdAt : a.sources.first.happenedAt;
        final bt = b.sources.isEmpty ? b.createdAt : b.sources.first.happenedAt;
        return bt.compareTo(at);
      });
    final grouped = <MemoryKind, List<MemoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.kind, () => []).add(entry);
    }

    // 有内容的板块。
    final boards = [
      for (final k in _kinds)
        if ((grouped[k] ?? const <MemoryEntry>[]).isNotEmpty) k,
    ];

    final hasOverview =
        (memory.userSummary?.isNotEmpty ?? false) ||
        (memory.partnerSummary?.isNotEmpty ?? false) ||
        (memory.relationshipSummary?.isNotEmpty ?? false) ||
        (memory.growthSummary?.isNotEmpty ?? false);

    // 板块导航列表：概况四卡 + 有内容的九板块，按页面顺序排列；
    // 快捷滑动条按它来显示当前小标题、展开跳转。
    // 概况 id 用 summary_ 前缀，避免与九板块的 kind.name（如 growth）冲突。
    final userSummary = memory.userSummary?.trim() ?? '';
    final partnerSummary = memory.partnerSummary?.trim() ?? '';
    final relationshipSummary = memory.relationshipSummary?.trim() ?? '';
    final growthSummary = memory.growthSummary?.trim() ?? '';
    _sections = [
      if (hasOverview) ...[
        if (userSummary.isNotEmpty)
          (
            id: 'summary_user',
            label: '我的概况',
            key: _sectionKey('summary_user'),
          ),
        if (partnerSummary.isNotEmpty)
          (
            id: 'summary_partner',
            label: 'TA 的概况',
            key: _sectionKey('summary_partner'),
          ),
        if (relationshipSummary.isNotEmpty)
          (
            id: 'summary_relation',
            label: '关系概况',
            key: _sectionKey('summary_relation'),
          ),
        if (growthSummary.isNotEmpty)
          (
            id: 'summary_growth',
            label: '成长概况',
            key: _sectionKey('summary_growth'),
          ),
      ],
      for (final kind in boards)
        (id: kind.name, label: _kindMeta(kind).label, key: _sectionKey(kind.name)),
    ];
    if (_currentSection.isEmpty ||
        !_sections.any((s) => s.label == _currentSection)) {
      _currentSection = _sections.isEmpty ? '' : _sections.first.label;
    }

    return Theme(
      data: mode.themeData,
      child: Scaffold(
        backgroundColor: mode.background,
        body: Stack(
          children: [
            Positioned.fill(
              // 用 SingleChildScrollView 而非 ListView：ListView 会懒加载卸载
              // 可视区外的子项，KeepAlive 只保证「已挂载过的」孩子不被回收，
              // 从未挂载的远距离板块标题根本拿不到 context，跳转会静默失效。
              // 整树常驻后所有锚点 key 都可用，远距离跳转稳定。
              child: SingleChildScrollView(
                controller: _scrollController,
                // 顶部留白避开浮层标题，底部留白避开底部悬浮条与渐变遮罩。
                padding: EdgeInsets.fromLTRB(
                  16,
                  _kMemoryListTopInset,
                  16,
                  _kMemoryListBottomInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_memoryStatus != ThinkingStatus.idle) ...[
                      ThinkingPanel(
                        mode: mode,
                        status: _memoryStatus,
                        content: _memoryContent,
                        expanded: _memoryExpanded,
                        startedAt: _memoryStartedAt,
                        finishedAt: _memoryFinishedAt,
                        onToggle: () =>
                            setState(() => _memoryExpanded = !_memoryExpanded),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (hasOverview || entries.isNotEmpty) ...[
                      if (hasOverview)
                        _OverviewSection(
                          mode: mode,
                          memory: memory,
                          headingKeys: {
                            'summary_user': _sectionKey('summary_user'),
                            'summary_partner': _sectionKey('summary_partner'),
                            'summary_relation': _sectionKey(
                              'summary_relation',
                            ),
                            'summary_growth': _sectionKey('summary_growth'),
                          },
                        ),
                      // 思考框出现（正在生成 / 生成完成/失败）时不再显示
                      // 空态，避免空态文案被思考框往下推。
                    ] else if (_memoryStatus == ThinkingStatus.idle)
                      _MemoryEmptyState(mode: mode),
                    const SizedBox(height: 22),
                    for (final kind in boards) ...[
                      KeyedSubtree(
                        key: _sectionKey(kind.name),
                        child: _BoardHeader(
                          mode: mode,
                          kind: kind,
                          count: grouped[kind]!.length,
                        ),
                      ),
                      const SizedBox(height: 9),
                      ...grouped[kind]!.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MemoryEntryCard(
                            mode: mode,
                            entry: entry,
                            existingIds: existingIds,
                            onTap: () =>
                                _openSource(context, ref, entry, existingIds),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            // 顶部渐隐：内容滚动到浮层标题下方时过渡淡出。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 130,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        mode.background.withValues(alpha: 1),
                        mode.background.withValues(alpha: 0.9),
                        mode.background.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 底部渐变遮罩。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 160,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        mode.background.withValues(alpha: 1),
                        mode.background.withValues(alpha: 0.85),
                        mode.background.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 底部悬浮条：板块快捷跳转（聊天页模式按钮同款样式）+ 更新记忆，
            // 与聊天页输入区同款布局，悬浮在内容上方。
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_sections.isNotEmpty) ...[
                        // 与聊天页「模式按钮 → 输入框」的间距完全一致。
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _SectionNavigator(
                              mode: mode,
                              currentLabel: _currentSection,
                              expanded: _navExpanded,
                              onToggle: () => setState(
                                () => _navExpanded = !_navExpanded,
                              ),
                              options: [
                                for (final s in _sections)
                                  if (s.label != _currentSection)
                                    (
                                      label: s.label,
                                      onTap: () => _jumpToSection(s.id),
                                    ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _UpdateMemoryButton(
                        mode: mode,
                        loading: _memoryGenerating,
                        onTap: () => _runMemoryUpdate(context, mode),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 顶部浮层：返回 + 标题 + 最近更新。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
                  child: Row(
                    children: [
                      PillButton(
                        mode: mode,
                        icon: Icons.arrow_back_rounded,
                        label: '',
                        highlight: true,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '记忆档案',
                        style: TextStyle(
                          color: mode.text,
                          fontSize: 20,
                          fontWeight: mode.strongWeight,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '共 ${entries.length} 条',
                        style: TextStyle(color: mode.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 滚动时跟踪当前浏览到的板块：标题进入屏幕上方 1/3 即视为当前板块
  /// （此时标题仍可见、未被顶部浮层遮挡），快捷滑动条随之更新。
  void _onMemoryScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final topLine = MediaQuery.sizeOf(context).height / 3;
    String? current;
    for (final s in _sections) {
      final ctx = s.key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      if (box.localToGlobal(Offset.zero).dy <= topLine) {
        current = s.label;
      } else {
        break;
      }
    }
    if (current != null && current != _currentSection) {
      setState(() => _currentSection = current!);
    }
  }

  /// 跳转到指定板块：手动计算目标偏移，让该板块标题停在距屏幕顶部约 18%
  /// 处（避开悬浮的返回栏），再收起展开列表。
  ///
  /// 锚点若尚未布局（如页面刚打开第一帧）会拿不到 RenderObject：
  /// 先等一帧再跳，避免首跳静默失效。
  void _jumpToSection(String id) {
    setState(() => _navExpanded = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ctx = _sectionKeys[id]?.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) return;
      final globalTop = box.localToGlobal(Offset.zero).dy;
      final target =
          globalTop + _scrollController.offset -
          MediaQuery.sizeOf(context).height * 0.18;
      final clamped = target.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 点「更新记忆」：把全部未消化分析卡片发给 AI（小米 MiMo），
  /// 增量写入九板块条目并重产出四份概况，成功后把来源分析标记为已消化。
  /// 生成过程与聊天页一致：页面顶部内嵌可折叠思考框，流式展示 AI 思考。
  Future<void> _runMemoryUpdate(BuildContext context, ModeTheme mode) async {
    if (_memoryGenerating) return;
    final config = ref.read(aiConfigProvider).valueOrNull ?? const AiConfig();
    if (!config.isConfigured) {
      _showMessageDialog(
        context,
        mode,
        icon: Icons.key_off_rounded,
        title: '先配置 API',
        body: '「更新记忆」需要调用 AI。请先到设置页「配置 API」填入小米 MiMo 的 API Key。',
        primaryLabel: '去配置',
        onPrimary: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiConfigScreen()),
          );
        },
      );
      return;
    }

    // 从仓库直接读取（不依赖 provider 缓存），收集未消化卡片（已锁定对话不再参与）。
    final repository = ref.read(appRepositoryProvider);
    final service = ref.read(memoryGenerationServiceProvider);
    final cases = await repository.watchCases().first;
    final analysesByConversation = <String, List<Analysis>>{};
    for (final caseItem in cases) {
      analysesByConversation[caseItem.id] = await repository
          .watchAnalyses(caseItem.id)
          .first;
    }
    final cards = service.collectUnprocessed(
      cases: cases,
      analysesOf: (conversationId) =>
          analysesByConversation[conversationId] ?? const [],
    );
    if (cards.isEmpty) {
      if (!context.mounted) return;
      FeedbackDialog.show(context, mode, message: '没有新的分析需要更新，或相关对话已锁定。');
      return;
    }

    final memory =
        ref.read(memoryProfileProvider).valueOrNull ?? MemoryProfile.empty();

    // 先展示本次会被写入的对话，用户确认后才调用模型。
    final involvedConversationIds = cards.map((c) => c.conversationId).toSet();
    final involvedCases = cases
        .where((c) => involvedConversationIds.contains(c.id))
        .toList();
    if (!context.mounted) return;
    final shouldContinue = await _confirmMemoryUpdate(
      context,
      mode,
      involvedCases,
    );
    if (!shouldContinue || !context.mounted) return;

    final prompt = service.buildPrompt(memory: memory, cards: cards);

    // 生成中：顶部思考框（与聊天页同款），可折叠，期间不可再次触发。
    final startedAt = DateTime.now();
    setState(() {
      _memoryGenerating = true;
      _memoryStatus = ThinkingStatus.thinking;
      _memoryContent = '';
      _memoryExpanded = true;
      _memoryStartedAt = startedAt;
      _memoryFinishedAt = null;
    });

    // 思考过程与聊天页一致：流式增量需要累积拼接，否则思考框只会显示
    // 最后一段增量（看起来只有一行）。
    final thinkingBuffer = StringBuffer();

    /// 失败统一处理：思考框收起到「思考完成」，弹出错误弹窗。
    void showFailure(Object error) {
      if (!context.mounted) return;
      setState(() {
        _memoryGenerating = false;
        _memoryStatus = ThinkingStatus.done;
        _memoryFinishedAt = DateTime.now();
        _memoryExpanded = false;
      });
      _showMessageDialog(
        context,
        mode,
        icon: Icons.error_outline,
        title: '更新失败',
        body: error is FormatException ? error.message : '$error',
      );
    }

    /// 生成 → 解析 → 落库 → 成功弹窗。解析失败会抛 [FormatException]。
    Future<void> generateAndSave(String userMessage) async {
      // 记忆生成与分析共用同一条「流式优先 + 连接失败自动回退」路径，
      // 可靠性和分析一致。输出是较长的 JSON（四份概况 + 增量条目），
      // 取一个能容纳完整输出的 maxTokens 上限。
      final raw = await const AiClient().chatStream(
        config: config,
        system: prompt,
        user: userMessage,
        maxTokens: 8192,
        onThinking: (delta) {
          thinkingBuffer.write(delta);
          if (mounted) {
            setState(() => _memoryContent = thinkingBuffer.toString());
          }
        },
      );
      final result = service.parseResponse(response: raw, cards: cards);
      // 空结果保护：AI 返回合法 JSON 但没有提取到任何内容（entries 为空且
      // 四份概况也全空）时，按失败处理——走重试/报错，绝不落库、绝不把
      // 来源卡片标记为已消化，避免「写入成功但页面空白」的假成功。
      final hasContent =
          result.entries.isNotEmpty ||
          (result.userSummary?.isNotEmpty ?? false) ||
          (result.partnerSummary?.isNotEmpty ?? false) ||
          (result.relationshipSummary?.isNotEmpty ?? false) ||
          (result.growthSummary?.isNotEmpty ?? false);
      if (!hasContent) {
        throw const FormatException(
          'AI 没有返回可用的记忆内容（JSON 结构或字段名可能不符）。请重试。',
        );
      }
      final updated = memory.copyWith(
        userSummary: result.userSummary ?? memory.userSummary,
        partnerSummary: result.partnerSummary ?? memory.partnerSummary,
        relationshipSummary:
            result.relationshipSummary ?? memory.relationshipSummary,
        growthSummary: result.growthSummary ?? memory.growthSummary,
        entries: [...memory.entries, ...result.entries],
      );
      // 写档案 + 标记卡片已消化 + 锁定对话在仓库层同一事务内完成，
      // 任一步失败整体回滚，不会出现半成功状态。
      await repository.saveMemoryWithProcessing(
        memory: updated,
        analysisIds: cards.map((c) => c.analysisId).toSet().toList(),
        conversationIds: involvedConversationIds.toList(),
      );
      if (!context.mounted) return;
      setState(() {
        _memoryGenerating = false;
        _memoryStatus = ThinkingStatus.done;
        _memoryFinishedAt = DateTime.now();
        _memoryExpanded = false;
      });
      _showMessageDialog(
        context,
        mode,
        icon: Icons.check_circle_rounded,
        title: '记忆已更新',
        body: '已写入 ${result.entries.length} 条档案条目，并重新生成四份档案概况。',
      );
    }

    try {
      await generateAndSave('请按上述要求生成记忆档案，只输出 JSON。');
    } on FormatException catch (firstError) {
      // 首次输出可能超长被截断（四份概况 + 增量条目超出输出上限）：
      // 用「精简输出」提示自动重试一次。解析失败发生在保存之前，
      // 重试不会造成重复写入。
      if (!context.mounted) return;
      setState(() {
        _memoryStatus = ThinkingStatus.thinking;
        _memoryFinishedAt = null;
        _memoryExpanded = true;
      });
      try {
        await generateAndSave(
          '上次生成的 JSON 不完整（可能被截断）。请重新生成，务必精简输出：'
          '四份概况分点压缩到最短、条目一句话一条，确保 JSON 完整闭合、不超过输出上限。'
          '只输出 JSON。',
        );
      } on FormatException catch (_) {
        showFailure(firstError);
      } catch (error) {
        showFailure(error);
      }
    } catch (error) {
      showFailure(error);
    }
  }

  Future<bool> _confirmMemoryUpdate(
    BuildContext context,
    ModeTheme mode,
    List<Case> cases,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: mode.cardBackground,
        title: Text('确认更新长期记忆', style: TextStyle(color: mode.cardTitle)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本次将使用以下未归档对话中已有的全部模式分析卡片，统一生成长期记忆。成功后这些对话将被锁定，不再重复更新。',
                  style: TextStyle(color: mode.cardBody, height: 1.5),
                ),
                const SizedBox(height: 14),
                for (final caseItem in cases) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 15,
                          color: mode.primary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _ConversationLabelText(
                            caseItem: caseItem,
                            mode: mode,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: mode.cardMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '确认更新',
              style: TextStyle(
                color: mode.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 主题化信息弹窗（成功 / 失败 / 引导提示共用）。
  void _showMessageDialog(
    BuildContext context,
    ModeTheme mode, {
    required IconData icon,
    required String title,
    required String body,
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _MessageDialog(
        mode: mode,
        icon: icon,
        title: title,
        body: body,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
      ),
    );
  }

  void _openSource(
    BuildContext context,
    WidgetRef ref,
    MemoryEntry entry,
    Set<String> existingIds,
  ) {
    final alive = entry.sources
        .where((s) => existingIds.contains(s.conversationId))
        .toList();
    if (alive.isEmpty) return;
    ref.read(selectedConversationIdProvider.notifier).state =
        alive.first.conversationId;
    Navigator.of(context).pop();
  }
}

/// 档案概况区：四张概况卡（我的概况 / TA 的概况 / 关系概况 / 成长概况），
/// 卡内首行是带主题色下划线的标题 + 正文。
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.mode,
    required this.memory,
    required this.headingKeys,
  });

  final ModeTheme mode;
  final MemoryProfile memory;

  /// 各概况卡的滚动定位锚点（快捷滑动条跳转用）。
  final Map<String, GlobalKey> headingKeys;

  @override
  Widget build(BuildContext context) {
    final user = memory.userSummary?.trim() ?? '';
    final partner = memory.partnerSummary?.trim() ?? '';
    final relation = memory.relationshipSummary?.trim() ?? '';
    final growth = memory.growthSummary?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (user.isNotEmpty) ...[
          KeyedSubtree(
            key: headingKeys['summary_user'],
            child: _OverviewSummaryCard(
              mode: mode,
              icon: Icons.person_outline,
              label: '我的概况',
              text: user,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (partner.isNotEmpty) ...[
          KeyedSubtree(
            key: headingKeys['summary_partner'],
            child: _OverviewSummaryCard(
              mode: mode,
              icon: Icons.favorite_outline,
              label: 'TA 的概况',
              text: partner,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (relation.isNotEmpty) ...[
          KeyedSubtree(
            key: headingKeys['summary_relation'],
            child: _OverviewSummaryCard(
              mode: mode,
              icon: Icons.favorite_border,
              label: '关系概况',
              text: relation,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (growth.isNotEmpty)
          KeyedSubtree(
            key: headingKeys['summary_growth'],
            child: _OverviewSummaryCard(
              mode: mode,
              icon: Icons.trending_up_outlined,
              label: '成长概况',
              text: growth,
            ),
          ),
      ],
    );
  }
}

/// 概况卡 / 板块共用的标题：小图标 + 主色大字，文字下方一条等长粗主色下划线。
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.mode,
    required this.icon,
    required this.label,
    this.trailing,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: mode.primary),
        const SizedBox(width: 7),
        // IntrinsicWidth 让横线宽度精确等于文字的排版宽度（含字距）。
        IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: mode.primary,
                  fontSize: 20,
                  fontWeight: mode.strongWeight,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: mode.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// 概况卡：二级标题直接嵌在卡片文本块的第一行，其下为正文。
class _OverviewSummaryCard extends StatelessWidget {
  const _OverviewSummaryCard({
    required this.mode,
    required this.icon,
    required this.label,
    required this.text,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return CutBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      fold: mode.cornerFold,
      color: mode.cardBackground,
      borderRadius: mode.cardRadius,
      border: Border.all(color: mode.cardBorder, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: mode.cardShadowAlpha),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(mode: mode, icon: icon, label: label),
          const SizedBox(height: 12),
          Text(
            cleanMemoryText(text),
            style: TextStyle(color: mode.cardBody, fontSize: 13.5, height: 1.7),
          ),
        ],
      ),
    );
  }
}

/// 「更新记忆」主按钮（已接入真实 AI）：主色填充的记忆按钮样式，
/// 通栏宽度与聊天页输入框同尺寸，生成中进入加载态并禁用。
class _UpdateMemoryButton extends StatelessWidget {
  const _UpdateMemoryButton({
    required this.mode,
    required this.onTap,
    this.loading = false,
  });

  final ModeTheme mode;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = loading
        ? mode.onPrimary.withValues(alpha: 0.85)
        : mode.onPrimary;
    return Material(
      color: loading ? mode.primary.withValues(alpha: 0.7) : mode.primary,
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
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(Icons.auto_awesome_rounded, size: 17, color: foreground),
              const SizedBox(width: 7),
              Text(
                loading ? '正在生成…' : '更新记忆',
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
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

/// 底部悬浮的「快捷滑动条」：按钮显示当前浏览到的板块小标题，与聊天页
/// 当前模式按钮完全同款。点击按钮本体（即当前板块的名字）向上展开其他
/// 板块的小标题；点选某个板块后平滑滚动到该位置并收起，按钮随之显示新
/// 板块名。展开动效与聊天页模式展开保持同款。
class _SectionNavigator extends StatelessWidget {
  const _SectionNavigator({
    required this.mode,
    required this.currentLabel,
    required this.expanded,
    required this.onToggle,
    required this.options,
  });

  final ModeTheme mode;
  final String currentLabel;
  final bool expanded;
  final VoidCallback onToggle;

  /// 展开后展示的其他板块（已排除当前板块）。
  final List<({String label, VoidCallback onTap})> options;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      // 与聊天页模式展开动画保持同一款：向上展开、220ms 缓出。
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (expanded) ...[
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _SectionOptionButton(
                mode: mode,
                label: options[i].label,
                onTap: options[i].onTap,
              ),
            ],
            const SizedBox(height: 12),
          ],
          PillButton(
            mode: mode,
            icon: Icons.unfold_more_rounded,
            label: currentLabel,
            highlight: true,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }
}

/// 展开态单个板块选项：与聊天页模式选项同款（未选中描边胶囊样式）。
class _SectionOptionButton extends StatelessWidget {
  const _SectionOptionButton({
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
      color: mode.chipBackground,
      shape: FoldShape(
        borderRadius: mode.chipRadius,
        side: BorderSide(
          color: mode.chipBorder.withValues(alpha: 0.55),
          width: 1,
        ),
        fold: mode.cornerFold,
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.16),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: mode.chipForeground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 板块标题：与概况标题同款（主色大字 + 主题色下划线），独立在板块上方。
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.mode,
    required this.kind,
    required this.count,
  });

  final ModeTheme mode;
  final MemoryKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(kind);
    return _SectionHeading(
      mode: mode,
      icon: meta.icon,
      label: meta.label,
      trailing: Text(
        '$count 条',
        style: TextStyle(color: mode.textMuted, fontSize: 12),
      ),
    );
  }
}

/// 单条记忆卡片：板块图标 + 内容 + 出处（可跳回源对话），源已删时标记。
class _MemoryEntryCard extends StatelessWidget {
  const _MemoryEntryCard({
    required this.mode,
    required this.entry,
    required this.existingIds,
    required this.onTap,
  });

  final ModeTheme mode;
  final MemoryEntry entry;
  final Set<String> existingIds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(entry.kind);
    final sourceGone =
        entry.sourceGone ||
        (entry.sources.isNotEmpty &&
            entry.sources.every(
              (s) => !existingIds.contains(s.conversationId),
            ));
    final first = entry.sources.isNotEmpty ? entry.sources.first : null;

    return Material(
      color: mode.cardBackground,
      shape: FoldShape(
        borderRadius: mode.cardRadius,
        side: BorderSide(color: mode.cardBorder, width: 1),
        fold: mode.cornerFold,
      ),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: mode.cardShadowAlpha),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.sources.isEmpty ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 与分析卡片同语言的板块图标瓷片，让条目卡片更精致、可识别。
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: mode.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(meta.icon, size: 15, color: mode.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cleanMemoryText(entry.summary),
                      style: TextStyle(
                        color: mode.cardBody,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    if (sourceGone || first != null) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: mode.cardBorder.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sourceGone) ...[
                            Icon(
                              Icons.delete_outlined,
                              size: 12,
                              color: mode.cardMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '源记录已删除',
                              style: TextStyle(
                                color: mode.cardMuted,
                                fontSize: 11,
                              ),
                            ),
                          ] else if (first != null) ...[
                            Icon(
                              Icons.link_outlined,
                              size: 12,
                              color: mode.cardMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _sourceLabel(first),
                              style: TextStyle(
                                color: mode.cardMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(MemorySourceRef source) {
    final date = formatDate(source.happenedAt);
    final time = formatTime(source.happenedAt);
    return '出处：$date $time';
  }
}

/// 对话标签：有自定义名称显示「名称 · 日期 时间」，未命名只显示「日期 时间」
/// （命名不是必填，不再用「未命名对话」占位）。
class _ConversationLabelText extends StatelessWidget {
  const _ConversationLabelText({required this.caseItem, required this.mode});

  final Case caseItem;
  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    final title = caseItem.title?.trim() ?? '';
    final dateTime =
        '${formatDate(caseItem.createdAt)} ${formatTime(caseItem.createdAt)}';
    return Text(
      title.isEmpty ? dateTime : '$title  ·  $dateTime',
      style: TextStyle(color: mode.cardBody, fontSize: 13),
    );
  }
}

/// 空态：还没有记忆档案。内容在可视区水平 + 垂直居中。
class _MemoryEmptyState extends StatelessWidget {
  const _MemoryEmptyState({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    // 与 ListView 顶部/底部留白对应的可视区高度，让空态整体垂直居中。
    final visibleHeight = (MediaQuery.sizeOf(context).height -
            _kMemoryListTopInset -
            _kMemoryListBottomInset)
        .clamp(0.0, double.infinity);
    return SizedBox(
      height: visibleHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 36,
              color: mode.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有记忆档案',
              style: TextStyle(
                color: mode.text,
                fontSize: 15,
                fontWeight: mode.strongWeight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '完成一次对话分析后，点下方「更新记忆」\n生成你们的记忆档案。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mode.textMuted,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主题化信息弹窗：图标 + 标题 + 正文 + 主按钮（默认「知道了」关闭）。
class _MessageDialog extends StatelessWidget {
  const _MessageDialog({
    required this.mode,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
  });

  final ModeTheme mode;
  final IconData icon;
  final String title;
  final String body;

  /// 主按钮文案；为空时默认「知道了」（仅关闭）。
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: mode.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: mode.primary),
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
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                color: mode.cardMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onPrimary ?? () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: FoldShape(
                    borderRadius: mode.chipRadius,
                    fold: mode.cornerFold,
                  ),
                ),
                child: Text(
                  primaryLabel ?? '知道了',
                  style: TextStyle(
                    color: mode.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 九板块的标题与图标（区块标签统一 outlined 线性风格）。
({String label, IconData icon}) _kindMeta(MemoryKind kind) {
  switch (kind) {
    case MemoryKind.profile:
      return (label: '双方画像', icon: Icons.people_outlined);
    case MemoryKind.relationship:
      return (label: '关系状态', icon: Icons.favorite_outline);
    case MemoryKind.growth:
      return (label: '成长轨迹', icon: Icons.trending_up_outlined);
    case MemoryKind.trigger:
      return (label: '矛盾触发点', icon: Icons.bolt_outlined);
    case MemoryKind.commLib:
      return (label: '有效沟通方式', icon: Icons.forum_outlined);
    case MemoryKind.milestone:
      return (label: '关系里程碑', icon: Icons.star_outline);
    case MemoryKind.minefield:
      return (label: '雷区清单', icon: Icons.block_outlined);
    case MemoryKind.openIssue:
      return (label: '未解决的问题', icon: Icons.help_outline);
    case MemoryKind.promise:
      return (label: '承诺跟踪', icon: Icons.event_note_outlined);
  }
}
