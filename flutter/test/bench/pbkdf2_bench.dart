// M0 benchmark (#203), PBKDF2 arm: unlike Argon2id, PBKDF2 IS a WebCrypto
// primitive, so on web `cryptography_plus` routes it through crypto.subtle and
// it should run near-native. This measures whether a high-iteration PBKDF2 is
// fast enough to be the uniform cross-platform KDF. Run:
//
//   flutter test --platform chrome test/bench/pbkdf2_bench.dart
//   flutter test test/bench/pbkdf2_bench.dart   # VM, for contrast

import 'dart:convert';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _timeMs(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMilliseconds;
}

Future<void> _derive(int iterations) async {
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode('device pairing phrase')),
    nonce: utf8.encode('botvinnik-sync/pbkdf2/v1'),
  );
}

void main() {
  const candidates = <(String, int)>[
    ('PBKDF2-HMAC-SHA256  300k', 300000),
    ('PBKDF2-HMAC-SHA256  600k', 600000),
    ('PBKDF2-HMAC-SHA256 1200k', 1200000),
  ];

  test('pbkdf2 derive timings', () async {
    await _derive(100000); // warm up
    for (final (label, iters) in candidates) {
      final samples = <int>[];
      for (var i = 0; i < 3; i++) {
        samples.add(await _timeMs(() => _derive(iters)));
      }
      samples.sort();
      // ignore: avoid_print
      print('$label  ->  median ${samples[1]} ms   (samples $samples)');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
