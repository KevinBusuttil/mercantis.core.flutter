import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';

class PropertySetter {
  final String id;
  final String docTypeId;
  final String fieldKey;
  final String property;
  final String value;

  const PropertySetter({
    required this.id,
    required this.docTypeId,
    required this.fieldKey,
    required this.property,
    required this.value,
  });

  factory PropertySetter.fromDbRow(Map<String, dynamic> row) => PropertySetter(
        id: row['id'] as String,
        docTypeId: row['doctype_id'] as String,
        fieldKey: row['field_key'] as String,
        property: row['property'] as String,
        value: row['value'] as String,
      );

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'doctype_id': docTypeId,
        'field_key': fieldKey,
        'property': property,
        'value': value,
      };

  static Future<void> save(Database db, PropertySetter ps) async {
    const uuid = Uuid();
    final record = ps.id.isEmpty
        ? PropertySetter(id: uuid.v4(), docTypeId: ps.docTypeId, fieldKey: ps.fieldKey, property: ps.property, value: ps.value)
        : ps;
    await db.insert('property_setters', record.toDbRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> delete(Database db, String id) async {
    await db.delete('property_setters', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<PropertySetter>> forDocType(Database db, String docTypeId) async {
    final rows = await db.query('property_setters', where: 'doctype_id = ?', whereArgs: [docTypeId]);
    return rows.map(PropertySetter.fromDbRow).toList();
  }
}
