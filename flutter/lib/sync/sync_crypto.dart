import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography_plus/cryptography_plus.dart';

import 'eff_wordlist.dart';

/// The crypto core of end-to-end-encrypted sync (issue #203).
///
/// One sync phrase roots everything:
///
///     phrase ──Argon2id(fixed salt)──► root
///                  root ──HKDF(info: "…/id/…")──►  blobId  (the server sees this)
///                       └─HKDF(info: "…/enc/…")─►  encKey  (never leaves device)
///
/// `blobId` is derived from the phrase too, so an attacker cannot even *locate*
/// a blob in R2 without it — there is no enumerable user list. Same phrase on
/// any device → same `blobId` + `encKey` → same blob; nothing is transferred
/// between screens.
///
/// This layer is deliberately payload-agnostic: [seal] / [open] transform raw
/// bytes, so they know nothing about `BackupService`. The wiring to the backup
/// document and the network is the `SyncService` layer (M3).
class SyncKeys {
  const SyncKeys({required this.blobId, required this.encKey});

  /// R2 object key. base64url, no padding — matches the Worker's
  /// `^[A-Za-z0-9_-]{16,128}$`. 32 bytes → 43 chars.
  final String blobId;

  /// 32-byte key for XChaCha20-Poly1305. Never sent to the server.
  final List<int> encKey;
}

/// Argon2id cost. Deliberately a value object so a benchmark (M0) can pin it
/// per platform without touching call sites.
class SyncCryptoParams {
  const SyncCryptoParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  /// Argon2 memory cost, in KiB (the unit the algorithm takes).
  final int memoryKib;
  final int iterations;
  final int parallelism;

  /// The starting point from #203, run once per device then cached. The web
  /// path runs Argon2id in pure Dart (WebCrypto has no Argon2id), so M0 still
  /// has to confirm this is tolerable on WASM and drop to 32 MiB if not.
  static const SyncCryptoParams start = SyncCryptoParams(
    memoryKib: 64 * 1024,
    iterations: 3,
    parallelism: 1,
  );
}

class SyncCrypto {
  SyncCrypto._();

  // XChaCha20-Poly1305: a 24-byte random nonce (large enough that random
  // generation never collides) and a 16-byte Poly1305 tag.
  static final Cipher _cipher = Xchacha20.poly1305Aead();
  static const int _macLength = 16;

  // Argon2id needs a salt, but sync must be deterministic — the same phrase has
  // to derive the same keys on every device — so the salt is a fixed,
  // domain-separated application constant, not a random per-user value. The
  // phrase itself carries the entropy (≈77 bits when generated); that is also
  // why a custom phrase is gated on strength (M4). See #203's threat model.
  static final List<int> _argonSalt =
      utf8.encode('botvinnik-sync/argon2id/v1');
  // HKDF-Extract is HMAC(salt, IKM). RFC 5869 permits an empty salt, but this
  // library's HMAC rejects an empty key, so use a fixed non-empty one. Domain
  // separation between the two derived keys comes from `info`, not the salt.
  static final List<int> _hkdfSalt = utf8.encode('botvinnik-sync/hkdf/v1');
  static final List<int> _infoBlobId = utf8.encode('botvinnik-sync/id/v1');
  static final List<int> _infoEncKey = utf8.encode('botvinnik-sync/enc/v1');

  /// phrase → `{blobId, encKey}`. Slow by design (Argon2id); callers derive
  /// once per device and cache the result. [params] is injectable so tests can
  /// use a cheap cost — the derivation *shape* is identical at any cost.
  static Future<SyncKeys> deriveKeys(
    String phrase, {
    SyncCryptoParams params = SyncCryptoParams.start,
  }) async {
    final argon = Argon2id(
      memory: params.memoryKib,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: 32,
    );
    final root = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(normalizePhrase(phrase))),
      nonce: _argonSalt,
    );

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final idBytes = await (await hkdf.deriveKey(
      secretKey: root,
      nonce: _hkdfSalt,
      info: _infoBlobId,
    ))
        .extractBytes();
    final encBytes = await (await hkdf.deriveKey(
      secretKey: root,
      nonce: _hkdfSalt,
      info: _infoEncKey,
    ))
        .extractBytes();

    return SyncKeys(
      blobId: base64Url.encode(idBytes).replaceAll('=', ''),
      encKey: encBytes,
    );
  }

  /// gzip then encrypt: the blob body the Worker stores, `nonce ‖ ct ‖ mac`.
  /// Non-deterministic (fresh random nonce each call).
  static Future<Uint8List> seal(List<int> encKey, List<int> plaintext) async {
    final compressed = GZipEncoder().encode(plaintext);
    final box = await _cipher.encrypt(compressed, secretKey: SecretKey(encKey));
    return Uint8List.fromList(box.concatenation());
  }

  /// The inverse of [seal]. Throws [SecretBoxAuthenticationError] if the bytes
  /// were tampered with or the key is wrong — never returns garbage.
  static Future<Uint8List> open(List<int> encKey, List<int> sealed) async {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _cipher.nonceLength,
      macLength: _macLength,
    );
    final compressed =
        await _cipher.decrypt(box, secretKey: SecretKey(encKey));
    return Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
  }

  /// A fresh diceware phrase: [words] words drawn uniformly from the EFF large
  /// list. Six words ≈ 77 bits. [random] is injectable for tests; production
  /// uses [Random.secure].
  static String generatePhrase({int words = 6, Random? random}) {
    final rng = random ?? Random.secure();
    return List.generate(
      words,
      (_) => effLargeWordlist[rng.nextInt(effLargeWordlist.length)],
    ).join(' ');
  }

  /// Normalize a phrase before derivation so trivial typing differences (case,
  /// stray or repeated whitespace) still reach the same key. Applied to both
  /// generated and typed phrases, so it can never cause a mismatch between a
  /// phrase as shown and the same phrase as re-entered.
  static String normalizePhrase(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
}
