import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/mode_theme.dart';
import '../battle_widgets.dart';

/// 聊天主内容区：消息流 + 分析卡片。
///
/// 顶部战场视觉已经移到 `BattleScreen` 的常驻区，这里只保留可滚动内容。
class BattleCanvas extends StatelessWidget {
  const BattleCanvas({
    super.key,
    required this.state,
    required this.messages,
    required this.scrollController,
  });

  final BattleState state;
  final List<Message> messages;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final modeTheme = ModeThemes.of(state.view);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 88, 16, 168),
      children: [
        if (messages.isEmpty)
          _EmptyChatHint(theme: modeTheme)
        else
          ...messages.map(
            (message) => _MessageBubble(message: message, theme: modeTheme),
          ),
        if (messages.isNotEmpty) const SizedBox(height: 6),
        ...state.cards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BattleAnalysisCard(card: card, mode: modeTheme),
          ),
        ),
      ],
    );
  }
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint({required this.theme});

  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: theme.isDark ? 0.95 : 0.75),
        borderRadius: theme.cardRadius,
        border: Border.all(color: theme.textMuted.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.24 : 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 34,
            color: theme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '把对话直接贴进来',
            style: TextStyle(
              color: theme.text,
              fontSize: 15,
              fontWeight: theme.strongWeight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '也可以点右下角加号上传截图。',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.textMuted, height: 1.45, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.theme});

  final Message message;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    final isMine = message.party == Party.a;
    final bubbleColor = switch (theme.view) {
      BattleView.win => isMine ? Colors.white : const Color(0xFF797980),
      BattleView.right => isMine ? const Color(0xFFC9B877) : const Color(0xFFF0E9D2),
      BattleView.love => isMine ? const Color(0xFFDDEAD8) : Colors.white,
    };
    final textColor = switch (theme.view) {
      BattleView.win => isMine ? Colors.black : Colors.white,
      BattleView.right => isMine ? const Color(0xFF241C07) : Colors.black,
      BattleView.love => isMine ? const Color(0xFF2F3A2A) : const Color(0xFF2F3A2A),
    };
    final borderColor = theme.view == BattleView.win
        ? Colors.black.withValues(alpha: 0.18)
        : theme.view == BattleView.right
            ? Colors.white.withValues(alpha: isMine ? 0.28 : 0.16)
            : Colors.transparent;
    final bubbleRadius = theme.view == BattleView.win
        ? BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomLeft: Radius.circular(30),
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(6),
          )
        : theme.view == BattleView.right
            ? BorderRadius.zero
            : theme.cardRadius;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 348),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: bubbleRadius,
          border: Border.all(color: borderColor, width: theme.view == BattleView.win || theme.view == BattleView.right ? 1 : 0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isMine ? 0.07 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.partyLabel,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.68),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 4),
            if (message.isImageType && message.assetPath != null)
              _ImageContent(message: message, textColor: textColor)
            else
              Text(
                message.content,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  height: 1.42,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.message, required this.textColor});

  final Message message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final path = message.assetPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (path != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(path),
              width: 180,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 180,
                height: 120,
                color: Colors.black.withValues(alpha: 0.05),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.black38,
                ),
              ),
            ),
          ),
        if (message.content.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message.content,
            style: TextStyle(
              fontSize: 12.5,
              color: textColor.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}
