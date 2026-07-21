// The Maia weights cache on macOS/iOS: which bands are on disk, how they get
// there, and the one place that downloads them.
//
// Split out of maia_engine_io.dart for two reasons, both structural:
//
//   * The ROSTER PICKER needs to know what is cached, and importing the engine
//     for that would drag ORT and JavaScriptCore into a bottom sheet.
//   * The download is now started from two directions — a move that needs a
//     band, and the prefetch below — and two downloaders of the same 3.5MB
//     file racing to rename the same `.part` is exactly the corruption the
//     rename was there to prevent. One owner, one in-flight future per band.
//
// PREFETCH, not bundle (#130). The nets stay a runtime fetch, so
// THIRD-PARTY-NOTICES.md's claim that they are never redistributed with a
// build stays true as written; and #30's decision not to ship them is not
// walked back on the platforms where the payload happens to be cheap. What
// changes is only WHEN the fetch happens: once, quietly, on a connected
// session, instead of in front of somebody waiting for a move — after which
// the file under Application Support survives relaunches and all six Maia
// personas play offline.
//
// The web does none of this: see maia_weights_web.dart.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'maia_progress.dart';

/// Community pre-conversions of the CSSLab lc0 weights, one repo per band —
/// the same URLs the web worker uses. GPL-3.0, which is why they are fetched
/// rather than redistributed with the app (see ARCHITECTURE.md), and why this
/// is the app's only third-party request on native as well.
String maiaModelUrl(int band) =>
    'https://huggingface.co/shermansiu/maia-$band/resolve/main/model.onnx';

/// 30s matches the web worker: a 3.5MB body that has not landed in thirty
/// seconds is not about to. Applied per chunk, so a stalled connection is
/// caught rather than only a slow one.
const Duration kMaiaLoadTimeout = Duration(seconds: 30);

/// A weights response, opened but not yet read.
///
/// This is the seam a test fakes: everything past it — the progress steps, the
/// `.part` write and rename, what a half-arrived download leaves behind — is
/// the real code, and none of it needs a network to exercise.
/// A failure that belonged to a download this caller merely JOINED — most often
/// a background prefetch.
///
/// The distinction is load-bearing. `MaiaEngine._net` latches a
/// `TimeoutException` into `_deadBands`, on the sound reasoning that a network
/// which accepts and never answers costs 30s per move. But a joiner inherits
/// the ORIGINAL download's clock: a prefetch that started at boot and times out
/// at t=30s hands that timeout to a move that arrived at t=29s, after one
/// second of its own waiting. Latching it kills a persona the player has only
/// just chosen, because of a download nobody asked for — and it never retries,
/// even if the network recovers a second later.
///
/// So a joined failure is wrapped, the caller can tell, and the decision to
/// give up belongs to whoever actually waited.
class JoinedDownloadFailure implements Exception {
  JoinedDownloadFailure(this.cause);
  final Object cause;
  @override
  String toString() => 'JoinedDownloadFailure($cause)';
}

class MaiaBody {
  const MaiaBody({
    required this.chunks,
    required this.contentLength,
    this.close,
  });

  final Stream<List<int>> chunks;

  /// -1 when the server sent no content-length, matching HttpClientResponse.
  final int contentLength;

  /// Released when the body has been consumed or abandoned. The HTTP client
  /// outlives the request that opened it and has to be closed by whoever
  /// finishes with the stream, not by whoever opened it.
  final void Function()? close;
}

typedef MaiaOpen = Future<MaiaBody> Function(Uri url);

/// Where a band's weights live, and how they get there.
class MaiaWeights {
  MaiaWeights._();

  /// The three nets behind six personas: Maia I/V/IX and their sampled twins
  /// share a band each, so three downloads cover the whole family.
  static const List<int> bands = [1100, 1500, 1900];

  static final ValueNotifier<Set<int>?> _cached = ValueNotifier(null);

  /// Bands whose weights are on disk — or null for "nobody has looked yet".
  ///
  /// The null is the point. An empty set says "none of them are cached", which
  /// is a claim; before [refresh] runs, and forever on the web, the honest
  /// answer is that we do not know, and the picker says a different thing for
  /// each.
  static ValueListenable<Set<int>?> get cached => _cached;

  /// One download per band at a time, whoever asked for it.
  static final Map<int, Future<Uint8List>> _inFlight = {};

  /// Who wants to hear about a band's progress. A set rather than a single
  /// callback because a move can join a download the prefetch started, and it
  /// should still get the bar rather than a mystery pause.
  static final Map<int, Set<void Function(MaiaProgress)>> _listeners = {};

  static Future<void>? _prefetch;

  @visibleForTesting
  static MaiaOpen? debugOpen;

  @visibleForTesting
  static Directory? debugDirectory;

  /// For a widget test about what the picker SAYS, which should not depend on
  /// a temporary directory to say it.
  @visibleForTesting
  static void debugSetCached(Set<int>? value) => _cached.value = value;

  @visibleForTesting
  static void debugReset() {
    debugOpen = null;
    debugDirectory = null;
    _prefetch = null;
    _inFlight.clear();
    _listeners.clear();
    _cached.value = null;
  }

  static Future<File> fileFor(int band) async {
    final dir = debugDirectory ?? await getApplicationSupportDirectory();
    return File('${dir.path}/maia/maia-$band.onnx');
  }

  /// Re-read the cache directory into [cached].
  ///
  /// Never throws: in a widget test there is no path_provider plugin to
  /// answer, and a picker that cannot say what is cached should fall back to
  /// saying nothing rather than fail to open.
  static Future<void> refresh() async {
    try {
      final found = <int>{};
      for (final band in bands) {
        if (await (await fileFor(band)).exists()) found.add(band);
      }
      _cached.value = found;
    } catch (e) {
      debugPrint('[maia] cache unreadable: $e');
    }
  }

  /// Fetch every band that is not already on disk, once per process.
  ///
  /// Deliberately quiet and deliberately weak: it reports nothing, it gives up
  /// on a band at the first failure, and a failure leaves NOTHING behind —
  /// no dead band, no retry counter, no partial file. The on-demand path in
  /// MaiaEngine is untouched by whatever happens here, which is the whole
  /// safety argument for starting a download nobody asked for.
  static Future<void> prefetch() => _prefetch ??= _prefetchAll();

  static Future<void> _prefetchAll() async {
    // Establishes what is already there before anything is fetched, so a
    // prefetch that fails entirely still leaves the picker able to say "not
    // downloaded" rather than "unknown" — the failure is exactly when that
    // distinction is worth something.
    await refresh();
    for (final band in bands) {
      // Let a move that somebody is watching have the pipe to itself. Checked
      // between bands rather than polled: the only thing that can be in flight
      // here is a download a move started, and joining its future is a wait
      // that ends exactly when it should.
      final live = _inFlight.values.toList();
      if (live.isNotEmpty) {
        await Future.wait(live).catchError((Object _) => const <Uint8List>[]);
      }
      final File file;
      try {
        file = await fileFor(band);
      } catch (e) {
        // No cache directory at all — a test binding, or a sandbox that will
        // not hand one over. There is nothing to prefetch INTO, so stop
        // rather than fail three times over.
        debugPrint('[maia] prefetch has nowhere to write: $e');
        return;
      }
      if (await file.exists()) {
        _markCached(band);
        continue;
      }
      try {
        await _fetch(band, file);
      } catch (e) {
        debugPrint('[maia] prefetch of maia-$band failed: $e');
      }
    }
  }

  /// The band's weights, from disk if they are there and over the network if
  /// they are not. This is the path a move takes, and its failures are the
  /// caller's to classify — a [TimeoutException] and a 404 mean very
  /// different things to MaiaEngine.
  static Future<Uint8List> load(
    int band, {
    void Function(MaiaProgress)? onProgress,
  }) async {
    final file = await fileFor(band);
    if (await file.exists()) {
      _markCached(band);
      return file.readAsBytes();
    }
    return _fetch(band, file, onProgress: onProgress);
  }

  /// Throw away a band's cached weights — ORT would not open them.
  static Future<void> discard(int band) async {
    try {
      await (await fileFor(band)).delete();
    } catch (_) {
      // never fatal; the point is that the next load re-downloads
    }
    final now = _cached.value;
    if (now != null && now.contains(band)) {
      _cached.value = {...now}..remove(band);
    }
  }

  static Future<Uint8List> _fetch(
    int band,
    File file, {
    void Function(MaiaProgress)? onProgress,
  }) async {
    final listeners = _listeners.putIfAbsent(band, () => {});
    if (onProgress != null) listeners.add(onProgress);
    try {
      var fetch = _inFlight[band];
      final joined = fetch != null;
      if (fetch == null) {
        late final Future<Uint8List> started;
        started = _download(band, file).whenComplete(() {
          if (identical(_inFlight[band], started)) _inFlight.remove(band);
        });
        _inFlight[band] = started;
        fetch = started;
      }
      try {
        return await fetch;
      } catch (e) {
        // Wrapped only when this caller did NOT start the download: the error
        // carries the original request's clock, and treating it as this
        // caller's own is what kills a band. See [JoinedDownloadFailure].
        if (joined) throw JoinedDownloadFailure(e);
        rethrow;
      }
    } finally {
      if (onProgress != null) {
        listeners.remove(onProgress);
        if (listeners.isEmpty) _listeners.remove(band);
      }
    }
  }

  static Future<Uint8List> _download(int band, File file) async {
    final open = debugOpen ?? _openHttp;
    final body = await open(Uri.parse(maiaModelUrl(band))).timeout(
      kMaiaLoadTimeout,
    );
    try {
      final total = math.max(body.contentLength, 0);
      // Report every ~4% rather than every chunk: each report crosses into the
      // controller and rebuilds a widget. The last chunk always reports, so
      // the line always finishes.
      final step = total > 0 ? math.max(total ~/ 25, 65536) : 262144;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      var reported = 0;
      _report(band, MaiaProgress('fetching', received: 0, total: total));
      await for (final chunk in body.chunks.timeout(kMaiaLoadTimeout)) {
        builder.add(chunk);
        received += chunk.length;
        if (received - reported >= step) {
          reported = received;
          _report(
              band, MaiaProgress('fetching', received: received, total: total));
        }
      }
      _report(
          band,
          MaiaProgress('fetching',
              received: received, total: total > 0 ? total : received));
      final bytes = builder.takeBytes();

      // Land it through a rename: a partial write must never be readable as a
      // cache hit, and an interrupted download is the ordinary case here.
      final part = File('${file.path}.part');
      await part.parent.create(recursive: true);
      try {
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      } catch (_) {
        // do not leave 3.5MB of orphan behind on a full or read-only disk
        try {
          await part.delete();
        } catch (_) {
          // never fatal
        }
        rethrow;
      }
      _markCached(band);
      return bytes;
    } finally {
      body.close?.call();
    }
  }

  static Future<MaiaBody> _openHttp(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url).timeout(kMaiaLoadTimeout);
      final response = await request.close().timeout(kMaiaLoadTimeout);
      if (response.statusCode != 200) {
        throw StateError('$url fetch failed: ${response.statusCode}');
      }
      return MaiaBody(
        chunks: response,
        contentLength: response.contentLength,
        close: () => client.close(force: true),
      );
    } catch (_) {
      // Only on the paths that never hand the client to a MaiaBody; once one
      // exists, closing the client is its consumer's job and doing it here
      // would cut the stream off mid-body.
      client.close(force: true);
      rethrow;
    }
  }

  static void _report(int band, MaiaProgress progress) {
    final listeners = _listeners[band];
    if (listeners == null || listeners.isEmpty) return;
    for (final listener in listeners.toList()) {
      listener(progress);
    }
  }

  /// A band has landed. When nothing has looked at the directory yet, this
  /// goes and looks rather than inventing a set: `{1100}` would claim the
  /// other two are absent, which this call is no evidence of.
  static void _markCached(int band) {
    final now = _cached.value;
    if (now == null) {
      unawaited(refresh());
      return;
    }
    if (!now.contains(band)) _cached.value = {...now, band};
  }
}
