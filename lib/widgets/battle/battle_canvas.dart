import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../battle_widgets.dart';

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
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      children: [
        BattleVisual(state: state),
        const SizedBox(height: 14),
        Text(
          state.headline,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 14),
        if (messages.isEmpty)
          const _EmptyChatHint()
        else
          ...messages.map((message) => _MessageBubble(message: message)),
        ...state.cards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BattleAnalysisCard(card: card),
          ),
        ),
      ],
    );
  }
}

class BattleVisual extends StatelessWidget {
  const BattleVisual({super.key, required this.state});

  final BattleState state;

  @override
  Widget build(BuildContext context) {
    if (state.view == BattleView.win) return BattleScoreboard(state: state);
    if (state.view == BattleView.right) return JusticeScale(state: state);
    return LoveTree(state: state);
  }
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            '这里是你们的对话空间',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '可以直接粘贴聊天记录，也可以点击加号上传截图。AI 会慢慢了解你们，而不只是分析这一句。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.party == Party.a;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMine ? scheme.primaryContainer : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMine ? 20 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.partyLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(message.content),
          ],
        ),
      ),
    );
  }
}
