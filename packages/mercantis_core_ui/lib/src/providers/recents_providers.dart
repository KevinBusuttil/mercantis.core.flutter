import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/recents_store.dart';
import 'core_providers.dart';

/// The [RecentsStore] over the shared database.
final recentsStoreProvider = FutureProvider<RecentsStore>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return RecentsStore(db.db);
});

/// The recent records, newest first, plus actions to record/clear them.
///
/// Reading the provider loads the persisted list; [RecentsNotifier.record]
/// appends an open and refreshes, [RecentsNotifier.clear] empties it.
final recentsProvider =
    AsyncNotifierProvider<RecentsNotifier, List<RecentEntry>>(
  RecentsNotifier.new,
);

class RecentsNotifier extends AsyncNotifier<List<RecentEntry>> {
  @override
  Future<List<RecentEntry>> build() async {
    final store = await ref.watch(recentsStoreProvider.future);
    return store.list();
  }

  /// Records [entry] as the most recently opened record and refreshes state.
  Future<void> record(RecentEntry entry) async {
    final store = await ref.read(recentsStoreProvider.future);
    await store.record(entry);
    state = AsyncData(await store.list());
  }

  /// Clears the recent list.
  Future<void> clear() async {
    final store = await ref.read(recentsStoreProvider.future);
    await store.clear();
    state = const AsyncData(<RecentEntry>[]);
  }
}
