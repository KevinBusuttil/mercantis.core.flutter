import '../metadata/sync_policy.dart';
import '../document_engine/document.dart';
import 'mutation_record.dart';

enum ConflictOutcome { acceptRemote, rejectRemote, requiresManualResolution }

class ConflictResolver {
  ConflictOutcome resolve(
    MutationRecord remote,
    Document? local,
    SyncPolicy policy,
  ) {
    switch (policy.conflictResolution) {
      case ConflictResolution.appendOnly:
        return ConflictOutcome.acceptRemote;

      case ConflictResolution.lastWriteWins:
        if (local == null) return ConflictOutcome.acceptRemote;
        final remoteTs = remote.localTimestamp;
        final localTs = local.modifiedAt ?? local.createdAt;
        return remoteTs.isAfter(localTs)
            ? ConflictOutcome.acceptRemote
            : ConflictOutcome.rejectRemote;

      case ConflictResolution.versionCheckedMerge:
        if (local == null) return ConflictOutcome.acceptRemote;
        if (local.syncVersion != null &&
            remote.syncVersion != null &&
            local.syncVersion != remote.syncVersion) {
          return ConflictOutcome.requiresManualResolution;
        }
        return ConflictOutcome.acceptRemote;
    }
  }
}
