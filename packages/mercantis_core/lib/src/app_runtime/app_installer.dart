import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/metadata_registry.dart';
import '../metadata/schema_validator.dart';
import '../sync_engine/sync_engine.dart';
import '../sync_engine/mutation_record.dart';
import '../notifications/event_emitter.dart';
import 'app_manifest.dart';

class AppInstaller {
  final Database _db;
  final MetadataRegistry _registry;
  final SchemaValidator _validator;
  final SyncEngine? _syncEngine;
  static const _uuid = Uuid();

  AppInstaller({
    required Database database,
    required MetadataRegistry registry,
    SchemaValidator? validator,
    SyncEngine? syncEngine,
  })  : _db = database,
        _registry = registry,
        _validator = validator ?? SchemaValidator(),
        _syncEngine = syncEngine;

  Future<void> install(AppManifest manifest) async {
    final errors = validate(manifest);
    if (errors.isNotEmpty) {
      throw Exception('Manifest validation failed: ${errors.map((e) => e.toString()).join(', ')}');
    }

    // Register DocTypes
    for (final dt in manifest.docTypes) {
      await _registry.register(dt);
    }

    // Store workflows
    for (final wf in manifest.workflows) {
      await _db.insert(
        'workflows',
        {'id': wf.id, 'app_id': manifest.id, 'payload': jsonEncode(wf.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Store manifest in apps table
    await _db.insert(
      'apps',
      {
        'id': manifest.id,
        'version': manifest.version,
        'payload': jsonEncode(manifest.toJson()),
        'installed_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Append sync mutation
    await _syncEngine?.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.installApp,
      docType: 'App',
      documentId: manifest.id,
      payload: {'appId': manifest.id, 'version': manifest.version},
      deviceId: 'installer',
      userId: 'system',
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
  }

  Future<void> uninstall(String appId) async {
    final manifest = await getManifest(appId);
    if (manifest == null) return;

    // Unregister DocTypes declared by this app
    for (final dt in manifest.docTypes) {
      await _registry.unregister(dt.id);
    }

    await _db.delete('apps', where: 'id = ?', whereArgs: [appId]);
    await _db.delete('workflows', where: 'app_id = ?', whereArgs: [appId]);

    await _syncEngine?.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.uninstallApp,
      docType: 'App',
      documentId: appId,
      payload: {'appId': appId},
      deviceId: 'installer',
      userId: 'system',
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
  }

  List<dynamic> validate(AppManifest manifest) {
    final errors = [];
    for (final dt in manifest.docTypes) {
      errors.addAll(_validator.validate(dt));
    }
    return errors;
  }

  Future<bool> isInstalled(String appId) async {
    final rows =
        await _db.query('apps', where: 'id = ?', whereArgs: [appId]);
    return rows.isNotEmpty;
  }

  Future<AppManifest?> getManifest(String appId) async {
    final rows =
        await _db.query('apps', where: 'id = ?', whereArgs: [appId]);
    if (rows.isEmpty) return null;
    return AppManifest.fromJson(
      jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
    );
  }

  Future<List<AppManifest>> installedApps() async {
    final rows = await _db.query('apps');
    return rows
        .map((r) => AppManifest.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ))
        .toList();
  }
}
