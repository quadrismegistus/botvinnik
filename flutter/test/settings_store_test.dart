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

  group('per-side players', () {
    test('default: you play White, the bot plays Black', () async {
      final s = await load();
      expect(s.whitePersonaId, isNull); // you
      expect(s.blackPersonaId, isNotNull); // a bot
      expect(s.botEnabled, isTrue);
      expect(s.playerColor, 'w'); // your side, for orientation
    });

    test('a new per-side blob loads verbatim (two different bots)', () async {
      final s = await load({
        'flutter.botvinnik-bot-v1':
            '{"white":"square-900","black":"square-600","personaId":"square-900"}'
      });
      expect(s.whitePersonaId, 'square-900');
      expect(s.blackPersonaId, 'square-600');
    });

    test('setPlayers persists and derives botEnabled', () async {
      final s = await load();
      s.setPlayers(white: 'square-900', black: null); // bot White, you Black
      expect(s.whitePersonaId, 'square-900');
      expect(s.blackPersonaId, isNull);
      expect(s.botEnabled, isTrue);
      expect(s.playerColor, 'b'); // you're Black now
    });

    test('both null is analysis — no bot', () async {
      final s = await load();
      s.setPlayers(white: null, black: null);
      expect(s.botEnabled, isFalse);
    });

    group('migrates the old {enabled,bothSides,color} blob', () {
      test('you vs bot (bot plays Black)', () async {
        final s = await load({
          'flutter.botvinnik-bot-v1':
              '{"enabled":true,"personaId":"square-900","color":"b"}'
        });
        expect(s.whitePersonaId, isNull);
        expect(s.blackPersonaId, 'square-900');
      });

      test('bot plays White', () async {
        final s = await load({
          'flutter.botvinnik-bot-v1':
              '{"enabled":true,"personaId":"square-900","color":"w"}'
        });
        expect(s.whitePersonaId, 'square-900');
        expect(s.blackPersonaId, isNull);
      });

      test('old bot-vs-bot (bothSides) → same bot both sides', () async {
        final s = await load({
          'flutter.botvinnik-bot-v1':
              '{"enabled":true,"bothSides":true,"personaId":"square-900","color":"b"}'
        });
        expect(s.whitePersonaId, 'square-900');
        expect(s.blackPersonaId, 'square-900');
      });

      test('analysis (disabled) → both human', () async {
        final s = await load({
          'flutter.botvinnik-bot-v1':
              '{"enabled":false,"personaId":"square-900","color":"b"}'
        });
        expect(s.botEnabled, isFalse);
      });
    });
  });
}
