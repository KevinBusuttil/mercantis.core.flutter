import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:path_provider/path_provider.dart';

import 'core_providers.dart';

/// The app-wide [AttachmentManager] — metadata in the shared database, bytes
/// under `<app-support>/attachments`.
final attachmentManagerProvider = FutureProvider<AttachmentManager>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final dir = await getApplicationSupportDirectory();
  return AttachmentManager(db.db, AttachmentStore('${dir.path}/attachments'));
});

/// The attachments bound to one document, newest first. Invalidate to refresh
/// after an attach/delete.
final attachmentsForDocumentProvider =
    FutureProvider.family<List<Attachment>, String>((ref, documentId) async {
  final manager = await ref.watch(attachmentManagerProvider.future);
  final list = await manager.attachmentsForDocument(documentId);
  list.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
  return list;
});
