class FieldDiff {
  final String fieldKey;
  final dynamic oldValue;
  final dynamic newValue;

  const FieldDiff({required this.fieldKey, this.oldValue, this.newValue});

  Map<String, dynamic> toJson() => {
        'fieldKey': fieldKey,
        'oldValue': oldValue,
        'newValue': newValue,
      };

  factory FieldDiff.fromJson(Map<String, dynamic> j) => FieldDiff(
        fieldKey: j['fieldKey'] as String,
        oldValue: j['oldValue'],
        newValue: j['newValue'],
      );
}

class DocumentVersion {
  final String id;
  final String documentId;
  final String docType;
  final int docStatus;
  final String modifiedBy;
  final DateTime modifiedAt;
  final List<FieldDiff> diffs;

  const DocumentVersion({
    required this.id,
    required this.documentId,
    required this.docType,
    required this.docStatus,
    required this.modifiedBy,
    required this.modifiedAt,
    required this.diffs,
  });

  static List<FieldDiff> computeDiff(
    Map<String, dynamic> oldPayload,
    Map<String, dynamic> newPayload,
  ) {
    final diffs = <FieldDiff>[];
    final allKeys = {...oldPayload.keys, ...newPayload.keys};
    for (final key in allKeys) {
      final oldVal = oldPayload[key];
      final newVal = newPayload[key];
      if ('$oldVal' != '$newVal') {
        diffs.add(FieldDiff(fieldKey: key, oldValue: oldVal, newValue: newVal));
      }
    }
    return diffs;
  }
}
