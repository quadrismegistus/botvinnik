// The Maia weights cache: the prefetch (#130), the single downloader behind
// it, and the guarantee the prefetch has to earn — that a download NOBODY
// ASKED FOR cannot damage the one somebody is waiting on.
//
// Fakes the network at [MaiaWeights.debugOpen], which is one layer above the
// socket and one below everything worth testing: the progress steps, the
// `.part` write and rename, the single in-flight future per band and the
// cached-band set are all the real code here.
//
//   cd flutter && flutter test test/maia_weights_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/maia_progress.dart';
import 'package:botvinnik_mobile/engine/maia_weights_io.dart';

/// A stand-in HuggingFace. Counts requests per band, and can fail in the two
/// ways that matter: refusing to open, and dying halfway through a body.
class _FakeServer {
  /// A stand-in for 3.5MB, in four chunks.
  static const int size = 4096;

  final Map<int, int> requests = {};
  int closes = 0;

  /// Thrown from `open`, as a refused connection or a non-200 would be.
  Object? openError;

  /// Cut the body off after the second of four chunks.
  bool breakMidway = false;

  /// Held before the first chunk of every body, so a test can put two callers
  /// on the same download at once.
  Completer<void>? gate;

  /// Thrown from the body stream, after any [gate] releases — the shape a
  /// per-chunk timeout has.
  Object? chunkError;

  Future<MaiaBody> open(Uri url) async {
    final band = int.parse(RegExp(r'maia-(\d+)').firstMatch('$url')!.group(1)!);
    requests.update(band, (n) => n + 1, ifAbsent: () => 1);
    final error = openError;
    if (error != null) throw error;
    return MaiaBody(
      chunks: _chunks(band),
      contentLength: size,
      close: () => closes++,
    );
  }

  Stream<List<int>> _chunks(int band) async* {
    final held = gate;
    if (held != null) await held.future;
    final ce = chunkError;
    if (ce != null) throw ce;
    final chunk = List<int>.filled(size ~/ 4, band % 251);
    for (var i = 0; i < 4; i++) {
      if (breakMidway && i == 2) {
        throw const SocketException('connection reset by peer');
      }
      yield chunk;
    }
  }
}

/// Let the real file I/O in the code under test actually happen — it goes to
/// a thread pool, so a microtask drain is not enough.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _FakeServer server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('maia-weights-test');
    server = _FakeServer();
    MaiaWeights.debugReset();
    MaiaWeights.debugDirectory = root;
    MaiaWeights.debugOpen = server.open;
  });

  tearDown(() async {
    MaiaWeights.debugReset();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  File cacheFile(int band) => File('${root.path}/maia/maia-$band.onnx');

  test('the prefetch fetches all three bands and marks them cached', () async {
    await MaiaWeights.prefetch();

    expect(server.requests, {1100: 1, 1500: 1, 1900: 1},
        reason: 'three bands cover six personas — no more, no fewer');
    for (final band in MaiaWeights.bands) {
      expect(cacheFile(band).existsSync(), isTrue, reason: 'maia-$band');
      expect(cacheFile(band).lengthSync(), _FakeServer.size);
    }
    expect(MaiaWeights.cached.value, {1100, 1500, 1900});
    expect(server.closes, 3, reason: 'every body releases its client');
  });

  test('a later launch downloads nothing it already has', () async {
    await MaiaWeights.prefetch();
    // A fresh process over the same Application Support directory.
    MaiaWeights.debugReset();
    MaiaWeights.debugDirectory = root;
    MaiaWeights.debugOpen = server.open;

    await MaiaWeights.prefetch();
    expect(server.requests, {1100: 1, 1500: 1, 1900: 1},
        reason: 'the cache is a real file — one connected session is enough');
    expect(MaiaWeights.cached.value, {1100, 1500, 1900});
  });

  // The load-bearing one. A prefetch is speculative: it must be incapable of
  // making the on-demand path worse than if it had never run.
  test('a prefetch that fails leaves the on-demand path exactly as it was',
      () async {
    server.openError = const SocketException('network is unreachable');
    await MaiaWeights.prefetch();

    expect(server.requests, {1100: 1, 1500: 1, 1900: 1},
        reason: 'each band is tried once and given up on, not retried');
    for (final band in MaiaWeights.bands) {
      expect(cacheFile(band).existsSync(), isFalse);
      expect(File('${cacheFile(band).path}.part').existsSync(), isFalse,
          reason: 'a failed prefetch leaves no half-file to be read as a hit');
    }
    // Not null: the picker can now say "not downloaded" rather than shrugging.
    expect(MaiaWeights.cached.value, <int>{});

    // Once per process, whoever calls it — and asserted HERE, where a missing
    // latch is visible: after a SUCCESSFUL prefetch a second run makes no
    // requests anyway, because the files are on disk.
    await MaiaWeights.prefetch();
    expect(server.requests, {1100: 1, 1500: 1, 1900: 1},
        reason: 'the picker calls prefetch every time it opens; a device with '
            'no network must not start three downloads each time');

    // And now the move that actually wants a band gets it, from a path the
    // failed prefetch has not latched, counted or poisoned.
    server.openError = null;
    final bytes = await MaiaWeights.load(1100);
    expect(bytes.length, _FakeServer.size);
    expect(cacheFile(1100).existsSync(), isTrue);
    expect(server.requests[1100], 2, reason: 'the demand fetch really ran');
    expect(MaiaWeights.cached.value, {1100});
  });

  test('an interrupted download leaves no cache and no orphan', () async {
    server.breakMidway = true;
    await expectLater(MaiaWeights.load(1900), throwsA(isA<SocketException>()),
        reason: 'the caller must see the failure, not a truncated model');

    expect(cacheFile(1900).existsSync(), isFalse);
    expect(File('${cacheFile(1900).path}.part').existsSync(), isFalse);
    expect(MaiaWeights.cached.value, isNull,
        reason: 'nothing has looked at the directory, which is not the same '
            'as having looked and found nothing');

    // The band is not dead: this layer counts nothing and latches nothing.
    server.breakMidway = false;
    expect((await MaiaWeights.load(1900)).length, _FakeServer.size);
  });

  test('a move joins the prefetch download rather than starting a second',
      () async {
    final gate = Completer<void>();
    server.gate = gate;
    final prefetching = MaiaWeights.prefetch();
    await _settle();
    expect(server.requests[1100], 1, reason: 'the prefetch is on 1100');

    final progress = <MaiaProgress>[];
    final demand = MaiaWeights.load(1100, onProgress: progress.add);
    await _settle();
    gate.complete();

    expect((await demand).length, _FakeServer.size);
    await prefetching;
    expect(server.requests[1100], 1,
        reason: 'two downloaders renaming the same .part is the corruption '
            'the rename exists to prevent');
    expect(progress.map((p) => p.phase), contains('fetching'),
        reason: 'a move that joins a download still gets its bar');
    expect(cacheFile(1100).existsSync(), isTrue);
  });

  test('a JOINED failure is distinguishable from one you started', () async {
    // The bug this closes. A move that joins a prefetch inherits that
    // download's error INCLUDING ITS CLOCK — a prefetch started at boot and
    // timing out at t=30s hands its TimeoutException to a move that arrived at
    // t=29s. MaiaEngine latches a TimeoutException into _deadBands, so a
    // background download nobody asked for retired a persona for the whole
    // session, and never retried even once the network recovered.
    //
    // Wrapping it is what lets the latch tell the difference. It is NOT a
    // TimeoutException, so `e is TimeoutException` no longer matches.
    final gate = Completer<void>();
    server.gate = gate;
    server.chunkError = TimeoutException("the prefetch's own 30s");

    final prefetching = MaiaWeights.prefetch();
    await _settle();
    final demand = MaiaWeights.load(1100); // joins the in-flight download
    await _settle();
    gate.complete();

    await expectLater(demand, throwsA(isA<JoinedDownloadFailure>()));
    await prefetching; // prefetch swallows its own failures by design

    // And a caller that STARTS its own download still sees the raw error, so
    // the latch keeps working for the case it was written for.
    server.gate = null;
    await expectLater(
        MaiaWeights.load(1500), throwsA(isA<TimeoutException>()));
  });

  test('the prefetch waits for a download a move is watching', () async {
    final gate = Completer<void>();
    server.gate = gate;
    final demand = MaiaWeights.load(1500);
    await _settle();
    expect(server.requests.keys, [1500]);

    final prefetching = MaiaWeights.prefetch();
    await _settle();
    expect(server.requests.keys, [1500],
        reason: 'a download nobody asked for must not compete for the pipe '
            'with the one somebody is waiting on');

    gate.complete();
    server.gate = null;
    await demand;
    await prefetching;
    expect(server.requests, {1100: 1, 1500: 1, 1900: 1},
        reason: 'and it picks up the rest afterwards, without refetching the '
            'band the move already landed');
  });

  test('discard drops the file and the mark', () async {
    await MaiaWeights.load(1100);
    // The first band to land with nothing yet known about the directory sends
    // the cache off to LOOK rather than asserting the other two are absent.
    await _settle();
    expect(MaiaWeights.cached.value, {1100});

    await MaiaWeights.discard(1100);
    expect(cacheFile(1100).existsSync(), isFalse);
    expect(MaiaWeights.cached.value, <int>{});
  });
}
