// M0 benchmark (#203), Argon2id arm — the road NOT taken, kept as evidence.
//
// Argon2id has no WebCrypto primitive, so on web it runs in pure Dart. This
// measured ~13 s (32 MiB) / ~31 s (64 MiB) in headless Chrome — unusable, and
// the reason the KDF is PBKDF2 (see pbkdf2_bench.dart, which is fast on web via
// crypto.subtle). Because the sync blobId is derived from the phrase, the KDF
// can't be platform-split, so a web-hostile KDF is a whole-feature blocker.
//
// Self-contained (calls cryptography_plus directly, not SyncCrypto) so it keeps
// compiling as the sync API evolves. Not a `_test.dart` file: excluded from CI.
//
//   flutter test test/bench/argon2id_bench.dart                    # Dart VM
//   flutter test --platform chrome test/bench/argon2id_bench.dart  # dart2js in Chrome

import 'dart:convert';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _timeMs(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMilliseconds;
}

Future<void> _derive(int memoryKib) async {
  final argon = Argon2id(
    memory: memoryKib,
    iterations: 3,
    parallelism: 1,
    hashLength: 32,
  );
  await argon.deriveKey(
    secretKey: SecretKey(utf8.encode('device pairing phrase')),
    nonce: utf8.encode('botvinnik-sync/argon2id/v1'),
  );
}

void main() {
  const candidates = <(String, int)>[
    ('Argon2id 32 MiB / t=3', 32 * 1024),
    ('Argon2id 64 MiB / t=3', 64 * 1024),
  ];

  test('argon2id derive-key timings', () async {
    await _derive(candidates.first.$2); // warm up
    for (final (label, memoryKib) in candidates) {
      final samples = <int>[];
      for (var i = 0; i < 3; i++) {
        samples.add(await _timeMs(() => _derive(memoryKib)));
      }
      samples.sort();
      // ignore: avoid_print
      print('$label  ->  median ${samples[1]} ms   (samples $samples)');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
