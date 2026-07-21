// Which calibration table the brain is using, on a real device.
//
// The brain keeps two — the shaped label→strength knots and the numeric
// recipe bands — because a persona label means different things depending on
// the engine underneath it. It defaults to `wasm`, and until #104 nothing in
// the Flutter app ever told it otherwise: native Squares mapped their labels
// through the WASM table while playing Stockfish 18 over FFI or a spawned
// process.
//
// This is worth a device test rather than a unit test for the same reason the
// bug survived so long — nothing about it fails. No crash, no fallback, no log
// line. A Square just plays at a strength nobody measured. The only way to
// catch it is to ask the brain, on the platform, what it thinks it is
// calibrating for.
//
//   cd flutter && flutter test integration_test/substrate_test.dart -d macos
//   flutter test integration_test/substrate_test.dart -d <simulator-id>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';
import 'package:botvinnik_mobile/brain/js_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late BotApi bot;
  setUpAll(() async => bot = BotApi(await JsBridge.load()));

  test('a fresh runtime still defaults to wasm', () {
    // The default is the thing that was wrong, so pin it: if the brain ever
    // starts defaulting to native, main.dart's call becomes a no-op and this
    // test stops meaning anything without saying so.
    expect(bot.substrate(), 'wasm');
  });

  test('setting native takes effect', () {
    bot.setSubstrate('native');
    expect(bot.substrate(), 'native');
  });

  test('the two tables genuinely disagree about a label', () {
    // If they agreed, none of this would matter. Internal 1140 is display-900
    // territory; the two curves put it at different labels, which is the whole
    // reason the substrate has to be told.
    bot.setSubstrate('wasm');
    final onWasm = bot.shapedLabelFor(1140);
    bot.setSubstrate('native');
    final onNative = bot.shapedLabelFor(1140);
    expect(onNative, isNot(onWasm),
        reason: 'the tables agree, so the substrate would not matter');
    // Remeasured 2026-07-21: native reads lower, so it needs a HIGHER label to
    // reach the same strength.
    expect(onNative, greaterThan(onWasm));
  });

  test('and disagree about the search depth that follows from it', () {
    // The label feeds shapedSearchDepth, so picking the wrong table does not
    // just mislabel the bot — it changes how deep it looks.
    bot.setSubstrate('wasm');
    final wasmDepth = bot.shapedSearchDepth(bot.shapedLabelFor(1140));
    bot.setSubstrate('native');
    final nativeDepth = bot.shapedSearchDepth(bot.shapedLabelFor(1140));
    expect(nativeDepth, greaterThanOrEqualTo(wasmDepth));
  });
}
