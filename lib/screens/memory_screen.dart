import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/ai_client.dart';
import '../services/memory_generation_service.dart';
import '../theme/mode_theme.dart';
import '../utils/format.dart';
import 'ai_config_screen.dart';

/// 长期记忆档案页（产品文档第 4 章，主打功能）。
///
/// 全屏独立页面，沿用全局规范「全屏内容 + 浮层控制」：
/// 九板块档案 + 档案概况 + 「更新记忆」按钮（已接入真实 AI）。
/// 记忆不可单独清除；删除对话时可勾选「连同记忆一起删除」。
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ModeThemes.of(ref.watch(selectedBattleViewProvider));
    final memory =
        ref.watch(memoryProfileProvider).valueOrNull ?? MemoryProfile.empty();
    final cases = ref.watch(casesProvider).valueOrNull ?? const <Case>[];
    final existingIds = cases.map((c) => c.id).toSet();

    final entries = memory.entries
        .where((e) => !e.isDeleted)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final grouped = <MemoryKind, List<MemoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.kind, () => []).add(entry);
    }

    final hasOverview = (memory.userSummary?.isNotEmpty ?? false) ||
        (memory.partnerSummary?.isNotEmpty ?? false) ||
        (memory.relationshipSummary?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: mode.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              // 顶部留白避开浮层标题，底部留白避开渐变遮罩。
              padding: const EdgeInsets.fromLTRB(16, 130, 16, 150),
              children: [
                if (hasOverview || entries.isNotEmpty) ...[
                  _OverviewCard(mode: mode, memory: memory),
                ] else
                  _MemoryEmptyState(mode: mode),
                const SizedBox(height: 14),
                // 始终显示：档案为空时也要能点「更新记忆」从分析卡片生成档案。
                _UpdateMemoryButton(
                  mode: mode,
                  onTap: () => _runMemoryUpdate(context, ref, mode),
                ),
                const SizedBox(height: 22),
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
                          onTap: () => _openSource(
                            context,
                            ref,
                            entry,
                            existingIds,
                          ),
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
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_rounded, color: mode.text),
                    ),
                    const SizedBox(width: 2),
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
    );
  }

  /// 点「更新记忆」：把全部未消化分析卡片发给 AI（小米 MiMo），
  /// 增量写入九板块条目并重产出四份概况，成功后把来源分析标记为已消化。
  Future<void> _runMemoryUpdate(
    BuildContext context,
    WidgetRef ref,
    ModeTheme mode,
  ) async {
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
      analysesByConversation[caseItem.id] =
          await repository.watchAnalyses(caseItem.id).first;
    }
    final cards = service.collectUnprocessed(
      cases: cases,
      analysesOf: (conversationId) =>
          analysesByConversation[conversationId] ?? const [],
    );
    if (cards.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有新的分析需要更新，或相关对话已锁定。'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final memory = ref.read(memoryProfileProvider).valueOrNull ??
        MemoryProfile.empty();

    // 先展示本次会被写入的对话，用户确认后才调用模型。
    final involvedConversationIds = cards.map((c) => c.conversationId).toSet();
    final involvedCases = cases
        .where((c) => involvedConversationIds.contains(c.id))
        .toList();
    final shouldContinue = await _confirmMemoryUpdate(
      context,
      mode,
      involvedCases,
    );
    if (!shouldContinue || !context.mounted) return;

    final prompt = service.buildPrompt(memory: memory, cards: cards);

    // 生成中：模态加载框，期间不可关闭。
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialog(mode: mode, count: cards.length),
    );

    try {
      final raw = await const AiClient().chat(
        config: config,
        system: prompt,
        user: '请按上述要求生成记忆档案，只输出 JSON。',
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
      Navigator.of(context).pop(); // 关加载框
      _showMessageDialog(
        context,
        mode,
        icon: Icons.check_circle_outline_rounded,
        title: '记忆已更新',
        body: '已写入 ${result.entries.length} 条档案条目，并重新生成四份档案概况。',
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关加载框
      _showMessageDialog(
        context,
        mode,
        icon: Icons.error_outline_rounded,
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
                        Icon(Icons.chat_bubble_outline, size: 15, color: mode.primary),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${caseItem.displayTitle}  ·  ${formatDate(caseItem.createdAt)} ${formatTime(caseItem.createdAt)}',
                            style: TextStyle(color: mode.cardBody, fontSize: 13),
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
            child: Text('确认更新', style: TextStyle(color: mode.primary, fontWeight: FontWeight.w700)),
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

/// 档案概况卡片：双方画像 + 关系状态概要。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.mode, required this.memory});

  final ModeTheme mode;
  final MemoryProfile memory;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (memory.userSummary?.isNotEmpty ?? false) ('你', memory.userSummary!),
      if (memory.partnerSummary?.isNotEmpty ?? false)
        ('TA', memory.partnerSummary!),
      if (memory.relationshipSummary?.isNotEmpty ?? false)
        ('关系', memory.relationshipSummary!),
      if (memory.growthSummary?.isNotEmpty ?? false)
        ('成长', memory.growthSummary!),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: mode.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    rows[i].$1,
                    style: TextStyle(
                      color: mode.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: TextStyle(
                      color: mode.cardBody,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 「更新记忆」主按钮（已接入真实 AI）。
class _UpdateMemoryButton extends StatelessWidget {
  const _UpdateMemoryButton({required this.mode, required this.onTap});

  final ModeTheme mode;
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: mode.onPrimary),
              const SizedBox(width: 7),
              Text(
                '更新记忆',
                style: TextStyle(
                  color: mode.onPrimary,
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
    final sourceGone = entry.sourceGone ||
        (entry.sources.isNotEmpty &&
            entry.sources.every((s) => !existingIds.contains(s.conversationId)));
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(meta.icon, size: 17, color: mode.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.summary,
                      style: TextStyle(
                        color: mode.cardBody,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (sourceGone) ...[
                          Icon(
                            Icons.delete_outline_rounded,
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
                            Icons.link_rounded,
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
      padding: const EdgeInsets.only(top: 80),
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
            '完成一次对话分析后，点下方「更新记忆」\n生成你们的记忆档案。',
            textAlign: TextAlign.center,
            style: TextStyle(color: mode.textMuted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// 生成中加载框：模态、不可关闭，显示正在处理的卡片数。
class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.mode, required this.count});

  final ModeTheme mode;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 250,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
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
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: mode.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '正在生成记忆…',
              style: TextStyle(
                color: mode.cardTitle,
                fontSize: 14.5,
                fontWeight: mode.strongWeight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '共 $count 张分析卡片，写入九板块并重产出四份概况。',
              textAlign: TextAlign.center,
              style: TextStyle(color: mode.cardMuted, fontSize: 12, height: 1.5),
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
              style: TextStyle(color: mode.cardMuted, fontSize: 12, height: 1.5),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: mode.chipRadius,
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

/// 九板块的标题与图标。
({String label, IconData icon}) _kindMeta(MemoryKind kind) {
  switch (kind) {
    case MemoryKind.profile:
      return (label: '双方画像', icon: Icons.people_outline_rounded);
    case MemoryKind.relationship:
      return (label: '关系状态', icon: Icons.favorite_outline_rounded);
    case MemoryKind.growth:
      return (label: '成长轨迹', icon: Icons.trending_up_rounded);
    case MemoryKind.trigger:
      return (label: '矛盾触发点', icon: Icons.bolt_rounded);
    case MemoryKind.commLib:
      return (label: '有效沟通方式', icon: Icons.forum_outlined);
    case MemoryKind.milestone:
      return (label: '关系里程碑', icon: Icons.star_outline_rounded);
    case MemoryKind.minefield:
      return (label: '雷区清单', icon: Icons.block_rounded);
    case MemoryKind.openIssue:
      return (label: '未解决的问题', icon: Icons.help_outline_rounded);
    case MemoryKind.promise:
      return (label: '承诺跟踪', icon: Icons.event_note_rounded);
  }
}
