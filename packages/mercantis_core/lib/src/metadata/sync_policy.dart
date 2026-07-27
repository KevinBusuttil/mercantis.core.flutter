enum ConflictResolution { lastWriteWins, versionCheckedMerge, appendOnly }

/// How a DocType's documents reconcile concurrent edits across devices.
///
/// The default is [ConflictResolution.versionCheckedMerge]: a remote edit
/// fast-forwards a clean local copy, but when BOTH sides changed the
/// document since the last sync the loser is never silently discarded —
/// the document is flagged and the user chooses keep-mine / take-theirs.
/// [ConflictResolution.lastWriteWins] (opt-in) resolves by wall-clock
/// instead, losing one side's edit; [ConflictResolution.appendOnly] is for
/// derived, immutable streams (ledger rows) that never contend.
class SyncPolicy {
  final ConflictResolution conflictResolution;
  final bool immutableAfterSubmit;

  const SyncPolicy({
    this.conflictResolution = ConflictResolution.versionCheckedMerge,
    this.immutableAfterSubmit = false,
  });

  factory SyncPolicy.fromJson(Map<String, dynamic> json) => SyncPolicy(
        conflictResolution: ConflictResolution.values.firstWhere(
          (r) => r.name == json['conflictResolution'],
          orElse: () => ConflictResolution.versionCheckedMerge,
        ),
        immutableAfterSubmit: (json['immutableAfterSubmit'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'conflictResolution': conflictResolution.name,
        'immutableAfterSubmit': immutableAfterSubmit,
      };
}
