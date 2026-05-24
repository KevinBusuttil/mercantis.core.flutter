import 'mutation_record.dart';

abstract class CloudAdapter {
  Future<void> push(List<MutationRecord> mutations);
  Future<List<MutationRecord>> pull(String? afterSyncVersion);
  Future<void> acknowledge(List<String> mutationIds);
}

class NoOpCloudAdapter implements CloudAdapter {
  const NoOpCloudAdapter();

  @override
  Future<void> push(List<MutationRecord> mutations) async {}

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async => [];

  @override
  Future<void> acknowledge(List<String> mutationIds) async {}
}
