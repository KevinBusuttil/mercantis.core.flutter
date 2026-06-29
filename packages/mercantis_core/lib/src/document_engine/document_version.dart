import 'document.dart';

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

  /// Computes child-table diffs as flattened [FieldDiff] entries (P0.6), so a
  /// submitted document's line-item edits are captured in version history.
  /// Each changed child cell is recorded with a `tableName[rowIndex].fieldKey`
  /// key; whole-row additions/removals as a `tableName[rowIndex]` entry whose
  /// value carries the row id. Rows are matched by their stable [ChildRow.id]
  /// (not position), so reordering a table is not mistaken for a full rewrite.
  static List<FieldDiff> computeChildDiffs(
    Map<String, List<ChildRow>> oldChildren,
    Map<String, List<ChildRow>> newChildren,
  ) {
    final diffs = <FieldDiff>[];
    final tables = {...oldChildren.keys, ...newChildren.keys}.toList()..sort();
    for (final table in tables) {
      final oldRows = oldChildren[table] ?? const <ChildRow>[];
      final newRows = newChildren[table] ?? const <ChildRow>[];
      final oldById = {for (final r in oldRows) r.id: r};
      final newById = {for (final r in newRows) r.id: r};
      final ids = {...oldById.keys, ...newById.keys}.toList()..sort();
      for (final id in ids) {
        final o = oldById[id];
        final n = newById[id];
        if (o != null && n != null) {
          for (final fd in computeDiff(o.payload, n.payload)) {
            diffs.add(FieldDiff(
              fieldKey: '$table[${n.rowIndex}].${fd.fieldKey}',
              oldValue: fd.oldValue,
              newValue: fd.newValue,
            ));
          }
        } else if (o != null) {
          diffs.add(FieldDiff(
              fieldKey: '$table[${o.rowIndex}]',
              oldValue: 'row:$id',
              newValue: null));
        } else if (n != null) {
          diffs.add(FieldDiff(
              fieldKey: '$table[${n.rowIndex}]',
              oldValue: null,
              newValue: 'row:$id'));
        }
      }
    }
    return diffs;
  }
}
