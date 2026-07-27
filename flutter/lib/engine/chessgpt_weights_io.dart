// ChessGPT's ONNX nets: which are on disk, how they get there, and the one
// place that downloads them.
//
// Three nets behind three personas, ~26MB each, which is why they are a
// download rather than an asset: bundling 78MB would put it in every install
// of every platform, including the ones that cannot run any of it.
//
// Structurally this is MaiaWeights with one axis swapped. Maia's `int band` is
// a rung on a strength ladder — 1100/1500/1900 — and the number means
// something to a player choosing an opponent. ChessGPT's variants are NOT a
// ladder: they measure 1225, 1244 and 1303 on our own gym, inside 78 points of
// each other, and differ by which corpus TAUGHT them rather than by dialled
// strength. So the key here is a variant id, the three share one roster entry
// as styles (#183's EnginePersonality pattern, where "strength stays a
// separate dial, so every style shares the engine's elo"), and nothing sorts
// them against each other by elo.
//
// THE ONE DELIBERATE DIVERGENCE FROM MAIA: no prefetch. Maia pulls all three
// bands quietly on a connected session because they are 3.5MB each, and 10.5MB
// is a rounding error against the app. Three ChessGPT nets are 78MB. Fetching
// that in the background for personas the player may never choose is not a
// kindness, so these arrive on demand and visibly.
//
// The artefacts are OURS, not upstream's: Karvonen publishes PyTorch
// checkpoints (huggingface.co/adamkarvonen/chess_llms, MIT), and the ONNX
// export plus int8 quantisation is scripts/shims/chessgpt/export_onnx.py. So
// the urls point at our own release, and the attribution travels with it in
// the engines repo's LICENSE-chessgpt.
//
// The web does none of this: see chessgpt_weights_web.dart.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One published net: where it lives, and what it should be.
///
/// Carries NO display strings. It held a `name` and a `teacher` and nothing
/// ever read them: the roster shows the PERSONA's name and blurb, from
/// brain/bots.ts, which is the source of truth for everything a player sees.
/// Two copies of a label that only one side renders do not stay equal — the
/// first rename of a variant had to touch both, and would have silently
/// diverged the moment one was missed.
@immutable
class ChessGptVariant {
  const ChessGptVariant({
    required this.id,
    required this.sha256,
    required this.bytes,
  });

  /// Stable key. It is the filename, the persona id suffix and the stored
  /// setting, so it must not change once shipped.
  final String id;

  /// Lowercase hex SHA-256 of the asset, checked before the bytes are kept or
  /// returned.
  ///
  /// The engines repo's contract is that every hosted artefact is pinned and a
  /// mismatch refused (EngineCatalogEntry.sha256 does the same for the
  /// binaries). This is 26MB fetched over the network and handed straight to a
  /// native runtime: a truncated download or a substituted asset should fail
  /// loudly at the fetch, not surface later as a model playing strange chess.
  final String sha256;

  /// Expected size, so a download can show a fraction rather than a spinner.
  /// Not a security check — [sha256] is.
  final int bytes;

  String get url =>
      'https://github.com/quadrismegistus/botvinnik-engines/releases/download/'
      'chessgpt-8layers-int8/chessgpt-$id-8layers-int8.onnx';
}

/// Where a variant's weights live, and how they get there.
class ChessGptWeights {
  ChessGptWeights._();

  /// ORT's native library, so the same platforms Maia runs on.
  static bool get supported => Platform.isMacOS || Platform.isIOS;

  /// The three published nets. Names, blurbs and roster order come from the
  /// personas in brain/bots.ts; this is only what to fetch and how to check it.
  static const List<ChessGptVariant> variants = [
    ChessGptVariant(
      id: 'lichess',
      sha256:
          '738ef5734a143740403069386da835c206739193141db89c69024e30da10a796',
      bytes: 25808998,
    ),
    ChessGptVariant(
      id: 'stockfish',
      sha256:
          '57e0285a7f571ef8aaad348446bc7ebe1d73bcfd15373a44111ac45a8a4e5521',
      bytes: 25808998,
    ),
    ChessGptVariant(
      id: 'mix',
      sha256:
          '4b828ec44060fb94465714e3ac2118851c61e74ce3360f2d7ccccf9f4e82dc5e',
      bytes: 25808998,
    ),
  ];

  static ChessGptVariant? variantFor(String? id) {
    for (final v in variants) {
      if (v.id == id) return v;
    }
    return null;
  }

  static final ValueNotifier<Set<String>?> _cached = ValueNotifier(null);

  /// Variants whose weights are on disk — or null for "nobody has looked yet".
  ///
  /// The null is the point, and it is Maia's reasoning verbatim: an empty set
  /// says "none of them are cached", which is a claim. Before [refresh] runs,
  /// and forever on the web, the honest answer is that we do not know, and the
  /// picker says a different thing for each.
  static ValueListenable<Set<String>?> get cached => _cached;

  /// One download per variant at a time, whoever asked for it.
  ///
  /// Maia needs this because a move and a prefetch can both want a band. There
  /// is no prefetch here, but a retry arriving beside a first attempt races the
  /// same `.part` rename — which is the corruption the rename exists to
  /// prevent.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Applied to the connect, the response, and the body separately, as Maia
  /// does. Without it a connection that is accepted and never answered leaves
  /// load() pending for ever; the engine memoises that pending future and
  /// GameController awaits pickMove with no timeout of its own, so the board
  /// reads "thinking" until the app is killed. 60s rather than Maia's 30s
  /// because this is 26MB, not 3.5.
  static const Duration kLoadTimeout = Duration(seconds: 60);

  @visibleForTesting
  static Directory? debugDirectory;

  /// For a widget test about what the picker SAYS, which should not depend on
  /// a temporary directory to say it.
  @visibleForTesting
  static void debugSetCached(Set<String>? value) => _cached.value = value;

  static Future<Directory> _dir() async =>
      debugDirectory ?? await getApplicationSupportDirectory();

  static Future<File> fileFor(String id) async =>
      File('${(await _dir()).path}/chessgpt/$id.int8.onnx');

  /// Which variants are already downloaded. Cheap, and it never fetches.
  /// Never throws: in a widget test there is no path_provider plugin to
  /// answer, and this is called from initState where nothing awaits it.
  ///
  /// A cheap check — the file is there and the right SIZE. Not the digest:
  /// hashing 78MB every time the sheet opens to render one line is not a
  /// trade worth making. Size catches the common corruption (a truncated
  /// download, a full disk) and [load] still verifies the digest before any
  /// bytes are used, so this is an optimistic claim backed by a real one.
  static Future<Set<String>> refresh() async {
    final found = <String>{};
    if (supported) {
      try {
        for (final v in variants) {
          final f = await fileFor(v.id);
          if (await f.exists() && await f.length() == v.bytes) found.add(v.id);
        }
      } catch (_) {
        // no plugin, or an unreadable directory: "we do not know" is the
        // honest answer, and it is what the null below renders.
        _cached.value = null;
        return const {};
      }
    }
    _cached.value = found;
    return found;
  }

  static void _markCached(String id) {
    final now = _cached.value;
    if (now == null) {
      // "Nobody has looked" is not "only this one is here". Inventing {id}
      // told the roster the OTHER two were absent when they may be on disk —
      // reachable whenever a move loads a net before the sheet has opened.
      // refresh() answers properly; Maia's does the same and says so.
      refresh();
    } else if (!now.contains(id)) {
      _cached.value = {...now, id};
    }
  }

  /// The variant's bytes, downloading once if needed. Null when unsupported,
  /// unknown, or the fetch failed — every caller treats null as "this persona
  /// is unavailable" rather than retrying into a stall.
  static Future<Uint8List?> load(String id) {
    final variant = variantFor(id);
    if (!supported || variant == null) return Future.value(null);
    return _inFlight.putIfAbsent(id, () {
      late final Future<Uint8List?> started;
      started = _load(variant).whenComplete(() {
        // Cleared on completion, not on success. A failed fetch left in the
        // map would hand every later attempt the same failure forever, and a
        // caller reads that as "this persona is broken" rather than "the
        // network was down once".
        if (identical(_inFlight[id], started)) _inFlight.remove(id);
      });
      return started;
    });
  }

  static Future<Uint8List?> _load(ChessGptVariant variant) async {
    // Inside the try: fileFor reaches path_provider, which throws rather than
    // returning null where the plugin is absent. Every caller of load() treats
    // null as "unavailable" and nothing is prepared for a throw.
    try {
      final file = await fileFor(variant.id);
      if (await file.exists()) {
        final cached = await file.readAsBytes();
        // Re-verified, not trusted for having arrived once: it may have been
        // written by an older build, truncated by a full disk, or touched on
        // disk since.
        if (_matches(cached, variant)) {
          _markCached(variant.id);
          return cached;
        }
        // Deleted AND un-advertised. Dropping only the file left the notifier
        // holding the id, so the roster went on promising "downloaded — plays
        // offline" for a file that no longer existed.
        await file.delete();
        _unmarkCached(variant.id);
      }
      await file.parent.create(recursive: true);
      final client = HttpClient();
      try {
        final res = await client
            .getUrl(Uri.parse(variant.url))
            .timeout(kLoadTimeout)
            .then((r) => r.close().timeout(kLoadTimeout));
        if (res.statusCode != 200) return null;
        final bytes = await consolidateHttpClientResponseBytes(res)
            .timeout(kLoadTimeout);
        if (!_matches(bytes, variant)) return null;
        // Written via a temp file and renamed: a half-downloaded net that
        // looks cached is worse than no net, because it fails at session build
        // with nothing to say why.
        final tmp = File('${file.path}.part');
        try {
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(file.path);
        } catch (_) {
          // A full or read-only disk. Without this the 26MB .part is orphaned
          // and nothing ever collects it.
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {/* nothing better to do */}
          return null;
        }
        _markCached(variant.id);
        return bytes;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  static void _unmarkCached(String id) {
    final now = _cached.value;
    if (now != null && now.contains(id)) {
      _cached.value = {...now}..remove(id);
    }
  }

  static bool _matches(Uint8List bytes, ChessGptVariant variant) =>
      sha256.convert(bytes).toString() == variant.sha256;

  static Future<bool> isCached(String id) async {
    if (!supported) return false;
    try {
      final v = variantFor(id);
      final f = await fileFor(id);
      return await f.exists() && (v == null || await f.length() == v.bytes);
    } catch (_) {
      return false;
    }
  }

  /// Throw away a variant's cached weights — ORT would not open them.
  static Future<void> discard(String id) async {
    try {
      await (await fileFor(id)).delete();
    } catch (_) {
      // never fatal; the point is that the next load re-downloads
    }
    final now = _cached.value;
    if (now != null && now.contains(id)) {
      _cached.value = {...now}..remove(id);
    }
  }
}
