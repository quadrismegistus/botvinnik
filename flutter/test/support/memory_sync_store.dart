import 'dart:typed_data';

import 'package:botvinnik_mobile/sync/sync_store.dart';

/// An in-memory [SyncStore] with the Worker's exact compare-and-swap semantics,
/// for tests. Etags are a monotonic counter; a create fails if the blob exists,
/// an update fails unless its etag is still current.
class MemorySyncStore implements SyncStore {
  final Map<String, _Entry> _blobs = {};
  int _seq = 0;

  /// Total committed writes — lets a test tell a retried write apart from a
  /// clean one.
  int writes = 0;

  /// Fires once, immediately before the next [update] evaluates its
  /// precondition. The seam for simulating a concurrent writer slipping in
  /// between a device's GET and its PUT; it clears itself after running.
  Future<void> Function()? onBeforeUpdate;

  @override
  Future<StoredBlob?> get(String blobId) async {
    final e = _blobs[blobId];
    return e == null ? null : StoredBlob(Uint8List.fromList(e.bytes), e.etag);
  }

  @override
  Future<String> create(String blobId, List<int> body) async {
    if (_blobs.containsKey(blobId)) throw const SyncConflict();
    return _commit(blobId, body);
  }

  @override
  Future<String> update(String blobId, List<int> body, String etag) async {
    final hook = onBeforeUpdate;
    if (hook != null) {
      onBeforeUpdate = null;
      await hook();
    }
    final e = _blobs[blobId];
    if (e == null || e.etag != etag) throw const SyncConflict();
    return _commit(blobId, body);
  }

  String _commit(String blobId, List<int> body) {
    final etag = 'e${++_seq}';
    _blobs[blobId] = _Entry(List<int>.from(body), etag);
    writes++;
    return etag;
  }
}

class _Entry {
  _Entry(this.bytes, this.etag);
  final List<int> bytes;
  final String etag;
}
