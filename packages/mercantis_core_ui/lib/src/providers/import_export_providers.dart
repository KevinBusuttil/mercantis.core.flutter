import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import 'core_providers.dart';

/// Bulk CSV/JSON exporter over the document store.
final dataExporterProvider = FutureProvider<DataExporter>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return DataExporter(engine, registry);
});

/// Bulk CSV/JSON importer.
final dataImporterProvider = FutureProvider<DataImporter>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return DataImporter(engine, registry);
});

/// Print/PDF service with the default plain-text + PDF renderers.
final printServiceProvider = Provider<PrintService>((_) => PrintService());
