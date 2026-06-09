import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/core_providers.dart';
import '../providers/import_export_providers.dart';

/// App-bar action that renders a record to a plain-text print preview using a
/// default [PrintFormat] auto-built from the DocType's fields. (PDF bytes are
/// available from the same `PrintService.render` for a future share/print
/// integration.)
class PrintRecordButton extends ConsumerWidget {
  const PrintRecordButton({super.key, required this.docType, required this.documentId});

  final String docType;
  final String? documentId;

  static const _skip = {
    FieldType.table,
    FieldType.tableMultiSelect,
    FieldType.heading,
    FieldType.sectionBreak,
    FieldType.columnBreak,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = documentId != null && documentId!.isNotEmpty;
    return IconButton(
      icon: const Icon(Icons.print_outlined),
      tooltip: 'Print preview',
      onPressed: enabled ? () => _print(context, ref) : null,
    );
  }

  Future<void> _print(BuildContext context, WidgetRef ref) async {
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final doc = await engine.fetch(docType, documentId!);
      final registry = await ref.read(metadataRegistryProvider.future);
      final meta = await registry.get(docType);
      if (doc == null || meta == null) {
        _snack(context, 'Nothing to print');
        return;
      }

      final fieldKeys = [for (final f in meta.fields) if (!_skip.contains(f.type)) f.key];
      final tableKeys = [for (final f in meta.fields) if (f.type == FieldType.table) f.key];

      final format = PrintFormat(
        id: 'auto-$docType',
        name: meta.name,
        docType: docType,
        sections: [
          HeadingSection(meta.name),
          FieldsSection(keys: fieldKeys),
          for (final t in tableKeys) TableSection(tableKey: t),
        ],
      );

      final service = ref.read(printServiceProvider)..registerFormat(format);
      final result = await service.render(
        formatId: format.id,
        document: doc,
        kind: PrintOutputKind.plainText,
      );
      final text = utf8.decode(result.bytes);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Print preview · ${meta.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
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
      _snack(context, 'Print failed: $e');
    }
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
