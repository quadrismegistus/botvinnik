// ChessGPT's ONNX net, fetched once and kept.
//
// ~26MB int8, which is why it is a download rather than an asset: bundling it
// would put it in every install of every platform, including the ones that
// cannot run it. The same reasoning, and the same shape, as MaiaWeights.
//
// The artefact is OURS, not upstream's: Karvonen publishes PyTorch checkpoints
// (huggingface.co/adamkarvonen/chess_llms), and the ONNX export plus int8
// quantisation is done by scripts/shims/chessgpt/export_onnx.py. So the URL
// below has to point at somewhere we publish, not at HuggingFace.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ChessGptWeights {
  ChessGptWeights._();

  static bool get supported => Platform.isMacOS || Platform.isIOS;

  /// Where the published net lives: a botvinnik-engines release, as the UCI
  /// binaries are. Upstream is MIT (Karvonen set the licence on the model card
  /// on request, #235); attribution and the terms travel with the release, in
  /// LICENSE-chessgpt.
  static const String url =
      'https://github.com/quadrismegistus/botvinnik-engines/releases/download/'
      'chessgpt-lichess-8layers-int8/chessgpt-lichess-8layers-int8.onnx';

  /// Lowercase hex SHA-256 of the asset at [url], checked before the bytes are
  /// kept or returned.
  ///
  /// The engines repo's contract is that every hosted artefact is pinned and a
  /// mismatch is refused (see EngineCatalogEntry.sha256, which does the same
  /// for the binaries). This is a 26MB blob fetched over the network and fed
  /// straight to a native runtime, so "probably fine" is not the standard: a
  /// truncated download or a substituted asset should fail loudly at the
  /// fetch, not surface later as a model that plays strange chess.
  static const String sha256Hex =
      'dbb0ca62daf05f15363270872337a82265eec3f5c329151d026de4c9f0c54d2b';

  /// The lichess-trained net. Structured as a named variant from the start
  /// because the family has siblings (Stockfish-trained, mixed, >1800-only).
  ///
  /// They are NOT a strength ladder like Maia's bands — they differ by
  /// training corpus, not by dialled strength. An earlier note here said the
  /// gym had measured them at identical strength; that measurement was an
  /// artefact and is withdrawn (#235). What a clean run does show is that the
  /// human-trained net makes markedly fewer mistakes than the
  /// Stockfish-trained one, so the siblings are a genuine curiosity rather
  /// than three names for one thing.
  static const String variant = 'lichess-8L';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/chessgpt/$variant.int8.onnx');
  }

  static Future<bool> get isCached async => (await _file()).exists();

  /// The net's bytes, downloading once if needed. Null when unsupported, not
  /// yet published, or the fetch failed — every caller treats null as "this
  /// persona is unavailable" rather than retrying into a stall.
  static Future<Uint8List?> load() async {
    if (!supported || url.isEmpty) return null;
    final file = await _file();
    try {
      if (await file.exists()) {
        final cached = await file.readAsBytes();
        // A cached file is re-verified, not trusted for having arrived once:
        // it may have been written by an older build, truncated by a full
        // disk, or touched on disk since.
        if (_matches(cached)) return cached;
        await file.delete();
      }
      await file.parent.create(recursive: true);
      final client = HttpClient();
      try {
        final res = await client.getUrl(Uri.parse(url)).then((r) => r.close());
        if (res.statusCode != 200) return null;
        final bytes = await consolidateHttpClientResponseBytes(res);
        if (!_matches(bytes)) return null;
        // Written via a temp file and renamed: a half-downloaded net that
        // looks cached is worse than no net, because it fails at session
        // build with nothing to say why.
        final tmp = File('${file.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
        return bytes;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  static bool _matches(Uint8List bytes) =>
      sha256.convert(bytes).toString() == sha256Hex;

  static Future<void> discard() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
