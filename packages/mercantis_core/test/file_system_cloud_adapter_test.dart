import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// ADR-047: two FileSystemCloudAdapter instances against the same shared root
/// simulate two devices syncing via a shared folder. Verifies push fan-out,
/// pull collection, peer-cursor advancement, and state persistence across
/// instance restarts.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fs-adapter-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  var counter = 0;
  MutationRecord mutation(String deviceId) {
    counter += 1;
    return MutationRecord(
      id: 'mut-$counter',
      type: MutationType.updateDocument,
      docType: 'Note',
      documentId: 'doc-$counter',
      payload: {'hello': 'world'},
      deviceId: deviceId,
      userId: 'alice',
      localTimestamp: DateTime.now(),
    );
  }

  Future<FileSystemCloudAdapter> open(String deviceId) =>
      FileSystemCloudAdapter.create(root: root, localDeviceId: deviceId);

  group('push', () {
    test('assigns a monotonic local sequence', () async {
      final a = await open('deviceA');
      final muts = [
        mutation('deviceA'),
        mutation('deviceA'),
        mutation('deviceA')
      ];
      await a.push(muts);
      expect(muts.map((m) => m.syncVersion), ['1', '2', '3']);
      expect(a.localPushSequence, 3);
    });

    test('local sequence survives re-initialisation', () async {
      final a = await open('deviceA');
      await a.push([mutation('deviceA')]);
      await a.push([mutation('deviceA')]);
      expect(a.localPushSequence, 2);

      final reopened = await open('deviceA');
      expect(reopened.localPushSequence, 2);
      final next = mutation('deviceA');
      await reopened.push([next]);
      expect(next.syncVersion, '3');
    });
  });

  group('cross-device pull', () {
    test('a peer pulls everything another device dropped', () async {
      final a = await open('deviceA');
      final b = await open('deviceB');

      await a.push([mutation('deviceA'), mutation('deviceA')]);
      final received = await b.pull(null);
      expect(received, hasLength(2));
      expect(received.map((m) => m.syncVersion), ['1', '2']);
    });

    test('an adapter never pulls its own pushed mutations', () async {
      final a = await open('deviceA');
      await a.push([mutation('deviceA')]);
      expect(await a.pull(null), isEmpty);
    });

    test('peer cursor advances so nothing is replayed', () async {
      final a = await open('deviceA');
      final b = await open('deviceB');

      await a.push([mutation('deviceA')]);
      expect(await b.pull(null), hasLength(1));
      expect(await b.pull(null), isEmpty);
      expect(b.peerCursor('deviceA'), 1);
    });

    test('pull after adapter restart does not replay', () async {
      final a = await open('deviceA');
      await a.push([mutation('deviceA')]);

      final b = await open('deviceB');
      expect(await b.pull(null), hasLength(1));

      final bReopened = await open('deviceB');
      expect(bReopened.peerCursor('deviceA'), 1);
      expect(await bReopened.pull(null), isEmpty);
    });

    test('three-device fan-out: a peer sees both others in one sweep',
        () async {
      final a = await open('deviceA');
      final b = await open('deviceB');
      final c = await open('deviceC');

      await a.push([mutation('deviceA')]);
      await b.push([mutation('deviceB')]);

      final received = await c.pull(null);
      expect(received, hasLength(2));
      expect(received.map((m) => m.deviceId).toSet(), {'deviceA', 'deviceB'});
      expect(received.map((m) => m.syncVersion), ['1', '2']);
    });

    test('syncVersion cutoff plus advanced cursor suppresses replays',
        () async {
      final a = await open('deviceA');
      final b = await open('deviceB');

      await a.push(
          [mutation('deviceA'), mutation('deviceA'), mutation('deviceA')]);

      final first = await b.pull('0');
      expect(first.map((m) => m.syncVersion), ['1', '2', '3']);

      // SyncEngine bookmarked at 2; the cursor has already advanced past all
      // three, so resuming returns nothing.
      expect(await b.pull('2'), isEmpty);
    });
  });

  test('payload round-trips through the on-disk envelope', () async {
    final a = await open('deviceA');
    final b = await open('deviceB');
    final mut = MutationRecord(
      id: 'm1',
      type: MutationType.createDocument,
      docType: 'Note',
      documentId: 'n1',
      payload: {'title': 'Hi', 'count': 3},
      deviceId: 'deviceA',
      userId: 'alice',
      localTimestamp: DateTime.now(),
    );
    await a.push([mut]);

    final received = await b.pull(null);
    expect(received.single.type, MutationType.createDocument);
    expect(received.single.documentId, 'n1');
    expect(received.single.payload, {'title': 'Hi', 'count': 3});
  });
}
