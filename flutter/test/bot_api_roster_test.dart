// What BotApi actually asks the brain for (#235).
//
// The whole ChessGPT feature shipped complete and UNREACHABLE, and this one
// argument was half the reason: `personas()` called
// `availablePersonas(false)` — the WEB roster, which drops every `nativeOnly`
// family. Correct while Dala (native-only, and never implemented) was the only
// such family; wrong the moment a native-only family got an engine behind it.
//
// roster_filter_test.dart covers the seam ABOVE this — that GameController
// asks for the native roster when a native-only family is playable — by
// recording what it requested of a FakeBot. Nothing covered the seam BELOW,
// where the boolean is handed to the bundle. Reverting `args: [native]` to
// `args: [false]`, which is literally the bug, left all 812 Flutter tests
// green.
//
// So this runs the REAL bundle, in node, through the same buildBrainExpr the
// shipping bridges use — see node_brain.dart for why that is worth the process
// spawn, and why a missing node fails rather than skips.
//
//   cd flutter && flutter test test/bot_api_roster_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';

import 'support/node_brain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NodeBrainBridge bridge;
  late BotApi api;

  setUp(() {
    bridge = NodeBrainBridge();
    api = BotApi(bridge);
  });

  test('the native roster carries the native-only families', () {
    final families = api.personas(native: true).map((p) => p.family).toSet();

    expect(families, contains('chessgpt'),
        reason: 'a hardcoded false here is what made ChessGPT unreachable');
    expect(families, contains('squarefish'),
        reason: 'and it must not have LOST the ordinary ones');
  });

  test('the web roster does not', () {
    // The control. Without it, `args: [true]` — hardcoded the other way — is
    // indistinguishable from asking properly, and the web build would offer
    // three ChessGPT personas it cannot run.
    final families = api.personas(native: false).map((p) => p.family).toSet();

    expect(families, isNot(contains('chessgpt')));
    expect(families, contains('squarefish'));
  });

  test('the argument reaches the bundle, not just the call', () {
    // Asserted on the expression itself as well as the answer: the two rosters
    // differing is evidence the brain branched, and this is evidence it
    // branched on what it was TOLD rather than on anything of its own.
    api.personas(native: true);
    expect(bridge.exprs.single, contains('availablePersonas(true)'));

    bridge.exprs.clear();
    api.personas(native: false);
    expect(bridge.exprs.single, contains('availablePersonas(false)'));
  });
}
