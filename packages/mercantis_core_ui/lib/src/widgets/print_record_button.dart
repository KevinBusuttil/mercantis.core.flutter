import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:printing/printing.dart';

import '../providers/core_providers.dart';
import '../providers/import_export_providers.dart';

enum _PrintAction { print, share }

/// App-bar action that renders a record to a real PDF (via the core
/// [PrintService]'s pure-Dart `pdf` renderer) and hands it to the platform's
/// native print/preview dialog or share sheet using the `printing` plugin.
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
    return PopupMenuButton<_PrintAction>(
      icon: const Icon(Icons.print_outlined),
      tooltip: 'Print',
      enabled: enabled,
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _PrintAction.print,
          child: ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Print…'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _PrintAction.share,
          child: ListTile(
            leading: Icon(Icons.ios_share),
            title: Text('Share PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, _PrintAction action) async {
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final doc = await engine.fetch(docType, documentId!);
      final registry = await ref.read(metadataRegistryProvider.future);
      final meta = await registry.get(docType);
      if (doc == null || meta == null) {
        if (!context.mounted) return;
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
        kind: PrintOutputKind.pdf,
      );
      if (!context.mounted) return;

      switch (action) {
        case _PrintAction.print:
          await Printing.layoutPdf(
            onLayout: (_) async => result.bytes,
            name: result.suggestedFileName,
          );
        case _PrintAction.share:
          await Printing.sharePdf(
            bytes: result.bytes,
            filename: result.suggestedFileName,
          );
      }
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Print failed: $e');
    }
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
