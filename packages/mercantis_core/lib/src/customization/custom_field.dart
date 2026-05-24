import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/field_definition.dart';

class CustomField {
  final String id;
  final String docTypeId;
  final FieldDefinition fieldDefinition;

  const CustomField({
    required this.id,
    required this.docTypeId,
    required this.fieldDefinition,
  });

  factory CustomField.fromDbRow(Map<String, dynamic> row) => CustomField(
        id: row['id'] as String,
        docTypeId: row['doctype_id'] as String,
        fieldDefinition: FieldDefinition.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        ),
      );

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'doctype_id': docTypeId,
        'payload': jsonEncode(fieldDefinition.toJson()),
      };

  static Future<void> save(Database db, CustomField field) async {
    const uuid = Uuid();
    final f = field.id.isEmpty ? CustomField(id: uuid.v4(), docTypeId: field.docTypeId, fieldDefinition: field.fieldDefinition) : field;
    await db.insert('custom_fields', f.toDbRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(Database db, String id) async {
    await db.delete('custom_fields', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<CustomField>> forDocType(Database db, String docTypeId) async {
    final rows = await db.query('custom_fields', where: 'doctype_id = ?', whereArgs: [docTypeId]);
    return rows.map(CustomField.fromDbRow).toList();
  }
}
