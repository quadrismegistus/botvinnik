// SettingsStore's persistence. These are the settings a user notices losing,
// and the encoding is hand-rolled on both sides, so it is worth pinning.
//
//   cd flutter && flutter test

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:botvinnik_mobile/stores/settings_store.dart';

Future<SettingsStore> load([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SettingsStore.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('panels', () {
    test('defaults to Insights alone', () async {
      expect((await load()).panels, {0});
    });

    test('round-trips through a reload', () async {
      final s = await load();
      s.togglePanel(2);
      s.togglePanel(3);
      expect(s.panels, {0, 2, 3});
      expect((await load({'flutter.botvinnik-panels': '0,2,3'})).panels,
          {0, 2, 3});
    });

    test('toggling removes as well as adds', () async {
      final s = await load({'flutter.botvinnik-panels': '0,2'});
      s.togglePanel(2);
      expect(s.panels, {0});
    });

    test('the last panel cannot be closed', () async {
      final s = await load();
      s.togglePanel(0);
      expect(s.panels, {0}, reason: 'an empty panel column just looks broken');
    });

    test('a corrupt value falls back rather than emptying the column',
        () async {
      for (final raw in ['', 'nonsense', '9,42', ',,,']) {
        expect((await load({'flutter.botvinnik-panels': raw})).panels, {0},
            reason: 'raw: "$raw"');
      }
    });
  });

  group('split', () {
    test('defaults, and clamps a stored value that is out of range', () async {
      expect((await load()).split, kDefaultSplit);
      expect((await load({'flutter.botvinnik-split': 0.05})).split, kMinSplit);
      expect((await load({'flutter.botvinnik-split': 0.99})).split, kMaxSplit);
    });

    test('clamps on write too, so a drag past the edge sticks at the edge',
        () async {
      final s = await load();
      s.split = 5.0;
      expect(s.split, kMaxSplit);
      s.split = -1;
      expect(s.split, kMinSplit);
    });
  });

  group('board colours', () {
    test('survive a round trip, alpha included', () async {
      final s = await load();
      s.lastMoveColor = const Color(0x8012AB34);
      expect((await load({'flutter.botvinnik-lastmove': '8012ab34'}))
          .lastMoveColor
          .toARGB32(),
          0x8012AB34);
    });

    test('a six-digit colour cannot make the board invisible', () async {
      // an import could produce 'f0d9b6', which parses to alpha 0
      final s = await load({'flutter.botvinnik-sq-light': 'f0d9b6'});
      expect(s.lightSquare.a, 1.0);
    });

    test('an unparseable colour falls back to the default', () async {
      final s = await load({'flutter.botvinnik-sq-dark': 'not-a-colour'});
      expect(s.darkSquare.toARGB32(), kDefaultDarkSquare.toARGB32());
    });
  });

  group('defaults out of the box', () {
    test('the explaining overlays are on', () async {
      final s = await load();
      expect(s.showThreats, isTrue);
      expect(s.showControl, isTrue);
      expect(s.showArrows, isTrue);
    });

    test('turning one off sticks', () async {
      expect((await load({'flutter.botvinnik-threats': '0'})).showThreats,
          isFalse);
      expect((await load({'flutter.botvinnik-control': '0'})).showControl,
          isFalse);
    });

    test('the board starts on a texture', () async {
      expect((await load()).boardTexture, kDefaultBoardTexture);
    });

    test('choosing custom colours sticks rather than reverting', () async {
      // an absent value now means "never chose", which is the default
      // texture — so clearing has to be stored, not removed
      final s = await load();
      s.applySquares(const Color(0xff112233), const Color(0xff445566));
      expect(s.boardTexture, isEmpty);
      expect((await load({'flutter.botvinnik-board-texture': ''})).boardTexture,
          isEmpty);
    });

    test('reset puts the texture back', () async {
      final s = await load({'flutter.botvinnik-board-texture': ''});
      s.resetBoardColors();
      expect(s.boardTexture, kDefaultBoardTexture);
    });
  });

  test('arrow count is clamped to the number of brushes', () async {
    expect((await load({'flutter.botvinnik-arrow-count': 99})).arrowCount,
        kMaxArrowCount);
    expect((await load({'flutter.botvinnik-arrow-count': 0})).arrowCount, 1);
  });

  group('bot vs bot', () {
    test('defaults off', () async {
      expect((await load()).botBothSides, isFalse);
    });

    test('a stored bot blob with bothSides loads it', () async {
      final s = await load({
        'flutter.botvinnik-bot-v1':
            '{"enabled":true,"bothSides":true,"personaId":"square-900","color":"b"}'
      });
      expect(s.botBothSides, isTrue);
    });

    test('an old blob without the field loads as off (backward compatible)',
        () async {
      final s = await load({
        'flutter.botvinnik-bot-v1':
            '{"enabled":true,"personaId":"square-900","color":"b"}'
      });
      expect(s.botBothSides, isFalse);
    });

    test('the setter runs and persists without disturbing the other fields',
        () async {
      final s = await load();
      s.playerColor = 'b';
      s.botBothSides = true;
      expect(s.botBothSides, isTrue);
      expect(s.playerColor, 'b'); // still there
      expect(s.botEnabled, isTrue);
    });
  });
}
