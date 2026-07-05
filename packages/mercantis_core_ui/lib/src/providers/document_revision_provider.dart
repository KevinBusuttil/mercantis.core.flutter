import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A monotonically increasing revision per DocType, bumped whenever a document
/// of that type is created, updated, submitted, cancelled, or deleted.
///
/// This is the app's single "documents changed" seam: cached list views (e.g.
/// [MetadataListView]) `ref.watch` the revision for their DocType so they
/// re-fetch after a mutation, instead of every mutation site having to know
/// about — and reach into — each list provider (which are private to their
/// views). A form calls `bump()` after a successful write; the list re-runs.
///
/// Coarse by design (one counter per DocType, not per filter/query): a stale
/// list is worse than an occasional redundant fetch.
final documentRevisionProvider =
    NotifierProvider.family<DocumentRevisionNotifier, int, String>(
        DocumentRevisionNotifier.new);

class DocumentRevisionNotifier extends FamilyNotifier<int, String> {
  @override
  int build(String docType) => 0;

  /// Signal that a document of this DocType changed, waking any watcher.
  void bump() => state = state + 1;
}
