import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'eff_wordlist.dart';

/// The crypto core of end-to-end-encrypted sync (issue #203).
///
/// One sync phrase roots everything:
///
///     phrase ──PBKDF2(fixed salt)──► root
///                  root ──HKDF(info "…/id/…")──►  blobId  (the server sees this)
///                       └─HKDF(info "…/enc/…")─►  encKey  (never leaves device)
///
/// `blobId` is derived from the phrase too, so an attacker cannot even *locate*
/// a blob in R2 without it — there is no enumerable user list. Same phrase on
/// any device → same `blobId` + `encKey` → same blob; nothing is transferred
/// between screens.
///
/// **Why PBKDF2, not Argon2id.** The KDF has to produce byte-identical output on
/// every target, and on web that means dart2js. Argon2id has no WebCrypto
/// primitive, so it runs in pure Dart there — benchmarked at ~31 s for 64 MiB
/// (M0). PBKDF2-HMAC-SHA256 *is* a WebCrypto primitive, so `crypto.subtle` runs
/// it in ~60 ms on web (and ~2.3 s in pure Dart on native, paid once per device
/// and cached). It is not memory-hard, which the ~77-bit generated phrase and
/// the custom-phrase strength gate (M4) compensate for. Matches the choice the
/// Mothtrap web app landed on for the same reason.
///
/// This layer is deliberately payload-agnostic: [seal] / [open] transform raw
/// bytes, so they know nothing about `BackupService`. The wiring to the backup
/// document and the network is the `SyncService` layer (M3).
class SyncKeys {
  const SyncKeys({required this.blobId, required this.encKey});

  /// R2 object key. base64url, no padding — matches the Worker's
  /// `^[A-Za-z0-9_-]{16,128}$`. 32 bytes → 43 chars.
  final String blobId;

  /// 32-byte key for AES-256-GCM. Never sent to the server.
  final List<int> encKey;
}

/// KDF cost. A value object so a benchmark (M0) can pin it without touching call
/// sites, and so tests can derive cheaply.
class SyncCryptoParams {
  const SyncCryptoParams({required this.iterations});

  /// PBKDF2 iteration count.
  final int iterations;

  /// The shipped cost — OWASP's PBKDF2-HMAC-SHA256 recommendation. ~60 ms on
  /// web (WebCrypto), ~2.3 s in pure Dart on native (M0), paid once per device.
  static const SyncCryptoParams start = SyncCryptoParams(iterations: 600000);
}

class SyncCrypto {
  SyncCrypto._();

  // The blob envelope is self-describing (#203, on Mothtrap's advice): each blob
  // stamps the primitives it was written with, so a device on a different build
  // can still read it, params can migrate, and a hostile envelope can't smuggle
  // an absurd cost past us. These are the only values this build writes/accepts.
  static const int _envelopeVersion = 1;
  static const String _kdfName = 'PBKDF2-SHA256';
  static const String _cipherName = 'AES-256-GCM';
  static const String _zipName = 'gzip';
  // Guard rails for the stamped iteration count read back from an envelope.
  static const int _minIterations = 100000;
  static const int _maxIterations = 2000000;

  // AES-256-GCM with the WebCrypto-standard 12-byte IV, so crypto.subtle handles
  // it on web; 16-byte Poly-style tag appended to the ciphertext.
  static final Cipher _cipher = AesGcm.with256bits(nonceLength: 12);
  static const int _ivLength = 12;
  static const int _tagLength = 16;

  // PBKDF2 needs a salt; sync must be deterministic — the same phrase has to
  // derive the same keys on every device — so the salt is a fixed,
  // domain-separated application constant, not a random per-user value (the blob
  // location is derived from the phrase, so a random salt couldn't be found
  // before the blob it lives in). The phrase itself carries the entropy
  // (≈77 bits when generated); that is why a custom phrase is strength-gated
  // (M4). See #203's threat model.
  static final List<int> _kdfSalt = utf8.encode('botvinnik-sync/pbkdf2/v1');
  // HKDF-Extract is HMAC(salt, IKM); this library's HMAC rejects an empty key,
  // so use a fixed non-empty one. Separation between the two derived keys comes
  // from `info`, not the salt.
  static final List<int> _hkdfSalt = utf8.encode('botvinnik-sync/hkdf/v1');
  static final List<int> _infoBlobId = utf8.encode('botvinnik-sync/id/v1');
  static final List<int> _infoEncKey = utf8.encode('botvinnik-sync/enc/v1');

  /// phrase → `{blobId, encKey}`. Slow by design (PBKDF2); callers derive once
  /// per device and cache the result. [params] is injectable so tests can use a
  /// cheap cost — the derivation *shape* is identical at any cost.
  static Future<SyncKeys> deriveKeys(
    String phrase, {
    SyncCryptoParams params = SyncCryptoParams.start,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: 256,
    );
    final root = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(normalizePhrase(phrase))),
      nonce: _kdfSalt,
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

  /// gzip, then AES-256-GCM encrypt, then wrap in the self-describing JSON
  /// envelope the Worker stores. Non-deterministic (fresh random IV each call).
  /// The envelope header is bound as AEAD associated data, so tampering with the
  /// stamped params is caught, not just tampering with the ciphertext.
  static Future<Uint8List> seal(List<int> encKey, List<int> plaintext) async {
    final compressed = GZipEncoder().encode(plaintext);
    final header = _header(SyncCryptoParams.start.iterations);
    final box = await _cipher.encrypt(
      compressed,
      secretKey: SecretKey(encKey),
      aad: _aad(header),
    );
    final envelope = <String, dynamic>{
      ...header,
      'iv': base64.encode(box.nonce),
      // WebCrypto convention: tag appended to the ciphertext.
      'ct': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// The inverse of [seal]. Throws [SecretBoxAuthenticationError] on a wrong key
  /// or any tampering (ciphertext or stamped header), and [FormatException] on a
  /// malformed or unsupported envelope — never returns garbage.
  static Future<Uint8List> open(List<int> encKey, List<int> sealed) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(sealed));
    } catch (_) {
      throw const FormatException('sync blob is not a valid envelope');
    }
    if (decoded is! Map) {
      throw const FormatException('sync blob is not a valid envelope');
    }

    final iter = decoded['iter'];
    if (decoded['v'] != _envelopeVersion ||
        decoded['kdf'] != _kdfName ||
        decoded['cipher'] != _cipherName ||
        decoded['zip'] != _zipName ||
        decoded['iv'] is! String ||
        decoded['ct'] is! String ||
        iter is! int) {
      throw const FormatException('unsupported sync envelope');
    }
    if (iter < _minIterations || iter > _maxIterations) {
      // A hostile blob can't make us burn CPU on an absurd cost. (This build
      // derives at a fixed cost anyway; the caller's key already reflects it.)
      throw const FormatException('sync envelope iteration count out of range');
    }

    final iv = base64.decode(decoded['iv'] as String);
    final ctTag = base64.decode(decoded['ct'] as String);
    if (iv.length != _ivLength || ctTag.length < _tagLength) {
      throw const FormatException('sync envelope is truncated');
    }
    final box = SecretBox(
      ctTag.sublist(0, ctTag.length - _tagLength),
      nonce: iv,
      mac: Mac(ctTag.sublist(ctTag.length - _tagLength)),
    );

    final compressed = await _cipher.decrypt(
      box,
      secretKey: SecretKey(encKey),
      aad: _aad(_header(iter)),
    );
    return Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
  }

  static Map<String, dynamic> _header(int iterations) => {
        'v': _envelopeVersion,
        'kdf': _kdfName,
        'iter': iterations,
        'cipher': _cipherName,
        'zip': _zipName,
      };

  /// The header fields, canonicalized, bound as AEAD associated data so none of
  /// the stamped params can be altered without failing authentication.
  static List<int> _aad(Map<String, dynamic> header) => utf8.encode(
        'v=${header['v']}|kdf=${header['kdf']}|iter=${header['iter']}'
        '|cipher=${header['cipher']}|zip=${header['zip']}',
      );

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

  /// Normalize a phrase before derivation so trivial differences reach the same
  /// key: trim, lowercase, collapse whitespace, and **NFC-normalize**.
  ///
  /// PBKDF2's output is a pure function of the UTF-8 bytes, and Dart's `String`
  /// applies no Unicode normalization — so the SAME non-ASCII phrase entered NFC
  /// on one device and NFD on another (macOS leans NFD) would otherwise derive
  /// DIFFERENT keys. NFC is applied last so the final bytes are canonical
  /// regardless of what lowercasing produced. ASCII phrases — every generated
  /// one — are unchanged by NFC, so existing keys are unaffected.
  static String normalizePhrase(String phrase) => unorm.nfc(
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' '));
}
