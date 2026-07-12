import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_adapter.dart';
import 'mutation_record.dart';

/// A sync call the Atlas Team backend refused or that failed in transport.
/// [statusCode] is the HTTP status (0 for transport-level failures) and
/// [message] the server's `error` field when it sent one.
///
/// Notable statuses the sync engine may want to branch on:
///  * 401 — token invalid/revoked: re-registration or sign-in needed;
///  * 409 — an officially posted document is immutable on the sync plane
///    (changes must go through the command API).
class CloudHttpException implements Exception {
  const CloudHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'CloudHttpException($statusCode): $message';
}

/// HTTP [CloudAdapter] for the Atlas Team backend — the client half of the
/// replication plane (`/companies/{id}/sync/*`, `/blobs/{sha256}`).
///
/// Authenticates with a **device token** (from
/// `POST /companies/{id}/devices`); user tokens are rejected by the sync
/// endpoints on purpose, so pass the right kind. The wire format is the
/// camelCase [MutationRecord.toWireJson] shape the backend mirrors verbatim;
/// the server assigns per-company monotonic sync versions on push and this
/// adapter stamps them back onto the pushed records, mirroring what
/// `FileSystemCloudAdapter` does with its local sequence.
class HttpCloudAdapter implements PagedCloudAdapter {
  HttpCloudAdapter({
    required String baseUrl,
    required this.companyId,
    required this.deviceToken,
    http.Client? client,
    this.pageSize,
  })  : _base = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '')),
        _client = client ?? http.Client();

  final String companyId;
  final String deviceToken;

  /// Optional client-side page size for pulls (sent as `limit`); the server
  /// clamps it to its own maximum either way. Null lets the server decide.
  final int? pageSize;

  final Uri _base;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $deviceToken',
        'Content-Type': 'application/json',
      };

  Uri _url(String path, [Map<String, String>? query]) => _base.replace(
        path: '${_base.path}/companies/$companyId$path',
        queryParameters: query,
      );

  @override
  Future<void> push(List<MutationRecord> mutations) async {
    if (mutations.isEmpty) return;
    final response = await _client.post(
      _url('/sync/push'),
      headers: _headers,
      body: jsonEncode({
        'mutations': [for (final m in mutations) m.toWireJson()],
      }),
    );
    final body = _require(response);
    // The server's assigned version becomes each record's syncVersion —
    // the cursor the local store keeps.
    final versions = body['versions'];
    if (versions is Map) {
      for (final m in mutations) {
        final v = versions[m.id];
        if (v != null) m.syncVersion = '$v';
      }
    }
  }

  /// Drains EVERY page for callers of the plain [CloudAdapter] contract
  /// (e.g. SyncEngine.pullAndApplyRemoteMutations), advancing the cursor by
  /// the highest syncVersion seen. Returning only the first page here would
  /// silently truncate a multi-page bootstrap. Pagers that want per-page
  /// cursor commits use [pullPage] directly.
  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async {
    final all = <MutationRecord>[];
    var cursor = afterSyncVersion;
    while (true) {
      final page = await pullPage(cursor);
      all.addAll(page.mutations);
      if (!page.hasMore) return all;
      String? next;
      for (final m in page.mutations) {
        final v = m.syncVersion;
        if (v == null) continue;
        if (next == null ||
            (int.tryParse(v) ?? 0) > (int.tryParse(next) ?? 0)) {
          next = v;
        }
      }
      // No version to advance by would repeat the same page forever.
      if (next == null || next == cursor) return all;
      cursor = next;
    }
  }

  @override
  Future<PullPage> pullPage(String? afterSyncVersion) async {
    final after =
        afterSyncVersion == null ? 0 : int.tryParse(afterSyncVersion) ?? 0;
    final response = await _client.get(
      _url('/sync/pull', {
        'after': '$after',
        if (pageSize != null && pageSize! > 0) 'limit': '$pageSize',
      }),
      headers: _headers,
    );
    final body = _require(response);
    final raw = body['mutations'];
    return PullPage(
      [
        if (raw is List)
          for (final entry in raw)
            if (entry is Map)
              MutationRecord.fromWireJson(Map<String, dynamic>.from(entry)),
      ],
      // Servers predating pagination send no flag — one page is everything.
      hasMore: body['hasMore'] == true,
    );
  }

  @override
  Future<void> acknowledge(List<String> mutationIds) async {
    if (mutationIds.isEmpty) return;
    final response = await _client.post(
      _url('/sync/ack'),
      headers: _headers,
      body: jsonEncode({'ids': mutationIds}),
    );
    _require(response);
  }

  // Blob channel (ADR-048): content-addressed bytes. PUT is idempotent (the
  // server verifies the body's SHA-256 against the path and stores once).

  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {
    final response = await _client.put(
      _url('/blobs/${sha256.toLowerCase()}'),
      headers: {
        'Authorization': 'Bearer $deviceToken',
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );
    _require(response);
  }

  @override
  Future<List<int>?> pullBlob(String sha256) async {
    final response = await _client.get(
      _url('/blobs/${sha256.toLowerCase()}'),
      headers: {'Authorization': 'Bearer $deviceToken'},
    );
    if (response.statusCode == 404) return null;
    _requireStatus(response);
    return response.bodyBytes;
  }

  @override
  Future<bool> hasBlob(String sha256) async {
    final response = await _client.head(
      _url('/blobs/${sha256.toLowerCase()}'),
      headers: {'Authorization': 'Bearer $deviceToken'},
    );
    if (response.statusCode == 404) return false;
    _requireStatus(response);
    return true;
  }

  /// Frees the underlying HTTP client. Only call when this adapter owns it
  /// (i.e. none was injected).
  void close() => _client.close();

  /// 2xx or throws; returns the decoded JSON object body (empty map when the
  /// body isn't a JSON object — some endpoints only matter by status).
  Map<String, dynamic> _require(http.Response response) {
    _requireStatus(response);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through — status was already OK.
    }
    return const {};
  }

  void _requireStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'HTTP ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {
      // Non-JSON error body; keep the status-line message.
    }
    throw CloudHttpException(response.statusCode, message);
  }
}
