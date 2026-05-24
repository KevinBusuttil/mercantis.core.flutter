import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite_mobile;
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
  return MercantisDatabase.open(_platformFactory(), '${dir.path}/mercantis.db');
});

final metadataRegistryProvider = FutureProvider<MetadataRegistry>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return MetadataRegistry(db);
});

final metaComposerProvider = FutureProvider<MetaComposer>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return MetaComposer(db: db, registry: registry);
});

final resolvedMetaProvider = FutureProvider.family<ResolvedMeta?, String>((ref, docTypeName) async {
  final composer = await ref.watch(metaComposerProvider.future);
  try {
    return await composer.resolve(docTypeName);
  } catch (_) {
    return null;
  }
});

final namingServiceProvider = FutureProvider<NamingService>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return NamingService(db: db);
});

final eventEmitterProvider = Provider<EventEmitter>((_) => EventEmitter());

final permissionEngineProvider = Provider<PermissionEngine>((_) => PermissionEngine());

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return SyncEngine(db: db, cloudAdapter: NoOpCloudAdapter());
});

final documentEngineProvider = FutureProvider<DocumentEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final naming = await ref.watch(namingServiceProvider.future);
  final emitter = ref.watch(eventEmitterProvider);
  final sync = await ref.watch(syncEngineProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return DocumentEngine(
    db: db,
    namingService: naming,
    emitter: emitter,
    syncEngine: sync,
    metadataRegistry: registry,
  );
});

final workflowEngineProvider = FutureProvider<WorkflowEngine>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return WorkflowEngine(db: db);
});

final schedulerServiceProvider = FutureProvider<SchedulerService>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return SchedulerService(db: db);
});

final automationRunnerProvider = FutureProvider<AutomationRunner>((ref) async {
  final emitter = ref.watch(eventEmitterProvider);
  final engine = await ref.watch(documentEngineProvider.future);
  return AutomationRunner(emitter: emitter, documentEngine: engine);
});

final appInstallerProvider = FutureProvider<AppInstaller>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  final engine = await ref.watch(documentEngineProvider.future);
  final workflow = await ref.watch(workflowEngineProvider.future);
  final scheduler = await ref.watch(schedulerServiceProvider.future);
  final automation = await ref.watch(automationRunnerProvider.future);
  final emitter = ref.watch(eventEmitterProvider);
  return AppInstaller(
    db: db,
    metadataRegistry: registry,
    documentEngine: engine,
    workflowEngine: workflow,
    schedulerService: scheduler,
    automationRunner: automation,
    emitter: emitter,
  );
});
