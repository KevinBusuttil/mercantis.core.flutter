import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/field_definition.dart';

/// An end-user-authored field layered on top of a base DocType.
///
/// Persisted in the `custom_fields` table. Composed into a `ResolvedMeta`
/// by `MetaComposer.resolve(...)` so the field appears on every form /
/// list for its DocType, without mutating the manifest-declared schema.
class CustomField {
  final String id;
  final String docTypeId;
  final FieldDefinition fieldDefinition;

  /// The field key this custom field should be placed AFTER on the form.
  /// `null` (or empty) means "append at the end of the form" — the v1
  /// behaviour, preserved as the default for backwards compatibility.
  final String? insertAfter;

  const CustomField({
    required this.id,
    required this.docTypeId,
    required this.fieldDefinition,
    this.insertAfter,
  });

  CustomField copyWith({
    String? id,
    String? docTypeId,
    FieldDefinition? fieldDefinition,
    String? insertAfter,
  }) =>
      CustomField(
        id: id ?? this.id,
        docTypeId: docTypeId ?? this.docTypeId,
        fieldDefinition: fieldDefinition ?? this.fieldDefinition,
        insertAfter: insertAfter ?? this.insertAfter,
      );

  factory CustomField.fromDbRow(Map<String, dynamic> row) {
    final rawInsertAfter = row['insert_after'] as String?;
    return CustomField(
      id: row['id'] as String,
      docTypeId: row['doctype_id'] as String,
      fieldDefinition: FieldDefinition.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      ),
      insertAfter:
          (rawInsertAfter == null || rawInsertAfter.isEmpty) ? null : rawInsertAfter,
    );
  }

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'doctype_id': docTypeId,
        'payload': jsonEncode(fieldDefinition.toJson()),
        'insert_after': insertAfter,
      };

  /// Inserts a new row when [field.id] is empty (generating a uuid), or
  /// updates the existing row in place otherwise. UPDATE-in-place
  /// preserves SQLite's implicit `rowid`, which `forDocType` relies on
  /// to keep the customize-sheet list and the resolved form ordering
  /// stable when a user edits an existing field — using INSERT OR
  /// REPLACE here would re-issue a fresh rowid and silently push the
  /// edited field to the bottom of the list.
  static Future<void> save(Database db, CustomField field) async {
    if (field.id.isEmpty) {
      const uuid = Uuid();
      final assigned = field.copyWith(id: uuid.v4());
      await db.insert('custom_fields', assigned.toDbRow());
    } else {
      final row = field.toDbRow()..remove('id');
      final updated = await db.update(
        'custom_fields',
        row,
        where: 'id = ?',
        whereArgs: [field.id],
      );
      if (updated == 0) {
        // No existing row matched the id (e.g. a caller passed an id
        // that hasn't been persisted yet). Fall back to insert so the
        // caller's record isn't silently dropped.
        await db.insert('custom_fields', field.toDbRow());
      }
    }
  }

  static Future<void> delete(Database db, String id) async {
    await db.delete('custom_fields', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<CustomField>> forDocType(
    Database db,
    String docTypeId,
  ) async {
    final rows = await db.query(
      'custom_fields',
      where: 'doctype_id = ?',
      whereArgs: [docTypeId],
      orderBy: 'rowid',
    );
    return rows.map(CustomField.fromDbRow).toList();
  }
}
