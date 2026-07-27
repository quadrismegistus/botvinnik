// Nothing to fetch: ChessGPT is native-only by decision, not by omission.
// See chessgpt_engine_web.dart.
//
// This must declare EVERY member that anything under lib/ touches, whether or
// not the call is reachable on the web. `roster_picker` reads [cached] behind
// an `if (ChessGptEngine.supported)` guard, and a guard is a runtime test
// while the reference is resolved at COMPILE time — so omitting it here broke
// `flutter build web` while the analyzer and all 772 tests stayed green. The
// web build in CI is the only thing that typechecks this side of a conditional
// import; nothing else can.
//
// What is deliberately NOT here: the variant table, the urls and the
// checksums. Nothing under lib/ reads them, and a checksum copied into a
// second file to satisfy an import is how the two drift apart.
import 'package:flutter/foundation.dart';

class ChessGptWeights {
  ChessGptWeights._();
  static bool get supported => false;

  /// Stays null forever — "nobody has looked", which is the truth here and is
  /// the state the roster row renders as its neutral line. An empty set would
  /// claim we checked and found none. Same reasoning, and the same shape, as
  /// MaiaWeights on the web.
  static final ValueNotifier<Set<String>?> _cached = ValueNotifier(null);
  static ValueListenable<Set<String>?> get cached => _cached;

  static Future<Uint8List?> load(String id) async => null;
  static Future<void> discard(String id) async {}
  static Future<bool> isCached(String id) async => false;
  static Future<Set<String>> refresh() async => const {};
}
