import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_key_store.dart';

/// The real [SyncKeyStore]: Keychain on iOS/macOS, Keystore on Android,
/// WebCrypto-encrypted localStorage on web. Wired only in main.dart, so the
/// controller and its tests never pull in the platform plugin.
class SecureSyncKeyStore implements SyncKeyStore {
  SecureSyncKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'botvinnik-sync-session-v1';

  @override
  Future<SyncSession?> read() async =>
      SyncSession.fromJson(await _storage.read(key: _key));

  @override
  Future<void> write(SyncSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
