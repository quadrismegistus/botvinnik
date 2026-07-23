import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'sync_key_store.dart';

/// The real [SyncKeyStore]: Keychain on iOS/macOS, Keystore on Android,
/// WebCrypto-encrypted localStorage on web. Wired only in main.dart, so the
/// controller and its tests never pull in the platform plugin.
///
/// Every call is best-effort: if the platform store is unavailable — most
/// notably an **unsigned macOS build**, where Keychain access needs a
/// keychain-access-groups entitlement that in turn needs a development
/// certificate this project doesn't have (#67) — a failure degrades to "not
/// persisted" rather than crashing. Sync still works for the session; it just
/// won't survive a relaunch on that device. Web and iOS persist normally.
class SecureSyncKeyStore implements SyncKeyStore {
  SecureSyncKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'botvinnik-sync-session-v1';

  @override
  Future<SyncSession?> read() async {
    try {
      return SyncSession.fromJson(await _storage.read(key: _key));
    } catch (e) {
      debugPrint('sync: could not read the secure store ($e) — treating as off');
      return null;
    }
  }

  @override
  Future<void> write(SyncSession session) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('sync: could not persist to the secure store ($e) — '
          'sync works this session but will not survive a relaunch here');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('sync: could not clear the secure store ($e)');
    }
  }
}
