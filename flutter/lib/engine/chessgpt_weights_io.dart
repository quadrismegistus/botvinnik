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

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ChessGptWeights {
  ChessGptWeights._();

  static bool get supported => Platform.isMacOS || Platform.isIOS;

  /// Where the published net lives.
  ///
  /// TODO(#chessgpt): publish scripts/shims/chessgpt/onnx/*.int8.onnx to the
  /// botvinnik-engines releases, as the UCI engines are, and point this at it.
  /// Until then [load] returns null and the roster hides the persona — which
  /// is the honest failure: a bot that cannot fetch its brain should not be
  /// offered, not offered and then stall.
  static const String url = '';

  /// The lichess-trained net. Structured as a named variant from the start
  /// because the family has siblings (Stockfish-trained, mixed, >1800-only)
  /// that the gym measured at the SAME strength — so they are a curiosity to
  /// add later, not a strength ladder like Maia's bands.
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
      if (await file.exists()) return await file.readAsBytes();
      await file.parent.create(recursive: true);
      final client = HttpClient();
      try {
        final res = await client.getUrl(Uri.parse(url)).then((r) => r.close());
        if (res.statusCode != 200) return null;
        final bytes = await consolidateHttpClientResponseBytes(res);
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

  static Future<void> discard() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
