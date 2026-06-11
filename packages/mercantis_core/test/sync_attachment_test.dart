import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// ADR-048: attachment sync. A captured receipt (or any attachment) must
/// replicate to company peers — both the metadata row *and* the bytes, the
/// latter through the cloud adapter's content-addressed blob channel. Two
/// engines/stores against one shared cloud root stand in for two devices.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory cloudRoot;
  late Directory storeDirA;
  late Directory storeDirB;
  late MercantisDatabase dbA;
  late MercantisDatabase dbB;
  late AttachmentStore storeA;
  late AttachmentStore storeB;
  late FileSystemCloudAdapter adapterA;
  late FileSystemCloudAdapter adapterB;
  late SyncEngine engineA;
  late SyncEngine engineB;
  late AttachmentManager managerA;
  late AttachmentManager managerB;

  final bytes = List<int>.generate(4096, (i) => (i * 7) % 256);

  setUp(() async {
    cloudRoot = await Directory.systemTemp.createTemp('att-cloud-');
    storeDirA = await Directory.systemTemp.createTemp('att-store-a-');
    storeDirB = await Directory.systemTemp.createTemp('att-store-b-');

    dbA = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    dbB = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);

    storeA = AttachmentStore(storeDirA.path);
    storeB = AttachmentStore(storeDirB.path);

    adapterA =
        await FileSystemCloudAdapter.create(root: cloudRoot, localDeviceId: 'devA');
    adapterB =
        await FileSystemCloudAdapter.create(root: cloudRoot, localDeviceId: 'devB');

    engineA = SyncEngine(
      database: dbA.db,
      registry: MetadataRegistry(dbA.db),
      cloudAdapter: adapterA,
      attachmentStore: storeA,
    );
    engineB = SyncEngine(
      database: dbB.db,
      registry: MetadataRegistry(dbB.db),
      cloudAdapter: adapterB,
      attachmentStore: storeB,
    );

    managerA = AttachmentManager(dbA.db, storeA,
        syncEngine: engineA, deviceId: 'devA');
    managerB = AttachmentManager(dbB.db, storeB,
        syncEngine: engineB, deviceId: 'devB');
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
    for (final d in [cloudRoot, storeDirA, storeDirB]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('metadata and bytes replicate to a peer', () async {
    final attachment = await managerA.attach(
      documentId: 'CAP-0001',
      docType: 'Captured Document',
      fieldKey: 'document_file',
      fileName: 'receipt.jpg',
      mimeType: 'image/jpeg',
      data: bytes,
      userId: 'alice',
    );

    // Attaching enqueued a createAttachment mutation.
    expect(await engineA.pendingCount(), 1);

    await engineA.pushPendingMutations();
    await engineB.pullAndApplyRemoteMutations();

    // Metadata landed on the peer...
    final onPeer = await managerB.attachmentsForDocument('CAP-0001');
    expect(onPeer, hasLength(1));
    expect(onPeer.single.id, attachment.id);
    expect(onPeer.single.sha256, attachment.sha256);
    expect(onPeer.single.fieldKey, 'document_file');

    // ...and so did the bytes, intact (read() re-verifies the SHA-256).
    expect(storeB.exists(attachment.storagePath), isTrue);
    expect(await managerB.read(onPeer.single), bytes);
  });

  test('reconcileBlobs backfills bytes that arrive after the metadata',
      () async {
    final sha = AttachmentStore.sha256Hex(bytes);
    final row = {
      'id': 'att-late',
      'document_id': 'CAP-0002',
      'doc_type': 'Captured Document',
      'field_key': null,
      'file_name': 'late.png',
      'mime_type': 'image/png',
      'byte_size': bytes.length,
      'storage_path': 'CAP-0002/att-late',
      'uploaded_at': DateTime.now().millisecondsSinceEpoch,
      'uploaded_by': 'alice',
      'sha256': sha,
    };
    final mutation = MutationRecord(
      id: 'm-late',
      type: MutationType.createAttachment,
      docType: 'Captured Document',
      documentId: 'att-late',
      payload: row,
      deviceId: 'devA',
      userId: 'alice',
      localTimestamp: DateTime.now(),
    );

    // Apply the metadata before the blob exists in the shared channel.
    await engineB.applyRemoteMutations([mutation]);
    expect(await managerB.metadata('att-late'), isNotNull);
    expect(storeB.exists('CAP-0002/att-late'), isFalse); // bytes not here yet

    // The blob shows up later; reconcile pulls it down and verifies it.
    await adapterA.pushBlob(sha, bytes);
    await engineB.reconcileBlobs();
    expect(storeB.exists('CAP-0002/att-late'), isTrue);
    expect(storeB.read('CAP-0002/att-late'), bytes);
  });

  test('a corrupt blob is rejected on integrity check', () async {
    final sha = AttachmentStore.sha256Hex(bytes);
    final row = {
      'id': 'att-bad',
      'document_id': 'CAP-0003',
      'doc_type': 'Captured Document',
      'field_key': null,
      'file_name': 'bad.png',
      'mime_type': 'image/png',
      'byte_size': bytes.length,
      'storage_path': 'CAP-0003/att-bad',
      'uploaded_at': DateTime.now().millisecondsSinceEpoch,
      'uploaded_by': 'alice',
      'sha256': sha,
    };
    // Publish bytes that don't match the advertised sha256.
    await adapterA.pushBlob(sha, List<int>.generate(4096, (_) => 0));
    await engineB.applyRemoteMutations([
      MutationRecord(
        id: 'm-bad',
        type: MutationType.createAttachment,
        docType: 'Captured Document',
        documentId: 'att-bad',
        payload: row,
        deviceId: 'devA',
        userId: 'alice',
        localTimestamp: DateTime.now(),
      )
    ]);
    // Metadata is recorded, but the mismatched bytes are not written.
    expect(await managerB.metadata('att-bad'), isNotNull);
    expect(storeB.exists('CAP-0003/att-bad'), isFalse);
  });

  test('a delete replicates and removes the peer copy', () async {
    final attachment = await managerA.attach(
      documentId: 'CAP-0004',
      docType: 'Captured Document',
      fileName: 'r.jpg',
      mimeType: 'image/jpeg',
      data: bytes,
      userId: 'alice',
    );
    await engineA.pushPendingMutations();
    await engineB.pullAndApplyRemoteMutations();
    expect(await managerB.metadata(attachment.id), isNotNull);

    await managerA.delete(attachment.id, 'alice');
    await engineA.pushPendingMutations();
    await engineB.pullAndApplyRemoteMutations();

    expect(await managerB.metadata(attachment.id), isNull);
    expect(storeB.exists(attachment.storagePath), isFalse);
  });
}
