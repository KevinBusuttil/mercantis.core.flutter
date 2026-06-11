import 'mutation_record.dart';

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
