import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'doc_type.dart';

class MetadataRegistry {
  final Database _db;
  final Map<String, DocType> _cache = {};

  MetadataRegistry(this._db);

  Future<void> register(DocType docType) async {
    _cache[docType.id] = docType;
    await _db.insert(
      'doctypes',
      {
        'id': docType.id,
        'payload': jsonEncode(docType.toJson()),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DocType?> get(String docTypeId) async {
    if (_cache.containsKey(docTypeId)) return _cache[docTypeId];
    final rows = await _db.query(
      'doctypes',
      where: 'id = ?',
      whereArgs: [docTypeId],
    );
    if (rows.isEmpty) return null;
    final dt = DocType.fromJson(
      jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
    );
    _cache[dt.id] = dt;
    return dt;
  }

  Future<List<DocType>> all() async {
    final rows = await _db.query('doctypes');
    return rows
        .map((r) => DocType.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> unregister(String docTypeId) async {
    _cache.remove(docTypeId);
    await _db.delete('doctypes', where: 'id = ?', whereArgs: [docTypeId]);
  }

  void invalidateCache(String docTypeId) => _cache.remove(docTypeId);
  void invalidateAll() => _cache.clear();

  bool isCached(String docTypeId) => _cache.containsKey(docTypeId);
}
