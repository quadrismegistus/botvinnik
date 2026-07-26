// Nothing to fetch: ChessGPT is native-only by decision, not by omission.
// See chessgpt_engine_web.dart.
import 'dart:typed_data';

class ChessGptWeights {
  ChessGptWeights._();
  static bool get supported => false;
  static Future<Uint8List?> load() async => null;
  static Future<void> discard() async {}
  static Future<bool> get isCached async => false;
}
