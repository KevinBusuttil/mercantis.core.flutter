import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import 'core_providers.dart';

/// The app-wide [AttachmentManager] — metadata in the shared database, bytes in
/// the shared [attachmentStoreProvider]. Wired to the sync engine and device id
/// so attach/detach replicate to company peers (ADR-048).
final attachmentManagerProvider = FutureProvider<AttachmentManager>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final store = await ref.watch(attachmentStoreProvider.future);
  final sync = await ref.watch(syncEngineProvider.future);
  final deviceId = await ref.watch(deviceIdProvider.future);
  return AttachmentManager(db.db, store,
      syncEngine: sync, deviceId: deviceId);
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
