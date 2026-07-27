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
        // Manual resolution ONLY when both sides actually changed the
        // document: the local copy carries edits that have not shipped
        // (sync_state local/pushing — the push marks documents synced on
        // success) or is already flagged conflicted (a newer remote
        // candidate replaces the stored one). A clean local copy means
        // the remote edit is a plain fast-forward and applies silently —
        // comparing versions here would flag every ordinary update, which
        // is why this policy was previously unusable.
        if (local == null) return ConflictOutcome.acceptRemote;
        if (local.syncState == SyncState.synced) {
          return ConflictOutcome.acceptRemote;
        }
        return ConflictOutcome.requiresManualResolution;
    }
  }
}
