import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/ai_client.dart';
import '../theme/mode_theme.dart';
import '../utils/format.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/feedback/feedback.dart';
import '../widgets/thinking/thinking_panel.dart';
import 'ai_config_screen.dart';

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
  bool _memoryGenerating = false;

  @override
  Widget build(BuildContext context) {
    final mode = ModeThemes.of(ref.watch(selectedBattleViewProvider));
    final memory =
        ref.watch(memoryProfileProvider).valueOrNull ?? MemoryProfile.empty();
    final cases = ref.watch(casesProvider).valueOrNull ?? const <Case>[];
    final existingIds = cases.map((c) => c.id).toSet();

    final entries = memory.entries.where((e) => !e.isDeleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final grouped = <MemoryKind, List<MemoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.kind, () => []).add(entry);
    }

    final hasOverview =
        (memory.userSummary?.isNotEmpty ?? false) ||
        (memory.partnerSummary?.isNotEmpty ?? false) ||
        (memory.relationshipSummary?.isNotEmpty ?? false);

    return Theme(
      data: mode.themeData,
      child: Scaffold(
        backgroundColor: mode.background,
        body: Stack(
          children: [
            Positioned.fill(
            child: ListView(
              // 顶部留白避开浮层标题，底部留白避开渐变遮罩。
              padding: const EdgeInsets.fromLTRB(16, 130, 16, 150),
              children: [
                // 「更新记忆」固定在档案最顶部：空档案时也要能点。
                _UpdateMemoryButton(
                  mode: mode,
                  loading: _memoryGenerating,
                  onTap: () => _runMemoryUpdate(context, mode),
                ),
                if (_memoryStatus != ThinkingStatus.idle) ...[
                  const SizedBox(height: 10),
                  ThinkingPanel(
                    mode: mode,
                    status: _memoryStatus,
                    content: _memoryContent,
                    expanded: _memoryExpanded,
                    startedAt: _memoryStartedAt,
                    onToggle: () =>
                        setState(() => _memoryExpanded = !_memoryExpanded),
                  ),
                ],
                const SizedBox(height: 22),
                if (hasOverview || entries.isNotEmpty) ...[
                  _OverviewCard(mode: mode, memory: memory),
                ] else
                  _MemoryEmptyState(mode: mode),
                const SizedBox(height: 14),
                for (final kind in _kinds)
                  if (grouped[kind] case final list? when list.isNotEmpty) ...[
                    _SectionLabel(mode: mode, kind: kind),
                    const SizedBox(height: 8),
                    ...list.map(
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
          // 顶部渐隐：内容滚动到浮层标题下方时过渡淡出。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 110,
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
            height: 120,
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
    });

    try {
      // 记忆生成与分析共用同一条「流式优先 + 连接失败自动回退」路径，
      // 可靠性和分析一致。输出是较长的 JSON（四份概况 + 增量条目），
      // 取一个能容纳完整输出的 maxTokens 上限。
      final raw = await const AiClient().chatStream(
        config: config,
        system: prompt,
        user: '请按上述要求生成记忆档案，只输出 JSON。',
        maxTokens: 8192,
        onThinking: (delta) {
          if (mounted) setState(() => _memoryContent = delta);
        },
      );
      final result = service.parseResponse(response: raw, cards: cards);
      final updated = memory.copyWith(
        userSummary: result.userSummary ?? memory.userSummary,
        partnerSummary: result.partnerSummary ?? memory.partnerSummary,
        relationshipSummary:
            result.relationshipSummary ?? memory.relationshipSummary,
        growthSummary: result.growthSummary ?? memory.growthSummary,
        entries: [...memory.entries, ...result.entries],
      );
      await repository.saveMemory(updated);
      await repository.markAnalysesProcessed(
        cards.map((c) => c.analysisId).toSet().toList(),
      );
      await repository.finalizeConversationsForMemory(
        involvedConversationIds.toList(),
      );
      if (!context.mounted) return;
      setState(() {
        _memoryGenerating = false;
        _memoryStatus = ThinkingStatus.done;
        _memoryExpanded = false;
      });
      _showMessageDialog(
        context,
        mode,
        icon: Icons.check_circle_rounded,
        title: '记忆已更新',
        body: '已写入 ${result.entries.length} 条档案条目，并重新生成四份档案概况。',
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      setState(() {
        _memoryGenerating = false;
        _memoryStatus = ThinkingStatus.done;
        _memoryExpanded = false;
      });
      _showMessageDialog(
        context,
        mode,
        icon: Icons.error_outline,
        title: '更新失败',
        body: error.message,
      );
    } catch (error) {
      if (!context.mounted) return;
      setState(() {
        _memoryGenerating = false;
        _memoryStatus = ThinkingStatus.done;
        _memoryExpanded = false;
      });
      _showMessageDialog(
        context,
        mode,
        icon: Icons.error_outline,
        title: '更新失败',
        body: '$error',
      );
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
                for (final caseItem in cases)
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
                          child: Text(
                            '${caseItem.displayTitle}  ·  ${formatDate(caseItem.createdAt)} ${formatTime(caseItem.createdAt)}',
                            style: TextStyle(
                              color: mode.cardBody,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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

/// 档案概况区：大标题「档案概况」下方，用两张独立卡片分别展示「你」和「他」；
/// 若有关系状态 / 成长轨迹，再并列一张概况卡。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.mode, required this.memory});

  final ModeTheme mode;
  final MemoryProfile memory;

  @override
  Widget build(BuildContext context) {
    final user = memory.userSummary?.trim() ?? '';
    final partner = memory.partnerSummary?.trim() ?? '';
    final relation = memory.relationshipSummary?.trim() ?? '';
    final growth = memory.growthSummary?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 大标题「档案概况」（AI 生成的综合概况区；下方九板块里的「双方画像」
        // 是另一套增量条目，标题由 AI 契约固定，二者不重复）。
        Row(
          children: [
            Icon(Icons.people_outlined, size: 15, color: mode.primary),
            const SizedBox(width: 6),
            Text(
              '档案概况',
              style: TextStyle(
                color: mode.primary,
                fontSize: 15,
                fontWeight: mode.strongWeight,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (user.isNotEmpty) ...[
          _ProfileCard(mode: mode, label: '你', icon: Icons.person_outline, text: user),
          const SizedBox(height: 12),
        ],
        if (partner.isNotEmpty)
          _ProfileCard(mode: mode, label: '他', icon: Icons.favorite_outline, text: partner),
        if (relation.isNotEmpty || growth.isNotEmpty) ...[
          if (user.isNotEmpty || partner.isNotEmpty) const SizedBox(height: 12),
          _StatusCard(
            mode: mode,
            rows: [
              if (relation.isNotEmpty) ('关系', Icons.favorite_outline, relation),
              if (growth.isNotEmpty) ('成长', Icons.trending_up_outlined, growth),
            ],
          ),
        ],
      ],
    );
  }
}

/// 单张身份画像卡片：「你」/「他」各自独立成卡，头部标签 + 正文。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.text,
  });

  final ModeTheme mode;
  final String label;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      decoration: BoxDecoration(
        color: mode.cardBackground.withValues(alpha: 0.72),
        borderRadius: mode.cardRadius,
        border: Border.all(color: mode.cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: mode.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: mode.primary),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: mode.primary,
                  fontSize: 14,
                  fontWeight: mode.strongWeight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            text,
            style: TextStyle(color: mode.cardBody, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// 概况补充卡：关系状态 / 成长轨迹，各自带小标题（与画像卡并列在「双方画像」下）。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.mode, required this.rows});

  final ModeTheme mode;
  final List<(String, IconData, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      decoration: BoxDecoration(
        color: mode.cardBackground.withValues(alpha: 0.72),
        borderRadius: mode.cardRadius,
        border: Border.all(color: mode.cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                Icon(rows[i].$2, size: 14, color: mode.primary),
                const SizedBox(width: 5),
                Text(
                  rows[i].$1,
                  style: TextStyle(
                    color: mode.primary,
                    fontSize: 12,
                    fontWeight: mode.strongWeight,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              rows[i].$3,
              style: TextStyle(
                color: mode.cardBody,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「更新记忆」主按钮（已接入真实 AI），生成中进入加载态并禁用。
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
      borderRadius: mode.chipRadius,
      child: InkWell(
        borderRadius: mode.chipRadius,
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
                Icon(Icons.auto_awesome_rounded, size: 16, color: foreground),
              const SizedBox(width: 7),
              Text(
                loading ? '正在生成…' : '更新记忆',
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
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

/// 九板块分区标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.mode, required this.kind});

  final ModeTheme mode;
  final MemoryKind kind;

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(kind);
    return Row(
      children: [
        Icon(meta.icon, size: 14, color: mode.textMuted),
        const SizedBox(width: 5),
        Text(
          meta.label,
          style: TextStyle(
            color: mode.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
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
      shape: RoundedRectangleBorder(
        borderRadius: mode.cardRadius,
        side: BorderSide(color: mode.cardBorder, width: 1),
      ),
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
                      entry.summary,
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

/// 空态：还没有记忆档案。
class _MemoryEmptyState extends StatelessWidget {
  const _MemoryEmptyState({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Icon(Icons.auto_stories_outlined, size: 36, color: mode.textMuted),
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
            '完成一次对话分析后，点上方「更新记忆」\n生成你们的记忆档案。',
            textAlign: TextAlign.center,
            style: TextStyle(color: mode.textMuted, fontSize: 12, height: 1.6),
          ),
        ],
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
      child: Container(
        width: 292,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
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
        ),
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
                  shape: RoundedRectangleBorder(borderRadius: mode.chipRadius),
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
