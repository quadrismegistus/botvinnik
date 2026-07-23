import 'dart:convert';
import 'dart:math';

import 'package:botvinnik_mobile/sync/eff_wordlist.dart';
import 'package:botvinnik_mobile/sync/sync_crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';

// Argon2id at the shipped 64 MiB cost is slow on purpose; the derivation *shape*
// (determinism, key separation, phrase sensitivity) is identical at any cost, so
// the logic tests run it cheaply. The real numbers are guarded separately.
const _fast = SyncCryptoParams(memoryKib: 256, iterations: 1, parallelism: 1);

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

    test('the shipped Argon2id params are the #203 starting numbers', () {
      expect(SyncCrypto.deriveKeys, isNotNull); // uses SyncCryptoParams.start by default
      expect(SyncCryptoParams.start.memoryKib, 64 * 1024);
      expect(SyncCryptoParams.start.iterations, 3);
      expect(SyncCryptoParams.start.parallelism, 1);
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

    test('the sealed blob is neither the plaintext nor deterministic', () async {
      final plain = utf8.encode('the same message twice');
      final a = await SyncCrypto.seal(key, plain);
      final b = await SyncCrypto.seal(key, plain);
      expect(a, isNot(plain)); // encrypted, not passthrough
      expect(a, isNot(b)); // fresh nonce each time
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

    test('open rejects a tampered blob', () async {
      final sealed = await SyncCrypto.seal(key, utf8.encode('secret'));
      sealed[sealed.length ~/ 2] ^= 0x01; // flip one bit past the nonce
      expect(
        () => SyncCrypto.open(key, sealed),
        throwsA(isA<SecretBoxAuthenticationError>()),
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
      expect(SyncCrypto.normalizePhrase(phrase), phrase); // already clean
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
