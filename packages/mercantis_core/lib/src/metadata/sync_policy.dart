enum ConflictResolution { lastWriteWins, versionCheckedMerge, appendOnly }

class SyncPolicy {
  final ConflictResolution conflictResolution;
  final bool immutableAfterSubmit;

  const SyncPolicy({
    this.conflictResolution = ConflictResolution.lastWriteWins,
    this.immutableAfterSubmit = false,
  });

  factory SyncPolicy.fromJson(Map<String, dynamic> json) => SyncPolicy(
        conflictResolution: ConflictResolution.values.firstWhere(
          (r) => r.name == json['conflictResolution'],
          orElse: () => ConflictResolution.lastWriteWins,
        ),
        immutableAfterSubmit: (json['immutableAfterSubmit'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'conflictResolution': conflictResolution.name,
        'immutableAfterSubmit': immutableAfterSubmit,
      };
}
