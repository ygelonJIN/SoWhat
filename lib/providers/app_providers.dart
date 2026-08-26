import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/app_repository.dart';
import '../repositories/memory_app_repository.dart';

final appRepositoryProvider = Provider<MemoryAppRepository>((ref) {
  final repository = MemoryAppRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final casesProvider = StreamProvider<List<Case>>((ref) {
  return ref.watch(appRepositoryProvider).watchCases();
});

final conversationMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, conversationId) {
  return ref.watch(appRepositoryProvider).watchMessages(conversationId);
});

final conversationAnalysesProvider =
    StreamProvider.family<List<Analysis>, String>((ref, conversationId) {
  return ref.watch(appRepositoryProvider).watchAnalyses(conversationId);
});

final memoryProfileProvider = StreamProvider<MemoryProfile>((ref) {
  return ref.watch(appRepositoryProvider).watchMemory();
});

final battleStateProvider = StreamProvider<BattleState>((ref) {
  return ref.watch(appRepositoryProvider).watchBattleState();
});

final selectedBattleViewProvider = StateProvider<BattleView>((ref) {
  return BattleView.love;
});

final repositoryActionsProvider = Provider<AppRepositoryActions>((ref) {
  return AppRepositoryActions(repository: ref.watch(appRepositoryProvider));
});

class AppRepositoryActions {
  const AppRepositoryActions({required this.repository});

  final AppRepository repository;

  Future<void> setBattleView(BattleView view) => repository.setBattleView(view);

  Future<void> addMessage({
    required String conversationId,
    required Party party,
    required String content,
    MessageType type = MessageType.text,
    String? assetPath,
  }) async {
    final sequence = await repository.nextMessageSequence(conversationId);
    await repository.addMessage(
      Message(
        conversationId: conversationId,
        sequence: sequence,
        party: party,
        type: type,
        content: content,
        assetPath: assetPath,
      ),
    );
  }
}
