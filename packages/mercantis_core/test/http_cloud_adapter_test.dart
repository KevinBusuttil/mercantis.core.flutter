import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// HttpCloudAdapter — the client half of the Atlas Team replication plane.
/// Verifies the exact wire contract the Rust backend speaks: paths, device
/// bearer auth, camelCase MutationRecord JSON, server-assigned versions
/// stamped back on push, cursor-based pull, and the content-addressed blob
/// channel.
void main() {
  MutationRecord record(String id, {String? syncVersion}) => MutationRecord(
        id: id,
        type: MutationType.createDocument,
        docType: 'Sales Invoice',
        documentId: 'SINV-0001',
        payload: {'customer': 'CUST-1', 'grand_total': 44},
        deviceId: 'dev-A',
        userId: 'user-1',
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000000),
        syncVersion: syncVersion,
      );

  HttpCloudAdapter adapter(MockClient client) => HttpCloudAdapter(
        baseUrl: 'https://sync.atlas.neuradix.app/',
        companyId: 'c0mp-any1',
        deviceToken: 'devtok-secret',
        client: client,
      );

  group('wire format', () {
    test('toWireJson/fromWireJson round-trip, payload as object', () {
      final m = record('m1', syncVersion: '7');
      final wire = m.toWireJson();
      expect(wire['type'], 'createDocument');
      expect(wire['docType'], 'Sales Invoice');
      expect(wire['documentId'], 'SINV-0001');
      expect(wire['payload'], isA<Map<String, dynamic>>());
      expect(wire['localTimestamp'], 1751800000000);
      expect(wire['syncVersion'], '7');

      final back = MutationRecord.fromWireJson(
          jsonDecode(jsonEncode(wire)) as Map<String, dynamic>);
      expect(back.id, m.id);
      expect(back.type, m.type);
      expect(back.payload['grand_total'], 44);
      expect(back.localTimestamp, m.localTimestamp);
      expect(back.syncVersion, '7');
      expect(back.status, MutationStatus.pending);
    });
  });

  group('push', () {
    test('POSTs the batch with device auth and stamps assigned versions',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({'versions': {'m1': 12, 'm2': 13}}), 200);
      });

      final m1 = record('m1');
      final m2 = record('m2');
      await adapter(client).push([m1, m2]);

      expect(seen!.method, 'POST');
      expect(seen!.url.toString(),
          'https://sync.atlas.neuradix.app/companies/c0mp-any1/sync/push');
      expect(seen!.headers['Authorization'], 'Bearer devtok-secret');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect((body['mutations'] as List).length, 2);
      expect((body['mutations'] as List).first['docType'], 'Sales Invoice');

      // The server's monotonic versions become the local records' cursors.
      expect(m1.syncVersion, '12');
      expect(m2.syncVersion, '13');
    });

    test('an empty batch never touches the network', () async {
      final client = MockClient((_) async => fail('no request expected'));
      await adapter(client).push([]);
    });

    test('a 409 (immutable posted document) surfaces status and reason',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': 'Sales Invoice SINV-0001 is officially posted '
                '(docstatus 1) and immutable; use the command API'
          }),
          409));
      await expectLater(
        adapter(client).push([record('m1')]),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('immutable'))),
      );
    });
  });

  group('pull', () {
    test('passes the numeric cursor and parses wire records', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'mutations': [
                {...record('m9').toWireJson(), 'syncVersion': '9'},
              ],
            }),
            200);
      });

      final pulled = await adapter(client).pull('8');
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/companies/c0mp-any1/sync/pull');
      expect(seen!.url.queryParameters['after'], '8');
      expect(pulled.single.id, 'm9');
      expect(pulled.single.syncVersion, '9');
      expect(pulled.single.payload['customer'], 'CUST-1');
    });

    test('a null cursor pulls from the beginning', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'mutations': []}), 200);
      });
      expect(await adapter(client).pull(null), isEmpty);
      expect(seen!.queryParameters['after'], '0');
    });

    test('an expired/revoked device token surfaces as 401', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'error': 'unauthorized'}), 401));
      await expectLater(
        adapter(client).pull(null),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    // Phase 0.6 (gap analysis §8-C9): the server pages its pull responses;
    // pullPage exposes the hasMore flag so callers can loop with a per-page
    // cursor commit instead of receiving years of history in one body.
    test('pullPage surfaces hasMore and an optional client page size',
        () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response(
            jsonEncode({
              'mutations': [
                {...record('m9').toWireJson(), 'syncVersion': '9'},
              ],
              'hasMore': true,
            }),
            200);
      });

      final paged = HttpCloudAdapter(
        baseUrl: 'https://sync.atlas.neuradix.app',
        companyId: 'c0mp-any1',
        deviceToken: 'devtok-secret',
        client: client,
        pageSize: 50,
      );
      final page = await paged.pullPage('8');
      expect(seen!.queryParameters['after'], '8');
      expect(seen!.queryParameters['limit'], '50');
      expect(page.mutations.single.id, 'm9');
      expect(page.hasMore, isTrue);
    });

    test('a server without pagination reads as a single final page',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'mutations': [record('m1').toWireJson()],
          }),
          200));
      final page = await adapter(client).pullPage(null);
      expect(page.mutations, hasLength(1));
      expect(page.hasMore, isFalse); // no flag → nothing more
    });

    test('no pageSize configured sends no limit parameter', () async {
      Uri? seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response(
            jsonEncode({'mutations': [], 'hasMore': false}), 200);
      });
      await adapter(client).pullPage(null);
      expect(seen!.queryParameters.containsKey('limit'), isFalse);
    });
  });

  group('acknowledge', () {
    test('POSTs the id list', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'acknowledged': 2}), 200);
      });
      await adapter(client).acknowledge(['m1', 'm2']);
      expect(seen!.url.path, '/companies/c0mp-any1/sync/ack');
      expect(jsonDecode(seen!.body), {'ids': ['m1', 'm2']});
    });
  });

  group('blobs', () {
    const sha = 'A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90';

    test('pushBlob PUTs raw bytes to the lower-cased content address',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('', 201);
      });
      await adapter(client).pushBlob(sha, [1, 2, 3]);
      expect(seen!.method, 'PUT');
      expect(seen!.url.path,
          '/companies/c0mp-any1/blobs/${sha.toLowerCase()}');
      expect(seen!.headers['Content-Type'], contains('application/octet-stream'));
      expect(seen!.bodyBytes, [1, 2, 3]);
    });

    test('pullBlob returns bytes, or null on 404', () async {
      final client = MockClient((req) async =>
          req.method == 'GET' && req.url.path.endsWith('deadbeef')
              ? http.Response.bytes([9, 9], 200)
              : http.Response(jsonEncode({'error': 'not found'}), 404));
      expect(await adapter(client).pullBlob('deadbeef'), [9, 9]);
      expect(await adapter(client).pullBlob('cafebabe'), isNull);
    });

    test('hasBlob maps HEAD 200/404 to true/false', () async {
      final client = MockClient((req) async =>
          req.url.path.endsWith('deadbeef')
              ? http.Response('', 200)
              : http.Response('', 404));
      expect(await adapter(client).hasBlob('deadbeef'), isTrue);
      expect(await adapter(client).hasBlob('cafebabe'), isFalse);
    });
  });

  test('a base URL with a path prefix is respected', () async {
    Uri? seen;
    final client = MockClient((req) async {
      seen = req.url;
      return http.Response(jsonEncode({'mutations': []}), 200);
    });
    final prefixed = HttpCloudAdapter(
      baseUrl: 'https://team.neuradix.app/atlas/',
      companyId: 'c1',
      deviceToken: 't',
      client: client,
    );
    await prefixed.pull(null);
    expect(seen!.path, '/atlas/companies/c1/sync/pull');
  });
}
