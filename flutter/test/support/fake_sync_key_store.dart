import 'package:botvinnik_mobile/sync/sync_key_store.dart';

/// An in-memory [SyncKeyStore] for tests — stands in for the real Keychain /
/// Keystore / WebCrypto storage, which needs platform channels a unit test
/// doesn't have.
class FakeSyncKeyStore implements SyncKeyStore {
  SyncSession? session;
  int writes = 0;
  int clears = 0;

  @override
  Future<SyncSession?> read() async => session;

  @override
  Future<void> write(SyncSession s) async {
    session = s;
    writes++;
  }

  @override
  Future<void> clear() async {
    session = null;
    clears++;
  }
}
