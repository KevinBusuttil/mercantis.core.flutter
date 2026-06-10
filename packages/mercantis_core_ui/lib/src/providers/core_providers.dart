import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite_mobile;
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mercantis_core/mercantis_core.dart';

DatabaseFactory _platformFactory() {
  if (kIsWeb) throw UnsupportedError('Web is not supported');
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return sqflite_mobile.databaseFactory;
}

final mercantisDatabaseProvider = FutureProvider<MercantisDatabase>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return MercantisDatabase.open(
    factory: _platformFactory(),
    path: '${dir.path}/mercantis.db',
  );
});

final metadataRegistryProvider = FutureProvider<MetadataRegistry>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return MetadataRegistry(db.db);
});

final metaComposerProvider = FutureProvider<MetaComposer>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return MetaComposer(registry, db.db);
});

final resolvedMetaProvider =
    FutureProvider.family<ResolvedMeta?, String>((ref, docTypeName) async {
  final composer = await ref.watch(metaComposerProvider.future);
  try {
    return await composer.resolve(docTypeName);
  } catch (_) {
    return null;
  }
});

/// A stable, per-install device identifier. Generated once and persisted, it
/// keys the per-device naming counter blocks (ADR-042) and the sync adapter's
/// per-device change log — so two devices sharing one company never collide on
/// document numbers or on their sync streams. Must be unique per physical
/// install; never hardcode it.
final deviceIdProvider = FutureProvider<String>((ref) async {
  const key = 'core.device_id';
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(key);
  if (id == null || id.isEmpty) {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(key, id);
  }
  return id;
});

final namingServiceProvider = Provider<NamingService>((ref) => NamingService());

final eventEmitterProvider = Provider<EventEmitter>((_) => EventEmitter());

final permissionEngineProvider =
    Provider<PermissionEngine>((_) => const PermissionEngine());

final expressionEvaluatorProvider =
    Provider<ExpressionEvaluator>((_) => ExpressionEvaluator());

final workflowEngineProvider = FutureProvider<WorkflowEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  // Share the app's emitter so workflow transitions fan out as
  // WorkflowTransitionEvents (consumed e.g. by the Hub's WO auto-post).
  return WorkflowEngine(db.db, emitter: ref.watch(eventEmitterProvider));
});

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return SyncEngine(database: db.db, registry: registry);
});

/// Lifecycle hooks injected into the [DocumentEngine] (defaults, posting-time
/// validation). Empty by default; apps override this to register their own
/// [DocumentInterceptor]s (e.g. the Hub's business-profile defaults and
/// fiscal-year guard).
final documentInterceptorsProvider =
    Provider<List<DocumentInterceptor>>((_) => const []);

final documentEngineProvider = FutureProvider<DocumentEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  final composer = await ref.watch(metaComposerProvider.future);
  final naming = ref.watch(namingServiceProvider);
  final emitter = ref.watch(eventEmitterProvider);
  final permission = ref.watch(permissionEngineProvider);
  final evaluator = ref.watch(expressionEvaluatorProvider);
  final workflow = await ref.watch(workflowEngineProvider.future);
  final sync = await ref.watch(syncEngineProvider.future);
  final deviceId = await ref.watch(deviceIdProvider.future);
  return DocumentEngine(
    database: db.db,
    registry: registry,
    metaComposer: composer,
    permissionEngine: permission,
    workflowEngine: workflow,
    expressionEvaluator: evaluator,
    namingService: naming,
    syncEngine: sync,
    emitter: emitter,
    deviceId: deviceId,
    userId: 'local-user',
    interceptors: ref.watch(documentInterceptorsProvider),
  );
});

final schedulerServiceProvider = FutureProvider<SchedulerService>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return SchedulerService(db.db);
});

final automationRunnerProvider =
    FutureProvider<AutomationRunner>((ref) async {
  final evaluator = ref.watch(expressionEvaluatorProvider);
  return AutomationRunner(
    registry: AutomationActionRegistry(),
    evaluator: evaluator,
  );
});

final appInstallerProvider = FutureProvider<AppInstaller>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  final sync = await ref.watch(syncEngineProvider.future);
  return AppInstaller(
    database: db.db,
    registry: registry,
    syncEngine: sync,
  );
});
