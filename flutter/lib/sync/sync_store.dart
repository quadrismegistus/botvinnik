import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A blob the store holds, with the version tag needed to compare-and-swap it.
class StoredBlob {
  const StoredBlob(this.bytes, this.etag);
  final Uint8List bytes;
  final String etag;
}

/// A write lost a compare-and-swap race (the Worker's 412): the blob was
/// created or changed by someone else first. The caller re-reads, re-merges,
/// and retries — see [SyncService.syncNow].
class SyncConflict implements Exception {
  const SyncConflict();
  @override
  String toString() => 'SyncConflict';
}

/// The ciphertext exceeded the store's size cap (the Worker's 413).
class SyncTooLarge implements Exception {
  const SyncTooLarge();
  @override
  String toString() => 'SyncTooLarge';
}

/// The store failed for a reason that is not a conflict — no network, a 5xx, a
/// malformed response. Treated by callers as "offline / try later", never as
/// data loss.
class SyncTransportException implements Exception {
  const SyncTransportException(this.message);
  final String message;
  @override
  String toString() => 'SyncTransportException: $message';
}

/// A compare-and-swap blob store, mirroring the botvinnik-sync Worker's
/// contract (#203 M1). The two write methods map onto the Worker's two
/// preconditions; [SyncService] is the only intended caller.
abstract class SyncStore {
  /// The blob, or null if it does not exist (404).
  Future<StoredBlob?> get(String blobId);

  /// Create-only — `If-None-Match: *`. Returns the new etag, or throws
  /// [SyncConflict] if the blob already exists.
  Future<String> create(String blobId, List<int> body);

  /// Update-only — `If-Match: <etag>`. Returns the new etag, or throws
  /// [SyncConflict] if [etag] is no longer current.
  Future<String> update(String blobId, List<int> body, String etag);
}

/// The real store: HTTP to the botvinnik-sync Worker at [baseUrl].
class HttpSyncStore implements SyncStore {
  HttpSyncStore({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// The Worker's origin, no trailing slash (e.g. `https://sync.botvinnik.app`).
  final String baseUrl;
  final http.Client _client;

  Uri _blob(String id) => Uri.parse('$baseUrl/b/$id');

  @override
  Future<StoredBlob?> get(String blobId) async {
    final res = await _send(() => _client.get(_blob(blobId)));
    if (res.statusCode == 404) return null;
    if (res.statusCode == 200) {
      return StoredBlob(res.bodyBytes, _etag(res));
    }
    throw SyncTransportException('GET ${res.statusCode}');
  }

  @override
  Future<String> create(String blobId, List<int> body) =>
      _put(blobId, body, const {'If-None-Match': '*'});

  @override
  Future<String> update(String blobId, List<int> body, String etag) =>
      _put(blobId, body, {'If-Match': etag});

  Future<String> _put(
    String blobId,
    List<int> body,
    Map<String, String> precondition,
  ) async {
    final res = await _send(() => _client.put(
          _blob(blobId),
          headers: {
            ...precondition,
            'Content-Type': 'application/octet-stream',
          },
          body: body,
        ));
    switch (res.statusCode) {
      case 200:
      case 201:
        return _etag(res);
      case 412:
        throw const SyncConflict();
      case 413:
        throw const SyncTooLarge();
      default:
        throw SyncTransportException('PUT ${res.statusCode}');
    }
  }

  String _etag(http.Response res) {
    final etag = res.headers['etag'];
    if (etag == null || etag.isEmpty) {
      throw const SyncTransportException('response had no ETag');
    }
    return etag;
  }

  Future<http.Response> _send(Future<http.Response> Function() op) async {
    try {
      return await op();
    } on http.ClientException catch (e) {
      throw SyncTransportException(e.message);
    }
  }
}
