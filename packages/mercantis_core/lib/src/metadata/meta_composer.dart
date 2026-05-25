import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'doc_type.dart';
import 'field_definition.dart';
import 'metadata_registry.dart';
import 'resolved_meta.dart';

class MetaComposer {
  final MetadataRegistry _registry;
  final Database _db;
  final Map<String, ResolvedMeta> _cache = {};

  MetaComposer(this._registry, this._db);

  Future<ResolvedMeta> resolve(String docTypeId) async {
    if (_cache.containsKey(docTypeId)) return _cache[docTypeId]!;

    final docType = await _registry.get(docTypeId);
    if (docType == null) throw Exception('DocType not found: $docTypeId');

    // Start with base fields
    final resolvedFields = docType.fields
        .map((f) => ResolvedFieldDefinition.fromFieldDefinition(f))
        .toList();

    // Load custom fields and place each at its declared `insert_after`
    // position. Rows that pre-date the v2 migration (or that the user has
    // explicitly chosen to append) have `insert_after = NULL` and fall
    // back to "end of form".
    final customRows = await _db.query(
      'custom_fields',
      where: 'doctype_id = ?',
      whereArgs: [docTypeId],
      orderBy: 'rowid',
    );
    for (final row in customRows) {
      final fd = FieldDefinition.fromJson(
        jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );
      final resolved = ResolvedFieldDefinition.fromFieldDefinition(
        fd,
        isCustomField: true,
      );
      final insertAfter = row['insert_after'] as String?;
      if (insertAfter == null || insertAfter.isEmpty) {
        resolvedFields.add(resolved);
        continue;
      }
      final anchorIndex =
          resolvedFields.indexWhere((f) => f.key == insertAfter);
      if (anchorIndex < 0) {
        // Anchor field doesn't exist (e.g. base field was removed in a
        // later manifest version). Fall back to append so the user's
        // field doesn't silently disappear.
        resolvedFields.add(resolved);
      } else {
        resolvedFields.insert(anchorIndex + 1, resolved);
      }
    }

    // Load property setters and apply overrides
    final setterRows = await _db.query(
      'property_setters',
      where: 'doctype_id = ?',
      whereArgs: [docTypeId],
    );
    final overrideMap = <String, Map<String, dynamic>>{};
    for (final row in setterRows) {
      final fieldKey = row['field_key'] as String;
      final property = row['property'] as String;
      final value = row['value'] as String;
      overrideMap.putIfAbsent(fieldKey, () => {})[property] = value;
    }

    // Apply property overrides by rebuilding affected fields
    for (var i = 0; i < resolvedFields.length; i++) {
      final f = resolvedFields[i];
      final overrides = overrideMap[f.key];
      if (overrides == null) continue;
      final json = f.toJson();
      json.addAll(overrides);
      resolvedFields[i] = ResolvedFieldDefinition.fromFieldDefinition(
        FieldDefinition.fromJson(json),
        isCustomField: f.isCustomField,
        propertyOverrides: overrides,
      );
    }

    final meta = ResolvedMeta(docType: docType, fields: resolvedFields);
    _cache[docTypeId] = meta;
    return meta;
  }

  void invalidate(String docTypeId) => _cache.remove(docTypeId);
  void invalidateAll() => _cache.clear();
}
