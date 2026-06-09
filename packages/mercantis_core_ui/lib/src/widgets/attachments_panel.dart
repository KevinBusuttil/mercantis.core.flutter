import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/attachment_providers.dart';
import '../workspace/current_user.dart';

/// Lists, uploads and deletes the file attachments bound to a document, backed
/// by the [AttachmentManager]. Drop into a record's Attachments tab.
class AttachmentsPanel extends ConsumerStatefulWidget {
  const AttachmentsPanel({super.key, required this.documentId, required this.docType});

  /// The document these attachments belong to. When null/empty the document is
  /// unsaved and attachments can't be added yet.
  final String? documentId;
  final String docType;

  @override
  ConsumerState<AttachmentsPanel> createState() => _AttachmentsPanelState();
}

class _AttachmentsPanelState extends ConsumerState<AttachmentsPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final docId = widget.documentId;
    if (docId == null || docId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return; // cancelled
      }
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final manager = await ref.read(attachmentManagerProvider.future);
      await manager.attach(
        documentId: docId,
        docType: widget.docType,
        fileName: file.name,
        data: bytes,
        userId: ref.read(currentUserProvider).id,
      );
      ref.invalidate(attachmentsForDocumentProvider(docId));
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _delete(Attachment a) async {
    setState(() => _busy = true);
    try {
      final manager = await ref.read(attachmentManagerProvider.future);
      await manager.delete(a.id, ref.read(currentUserProvider).id);
      ref.invalidate(attachmentsForDocumentProvider(a.documentId));
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final docId = widget.documentId;
    if (docId == null || docId.isEmpty) {
      return const Center(child: Text('Save the document to add attachments'));
    }
    final async = ref.watch(attachmentsForDocumentProvider(docId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: const Text('Add Attachment'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load attachments: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file, size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No attachments', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = items[i];
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(a.fileName),
                    subtitle: Text('${_humanSize(a.byteSize)} · ${a.uploadedAt.toIso8601String().split('T').first}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: _busy ? null : () => _delete(a),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
