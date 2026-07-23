import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_key_store.dart';

/// The real [SyncKeyStore], wired only in main.dart so the controller and its
/// tests never pull in the platform plugins.
///
/// It prefers the platform **secure** store — Keychain on iOS/macOS,
/// WebCrypto-encrypted localStorage on web — for defence in depth. But that is
/// unavailable on an **unsigned macOS build** (Keychain wants a
/// keychain-access-groups entitlement, which needs a signing certificate this
/// project doesn't have — #67), and on web only in a **secure context**
/// (HTTPS/localhost — which `botvinnik.app` is), so it falls back to plain
/// `shared_preferences` where the secure store is missing.
///
/// Falling back to plaintext is safe here: the device already stores the games
/// and practice **unencrypted** in its local database, so a key sitting beside
/// them grants an attacker with local file access nothing they didn't already
/// have. The encryption protects the data *from the server*, not from the owner
/// of the machine — which is exactly why persisting the key locally (as the
/// Mothtrap web app also does) is the right call rather than re-deriving or
/// re-prompting every launch.
class SecureSyncKeyStore implements SyncKeyStore {
  SecureSyncKeyStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;
  static const String _key = 'botvinnik-sync-session-v1';

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<SyncSession?> read() async {
    try {
      final secure = await _secure.read(key: _key);
      if (secure != null) return SyncSession.fromJson(secure);
    } catch (e) {
      debugPrint('sync: secure read failed ($e) — trying local fallback');
    }
    try {
      return SyncSession.fromJson((await _prefsInstance()).getString(_key));
    } catch (e) {
      debugPrint('sync: local read failed ($e) — treating as off');
      return null;
    }
  }

  @override
  Future<void> write(SyncSession session) async {
    final json = jsonEncode(session.toJson());
    try {
      await _secure.write(key: _key, value: json);
      // Clear any stale plaintext fallback from a time the secure store was
      // unavailable — otherwise a later transient secure-read failure could
      // resurrect an old session (a different, abandoned blob).
      try {
        await (await _prefsInstance()).remove(_key);
      } catch (_) {}
      return; // stored in the secure store; done
    } catch (e) {
      debugPrint('sync: secure write failed ($e) — persisting to local fallback '
          '(safe: the games are already stored locally in plaintext)');
    }
    try {
      await (await _prefsInstance()).setString(_key, json);
    } catch (e) {
      debugPrint('sync: local write failed ($e) — session not persisted');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _secure.delete(key: _key);
    } catch (e) {
      debugPrint('sync: secure clear failed ($e)');
    }
    try {
      await (await _prefsInstance()).remove(_key);
    } catch (e) {
      debugPrint('sync: local clear failed ($e)');
    }
  }
}
