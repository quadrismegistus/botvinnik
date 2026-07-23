import 'dart:convert';
import 'dart:math';

import 'package:botvinnik_mobile/sync/eff_wordlist.dart';
import 'package:botvinnik_mobile/sync/sync_crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';

// PBKDF2 at the shipped 600k cost is slow on purpose; the derivation *shape*
// (determinism, key separation, phrase sensitivity) is identical at any cost, so
// the logic tests run it cheaply. The real number is guarded separately.
const _fast = SyncCryptoParams(iterations: 1000);

void main() {
  group('deriveKeys', () {
    test('is deterministic — same phrase, same keys', () async {
      final a = await SyncCrypto.deriveKeys('correct horse battery', params: _fast);
      final b = await SyncCrypto.deriveKeys('correct horse battery', params: _fast);
      expect(a.blobId, b.blobId);
      expect(a.encKey, b.encKey);
    });

    test('blobId is a paddingless base64url string of the right shape', () async {
      final k = await SyncCrypto.deriveKeys('one two three', params: _fast);
      expect(k.blobId, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
      expect(k.blobId.length, 43); // 32 bytes base64url, no '='
      expect(k.encKey.length, 32);
    });

    test('blobId and encKey are independent — the id never leaks the key', () async {
      final k = await SyncCrypto.deriveKeys('alpha bravo charlie', params: _fast);
      final idBytes = base64Url.decode('${k.blobId}='); // repad 43 -> 44
      expect(idBytes, isNot(equals(k.encKey)));
    });

    test('a different phrase yields different keys', () async {
      final a = await SyncCrypto.deriveKeys('alpha bravo charlie', params: _fast);
      final b = await SyncCrypto.deriveKeys('alpha bravo delta', params: _fast);
      expect(a.blobId, isNot(b.blobId));
      expect(a.encKey, isNot(b.encKey));
    });

    test('normalization: case and stray whitespace reach the same key', () async {
      final messy = await SyncCrypto.deriveKeys('  Correct   Horse ', params: _fast);
      final clean = await SyncCrypto.deriveKeys('correct horse', params: _fast);
      expect(messy.blobId, clean.blobId);
      expect(messy.encKey, clean.encKey);
    });

    test('the shipped KDF cost is the #203 / OWASP number', () {
      expect(SyncCryptoParams.start.iterations, 600000);
    });

    test('NFC-normalizes so NFD and NFC inputs derive the same key', () async {
      // e-acute composed (NFC, U+00E9) vs decomposed (NFD, e + U+0301).
      const composed = 'caf\u00e9 mountain river stone';
      const decomposed = 'cafe\u0301 mountain river stone';
      expect(composed == decomposed, isFalse); // different code units...
      final a = await SyncCrypto.deriveKeys(composed, params: _fast);
      final b = await SyncCrypto.deriveKeys(decomposed, params: _fast);
      expect(a.blobId, b.blobId); // ...but the same derived key
      expect(a.encKey, b.encKey);
    });

    test('normalizePhrase canonicalizes to NFC and leaves ASCII untouched', () {
      expect(SyncCrypto.normalizePhrase('cafe\u0301'), 'caf\u00e9'); // NFD -> NFC
      expect(SyncCrypto.normalizePhrase('One Two Three'), 'one two three');
    });
  });

  group('seal / open', () {
    late List<int> key;
    setUp(() async {
      key = (await SyncCrypto.deriveKeys('sealing key phrase', params: _fast)).encKey;
    });

    test('round-trips arbitrary bytes', () async {
      final plain = utf8.encode('{"games":[{"id":"g-1"}],"practice":[]}');
      final recovered = await SyncCrypto.open(key, await SyncCrypto.seal(key, plain));
      expect(recovered, plain);
    });

    test('writes a self-describing envelope', () async {
      final env = jsonDecode(utf8.decode(await SyncCrypto.seal(key, utf8.encode('x'))))
          as Map<String, dynamic>;
      expect(env['v'], 1);
      expect(env['kdf'], 'PBKDF2-SHA256');
      expect(env['cipher'], 'AES-256-GCM');
      expect(env['zip'], 'gzip');
      expect(env['iter'], 600000);
      expect(base64.decode(env['iv'] as String).length, 12);
    });

    test('the ciphertext is neither the plaintext nor deterministic', () async {
      final plain = utf8.encode('the same message twice');
      final a = await SyncCrypto.seal(key, plain);
      final b = await SyncCrypto.seal(key, plain);
      expect(a, isNot(b)); // fresh IV each time
      expect(await SyncCrypto.open(key, a), plain);
      expect(await SyncCrypto.open(key, b), plain);
    });

    test('gzip runs before encryption — repetitive input shrinks', () async {
      final repetitive = utf8.encode('ab' * 8192); // 16 KB, highly compressible
      final sealed = await SyncCrypto.seal(key, repetitive);
      expect(sealed.length, lessThan(repetitive.length));
      expect(await SyncCrypto.open(key, sealed), repetitive);
    });

    test('open rejects a wrong key', () async {
      final other =
          (await SyncCrypto.deriveKeys('a different phrase', params: _fast)).encKey;
      final sealed = await SyncCrypto.seal(key, utf8.encode('secret'));
      expect(
        () => SyncCrypto.open(other, sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects tampered ciphertext', () async {
      final env = jsonDecode(utf8.decode(await SyncCrypto.seal(key, utf8.encode('secret'))))
          as Map<String, dynamic>;
      final ct = base64.decode(env['ct'] as String);
      ct[0] ^= 0x01; // flip a byte of the ciphertext
      env['ct'] = base64.encode(ct);
      expect(
        () => SyncCrypto.open(key, utf8.encode(jsonEncode(env))),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects a tampered header (AAD binds the stamped params)', () async {
      final env = jsonDecode(utf8.decode(await SyncCrypto.seal(key, utf8.encode('secret'))))
          as Map<String, dynamic>;
      env['iter'] = 500000; // still in range, but not what it was sealed with
      expect(
        () => SyncCrypto.open(key, utf8.encode(jsonEncode(env))),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects a malformed or unsupported envelope', () async {
      expect(
        () => SyncCrypto.open(key, utf8.encode('not an envelope')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SyncCrypto.open(key, utf8.encode(jsonEncode({'v': 1, 'kdf': 'scrypt'}))),
        throwsA(isA<FormatException>()),
      );
    });

    test('open rejects an absurd iteration count before deriving anything', () async {
      final env = jsonDecode(utf8.decode(await SyncCrypto.seal(key, utf8.encode('x'))))
          as Map<String, dynamic>;
      env['iter'] = 999999999; // hostile: would burn CPU if we honoured it
      expect(
        () => SyncCrypto.open(key, utf8.encode(jsonEncode(env))),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('generatePhrase', () {
    test('defaults to six words, all from the EFF list', () {
      final words = SyncCrypto.generatePhrase().split(' ');
      expect(words, hasLength(6));
      final vocab = effLargeWordlist.toSet();
      expect(words.every(vocab.contains), isTrue);
    });

    test('honours the word count', () {
      expect(SyncCrypto.generatePhrase(words: 4).split(' '), hasLength(4));
    });

    test('is reproducible under an injected RNG (so the UI can be tested)', () {
      final a = SyncCrypto.generatePhrase(random: Random(42));
      final b = SyncCrypto.generatePhrase(random: Random(42));
      expect(a, b);
    });

    test('a generated phrase derives keys and normalizes to itself', () async {
      final phrase = SyncCrypto.generatePhrase(random: Random(7));
      expect(SyncCrypto.normalizePhrase(phrase), phrase); // already clean ASCII
      final k = await SyncCrypto.deriveKeys(phrase, params: _fast);
      expect(k.blobId, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
    });
  });

  test('the embedded wordlist is the full EFF large list', () {
    expect(effLargeWordlist, hasLength(7776));
    expect(effLargeWordlist.first, 'abacus');
    expect(effLargeWordlist.last, 'zoom');
    expect(effLargeWordlist.toSet(), hasLength(7776)); // no duplicates
  });
}
