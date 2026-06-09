import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/import_export_providers.dart';

/// Overflow menu (for a list screen's trailing actions) that exports the
/// current DocType to CSV/JSON and imports a CSV/JSON file via the bulk
/// import/export engine. [onChanged] is called after a successful import so the
/// caller can refresh its list.
class ImportExportMenu extends ConsumerWidget {
  const ImportExportMenu({super.key, required this.docType, this.onChanged});

  final String docType;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Import / Export',
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'csv', child: Text('Export CSV')),
        PopupMenuItem(value: 'json', child: Text('Export JSON')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'import', child: Text('Import…')),
      ],
      onSelected: (v) {
        if (v == 'import') {
          _import(context, ref);
        } else {
          _export(context, ref, v == 'csv' ? ImportExportFormat.csv : ImportExportFormat.json);
        }
      },
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, ImportExportFormat format) async {
    try {
      final exporter = await ref.read(dataExporterProvider.future);
      final text = await exporter.export(docType: docType, format: format);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Export $docType (${format.name.toUpperCase()})'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(text.isEmpty ? '(no records)' : text)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied')));
              },
              child: const Text('Copy'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      _snack(context, 'Export failed: $e');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['csv', 'json'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      final format =
          file.name.toLowerCase().endsWith('.json') ? ImportExportFormat.json : ImportExportFormat.csv;
      final importer = await ref.read(dataImporterProvider.future);
      final report = await importer.import(
        docType: docType,
        data: utf8.decode(bytes),
        format: format,
      );
      onChanged?.call();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import complete'),
          content: Text(
            '${report.rowsRead} rows read\n'
            'Inserted: ${report.insertedCount}\n'
            'Updated: ${report.updatedCount}\n'
            'Skipped: ${report.skippedCount}\n'
            'Failed: ${report.failedCount}',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      _snack(context, 'Import failed: $e');
    }
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
