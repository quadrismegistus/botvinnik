// Horizon through the REAL bridge. js-chess-engine is bundled into brain.js
// and executed by the host JS runtime — a bare-context node check cannot prove
// that runtime runs it, and a `String?` returning null is exactly the
// marshalling shape that has bitten before.
//
// Verified on JavaScriptCore only (ios/ and macos/ are the only native targets
// that exist). See js_bridge.dart for why QuickJS is a real open question here
// rather than a formality.
//
//   cd flutter && flutter test integration_test/horizon_live_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';
import 'package:botvinnik_mobile/brain/js_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late BotApi bot;
  setUpAll(() async => bot = BotApi(await JsBridge.load()));

  test('plays a legal-looking move from a real position', () {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    // non-deterministic by nature, so run it a few times and check the shape
    for (var i = 0; i < 8; i++) {
      final uci = bot.horizonMove(start, 1);
      expect(uci, isNotNull, reason: 'the opening position has legal moves');
      expect(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(uci!), isTrue,
          reason: 'got "$uci"');
    }
  });

  test('a terminal position crosses as Dart null, not the string "null"', () {
    expect(bot.horizonMove('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', 1), isNull);
  });

  test('promotion is spelled out across the bridge', () {
    expect(bot.horizonMove('8/P6k/8/8/8/8/6K1/8 w - - 0 1', 1), 'a7a8q');
  });

  test('internalElo is defined for a family that carries no numericElo', () {
    final horizon = bot.personas().firstWhere((p) => p.family == 'horizon');
    expect(horizon.numericElo, isNull, reason: 'precondition for the fallback');
    expect(bot.internalElo(horizon), horizon.elo + 240);
  });
}
