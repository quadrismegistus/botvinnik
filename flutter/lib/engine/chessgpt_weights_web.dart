// Nothing to fetch: ChessGPT is native-only by decision, not by omission.
// See chessgpt_engine_web.dart.
//
// The surface mirrors the io side's SHARED members only. The variant table,
// the urls and the checksums live there and are deliberately not duplicated
// here — a checksum copied into a second file to satisfy an import is how the
// two drift apart.
import 'dart:typed_data';

class ChessGptWeights {
  ChessGptWeights._();
  static bool get supported => false;
  static Future<Uint8List?> load(String id) async => null;
  static Future<void> discard(String id) async {}
  static Future<bool> isCached(String id) async => false;
  static Future<Set<String>> refresh() async => const {};
}
