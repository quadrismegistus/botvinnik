import 'dart:convert';

import 'sync_crypto.dart';

/// What a device remembers between launches once sync is on: the phrase (so it
/// can be shown again — "save your recovery phrase") and the derived keys, so
/// PBKDF2 runs once per device instead of once per sync.
class SyncSession {
  const SyncSession({required this.phrase, required this.keys});

  final String phrase;
  final SyncKeys keys;

  Map<String, dynamic> toJson() => {
        'phrase': phrase,
        'blobId': keys.blobId,
        'encKey': base64.encode(keys.encKey),
      };

  static SyncSession? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SyncSession(
        phrase: m['phrase'] as String,
        keys: SyncKeys(
          blobId: m['blobId'] as String,
          encKey: base64.decode(m['encKey'] as String),
        ),
      );
    } catch (_) {
      // A corrupt row reads as "not set up" rather than crashing launch.
      return null;
    }
  }
}

/// Device-local, non-synced storage for the [SyncSession]. Abstracted so the
/// controller (and its tests) never touch the platform plugin directly; the
/// real Keychain/Keystore/WebCrypto implementation lives in
/// `secure_sync_key_store.dart` and is wired only in main.dart.
abstract class SyncKeyStore {
  Future<SyncSession?> read();
  Future<void> write(SyncSession session);
  Future<void> clear();
}
