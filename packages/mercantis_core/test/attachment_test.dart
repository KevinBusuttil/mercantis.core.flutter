import 'dart:convert';
import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-043: file attachments — the filesystem byte store and the
/// metadata/integrity/audit manager on top of it.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late Directory tempDir;
  late AttachmentStore store;
  late AttachmentManager manager;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    tempDir = Directory.systemTemp.createTempSync('mc_attach_');
    store = AttachmentStore(tempDir.path);
    manager = AttachmentManager(database.db, store);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<int> bytes(String s) => utf8.encode(s);

  group('AttachmentStore', () {
    test('write → read round-trips and reports the relative path', () {
      final path = store.write('doc-1', 'att-1', bytes('hello'));
      expect(path, 'doc-1/att-1');
      expect(utf8.decode(store.read(path)), 'hello');
      expect(store.exists(path), isTrue);
    });

    test('reading a missing path throws notFound', () {
      expect(() => store.read('nope/missing'),
          throwsA(isA<AttachmentException>()));
    });

    test('delete removes one file; deleteAll removes the document tree', () {
      final a = store.write('doc-1', 'att-1', bytes('a'));
      final b = store.write('doc-1', 'att-2', bytes('b'));
      store.delete(a);
      expect(store.exists(a), isFalse);
      expect(store.exists(b), isTrue);

      store.deleteAll('doc-1');
      expect(store.exists(b), isFalse);
      expect(Directory('${tempDir.path}/doc-1').existsSync(), isFalse);
    });

    test('delete tolerates a missing file', () {
      expect(() => store.delete('doc-x/att-x'), returnsNormally);
    });

    test('sha256Hex matches the known digest', () {
      expect(AttachmentStore.sha256Hex(bytes('hello')),
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
    });
  });

  group('AttachmentManager', () {
    test('attach persists bytes, metadata, and an audit row', () async {
      final att = await manager.attach(
        documentId: 'SINV-1',
        docType: 'Sales Invoice',
        fileName: 'po.pdf',
        mimeType: 'application/pdf',
        data: bytes('purchase order'),
        userId: 'alice',
      );

      expect(att.byteSize, 14);
      expect(att.storagePath, 'SINV-1/${att.id}');
      expect(store.exists(att.storagePath), isTrue);

      final meta = await manager.metadata(att.id);
      expect(meta!.fileName, 'po.pdf');
      expect(meta.mimeType, 'application/pdf');
      expect(meta.uploadedBy, 'alice');

      final audit = await database.db.query('audit_log',
          where: 'action = ?', whereArgs: ['attach']);
      expect(audit, hasLength(1));
      expect(jsonDecode(audit.first['payload'] as String)['attachmentId'],
          att.id);
    });

    test('read verifies the SHA-256 and returns bytes', () async {
      final att = await manager.attach(
        documentId: 'D',
        docType: 'T',
        fileName: 'f.txt',
        data: bytes('content'),
        userId: 'u',
      );
      expect(utf8.decode(await manager.read(att)), 'content');
      expect(utf8.decode(await manager.readById(att.id)), 'content');
    });

    test('read throws on a corrupted file (integrity failure)', () async {
      final att = await manager.attach(
        documentId: 'D',
        docType: 'T',
        fileName: 'f.txt',
        data: bytes('original'),
        userId: 'u',
      );
      // Tamper with the bytes on disk behind the manager's back.
      store.write('D', att.id, bytes('tampered!'));
      expect(() => manager.read(att), throwsA(isA<AttachmentException>()));
    });

    test('readById on an unknown id throws notFound', () {
      expect(() => manager.readById('ghost'),
          throwsA(isA<AttachmentException>()));
    });

    test('listing by document and by field', () async {
      final logo = await manager.attach(
          documentId: 'D',
          docType: 'T',
          fieldKey: 'logo',
          fileName: 'logo.png',
          data: bytes('img'),
          userId: 'u');
      final general = await manager.attach(
          documentId: 'D',
          docType: 'T',
          fileName: 'misc.bin',
          data: bytes('x'),
          userId: 'u');

      final all = await manager.attachmentsForDocument('D');
      expect(all.map((a) => a.id), unorderedEquals([logo.id, general.id]));

      final fieldOnly = await manager.attachmentsForField('logo', 'D');
      expect(fieldOnly.map((a) => a.id), [logo.id]);
    });

    test('delete removes the row, file, and writes a detach audit', () async {
      final att = await manager.attach(
          documentId: 'D',
          docType: 'T',
          fileName: 'f',
          data: bytes('x'),
          userId: 'u');

      await manager.delete(att.id, 'u');
      expect(await manager.metadata(att.id), isNull);
      expect(store.exists(att.storagePath), isFalse);
      final audit = await database.db
          .query('audit_log', where: 'action = ?', whereArgs: ['detach']);
      expect(audit, hasLength(1));
    });

    test('deleting an unknown id throws notFound', () {
      expect(() => manager.delete('ghost', 'u'),
          throwsA(isA<AttachmentException>()));
    });

    test('deleteAll cascades the whole document tree', () async {
      await manager.attach(
          documentId: 'D',
          docType: 'T',
          fileName: 'a',
          data: bytes('a'),
          userId: 'u');
      await manager.attach(
          documentId: 'D',
          docType: 'T',
          fileName: 'b',
          data: bytes('b'),
          userId: 'u');

      await manager.deleteAll('D', 'u');
      expect(await manager.attachmentsForDocument('D'), isEmpty);
      expect(Directory('${tempDir.path}/D').existsSync(), isFalse);
      final audit = await database.db
          .query('audit_log', where: 'action = ?', whereArgs: ['detachAll']);
      expect(audit, hasLength(1));
      expect(jsonDecode(audit.first['payload'] as String)['count'], 2);
    });

    test('deleteAll on a document with no attachments is a no-op', () async {
      await manager.deleteAll('empty', 'u');
      final audit = await database.db.query('audit_log');
      expect(audit, isEmpty);
    });
  });
}
