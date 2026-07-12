import 'mutation_record.dart';

/// One page of a paginated pull: the mutations plus whether the server holds
/// more past them. `hasMore == true` means pull again with the cursor
/// advanced over this page.
class PullPage {
  const PullPage(this.mutations, {required this.hasMore});

  final List<MutationRecord> mutations;
  final bool hasMore;
}

/// A [CloudAdapter] whose server pages its pull responses (Phase 0.6,
/// gap analysis §8-C9). Callers that know about paging should loop
/// [pullPage] — applying and committing their cursor after every page, so an
/// interrupted bootstrap resumes where it stopped instead of restarting.
/// [CloudAdapter.pull] remains single-page for callers that don't.
abstract class PagedCloudAdapter implements CloudAdapter {
  Future<PullPage> pullPage(String? afterSyncVersion);
}

abstract class CloudAdapter {
  Future<void> push(List<MutationRecord> mutations);
  Future<List<MutationRecord>> pull(String? afterSyncVersion);
  Future<void> acknowledge(List<String> mutationIds);

  /// Content-addressed blob transfer for attachment bytes (ADR-048). Keyed by
  /// the lower-case hex SHA-256 of the bytes, so a push is idempotent and a
  /// pull is independent of the metadata mutation that references it. Adapters
  /// that don't move bytes (e.g. [NoOpCloudAdapter]) leave these as no-ops.
  Future<void> pushBlob(String sha256, List<int> bytes);

  /// Returns the bytes for [sha256], or null if the blob isn't available yet.
  Future<List<int>?> pullBlob(String sha256);

  /// Whether [sha256] is already present in the shared store.
  Future<bool> hasBlob(String sha256);
}

class NoOpCloudAdapter implements CloudAdapter {
  const NoOpCloudAdapter();

  @override
  Future<void> push(List<MutationRecord> mutations) async {}

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async => [];

  @override
  Future<void> acknowledge(List<String> mutationIds) async {}

  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {}

  @override
  Future<List<int>?> pullBlob(String sha256) async => null;

  @override
  Future<bool> hasBlob(String sha256) async => false;
}
