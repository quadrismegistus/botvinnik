// The custom-engine model and its store: the parts that hold without a real
// engine binary (spawning one is verified on a desktop). The load-bearing
// claims are that an engine round-trips through storage, that it becomes a
// `custom`-family persona the controller can resolve, and that byPersonaId is
// the exact inverse of toPersona.
//
//   cd flutter && flutter test test/custom_engine_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/custom_engine_runner_io.dart';
import 'package:botvinnik_mobile/stores/custom_engine.dart';
import 'package:botvinnik_mobile/stores/engine_catalog.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';

/// Let the store's constructor read from disk (it fires _load, not awaitable).
/// Drains MICROTASKS, not timers, so it works the same under a widget test's
/// fake async — the store's only await is [MemoryDb.kvGet], microtask-resolved.
Future<CustomEngineStore> loaded(MemoryDb db) async {
  final s = CustomEngineStore(db);
  for (var i = 0; i < 100 && !s.isLoaded; i++) {
    await Future<void>.microtask(() {});
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an engine round-trips through JSON unchanged', () {
    const e = CustomEngine(
      id: 'x1',
      name: 'Viridithas',
      path: '/usr/local/bin/viridithas',
      elo: 2800,
      movetimeMs: 500,
      limitElo: true,
    );
    final back = CustomEngine.fromJson(e.toJson());
    expect(back.id, e.id);
    expect(back.name, e.name);
    expect(back.path, e.path);
    expect(back.elo, e.elo);
    expect(back.movetimeMs, e.movetimeMs);
    expect(back.limitElo, e.limitElo);
  });

  test('becomes a custom-family persona, and the blurb names the binary', () {
    const e = CustomEngine(
        id: 'x1', name: 'My Engine', path: '/opt/engines/viri', elo: 2200);
    final p = e.toPersona();
    expect(p.family, 'custom');
    expect(p.id, 'custom-x1');
    expect(p.name, 'My Engine');
    expect(p.elo, 2200);
    // the binary name, so two same-named engines are still tellable apart
    expect(p.blurb, contains('viri'));
  });

  test('upsert adds then updates by id; remove drops it', () async {
    final store = await loaded(MemoryDb([]));

    await store.upsert(const CustomEngine(id: 'a', name: 'A', path: '/a'));
    await store.upsert(const CustomEngine(id: 'b', name: 'B', path: '/b'));
    expect(store.engines.map((e) => e.name), ['A', 'B']);

    // same id updates in place, not a duplicate
    await store.upsert(
        const CustomEngine(id: 'a', name: 'A2', path: '/a', elo: 1800));
    expect(store.engines.map((e) => e.name), ['A2', 'B']);
    expect(store.engines.first.elo, 1800);

    await store.remove('a');
    expect(store.engines.map((e) => e.name), ['B']);
  });

  test('byPersonaId is the inverse of toPersona, and null for a stranger',
      () async {
    final store = await loaded(MemoryDb([]));
    await store
        .upsert(const CustomEngine(id: 'a', name: 'A', path: '/a', elo: 1600));

    final p = store.personas.single;
    expect(store.byPersonaId(p.id)?.id, 'a');
    // a built-in persona id is not ours
    expect(store.byPersonaId('squarefish-1500'), isNull);
    expect(store.byPersonaId(null), isNull);
    // a custom id for an engine that has been removed resolves to nothing
    expect(store.byPersonaId('custom-gone'), isNull);
  });

  test('survives a reload from the same database', () async {
    final db = MemoryDb([]);
    final first = await loaded(db);
    await first.upsert(const CustomEngine(
        id: 'keep', name: 'Keep', path: '/k', elo: 2000, limitElo: true));

    // a fresh store over the SAME db reads it back — this is the persistence
    final second = await loaded(db);
    expect(second.engines, hasLength(1));
    final e = second.engines.single;
    expect(e.name, 'Keep');
    expect(e.elo, 2000);
    expect(e.limitElo, isTrue);
  });

  test('a corrupt stored document starts empty rather than crashing', () async {
    final db = MemoryDb([]);
    await db.kvPut('custom_engines', 'not json {[');
    final store = await loaded(db);
    expect(store.engines, isEmpty);
    expect(store.isLoaded, isTrue);
  });

  group('historylessFen — the fix for the Velvet endgame panic', () {
    test('resets the halfmove clock to 0, since we send no move history', () {
      // A shuffling endgame with a high halfmove clock is exactly what tripped
      // velvet-chess pos_history.rs:65 (`positions.last().unwrap()` on an empty
      // history once the clock reached 3).
      const fen = '8/4k3/8/8/8/8/R7/1K6 b - - 41 44';
      expect(CustomEngineRunner.historylessFen(fen),
          '8/4k3/8/8/8/8/R7/1K6 b - - 0 44');
    });

    test('leaves the board, side, castling and fullmove number untouched', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 7 12';
      final out = CustomEngineRunner.historylessFen(fen).split(' ');
      expect(out[0], 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');
      expect(out[1], 'w');
      expect(out[2], 'KQkq');
      expect(out[4], '0', reason: 'the halfmove clock is zeroed');
      expect(out[5], '12', reason: 'the fullmove number is preserved');
    });

    test('a clock already under the panic threshold is still normalised', () {
      expect(CustomEngineRunner.historylessFen('8/8/8/8/8/8/8/K1k5 w - - 2 3'),
          '8/8/8/8/8/8/8/K1k5 w - - 0 3');
    });

    test('a malformed FEN with too few fields is passed through unchanged', () {
      expect(CustomEngineRunner.historylessFen('8/8/8 w'), '8/8/8 w');
    });
  });

  group('Rodent styles: one engine record becomes many style personas', () {
    Future<CustomEngineStore> withRodent(
        {int elo = 2600, bool limit = false}) async {
      final store = await loaded(MemoryDb([]));
      await store.upsert(CustomEngine(
          id: 'rodent',
          name: 'Rodent IV',
          path: '/r',
          elo: elo,
          limitElo: limit));
      return store;
    }

    test('one rodent record expands into one persona per catalog style',
        () async {
      final store = await withRodent();
      final styles = catalogEntryById('rodent')!.personalities;
      expect(store.personas.length, styles.length);
      expect(store.personas.every((p) => p.family == 'rodent'), isTrue);
      expect(
          store.personas
              .any((p) => p.name == 'Tal' && p.id == 'custom-rodent~tal'),
          isTrue);
    });

    test('a style persona resolves to the shared engine and its style file',
        () async {
      final store = await withRodent();
      expect(store.byPersonaId('custom-rodent~tal')?.id, 'rodent');
      expect(store.personalityFor('custom-rodent~tal'), 'tal.txt');
      // a plain engine persona has no style; an unknown style key resolves to
      // nothing rather than a wrong file
      expect(store.personalityFor('custom-v'), isNull);
      expect(store.personalityFor('custom-rodent~nope'), isNull);
    });

    test('the shared strength cap labels every style with that rating',
        () async {
      final store = await withRodent(elo: 1400, limit: true);
      expect(store.personas.every((p) => p.elo == 1400), isTrue,
          reason: 'strength is one engine-wide dial across the styles');
    });
  });

  testWidgets('a custom engine merges into the roster and resolves as a persona',
      (tester) async {
    // On this (desktop) host CustomEngineRunner.supported is true, so the
    // controller offers it. Both players null → analysis mode, no bot timer.
    final db = MemoryDb([]);
    final engines = await loaded(db);
    await engines.upsert(const CustomEngine(
        id: 'v', name: 'Viridithas', path: '/bin/viri', elo: 2500));
    final settings = await loadSettings();

    final g = GameController(FakeArbiter(), const FakeBot(), FakeGrading(),
        settings, db, null, null, engines);
    addTearDown(g.dispose);

    expect(g.rosterPersonas.any((p) => p.id == 'custom-v'), isTrue,
        reason: 'a custom engine is offered in the roster on desktop');
    final p = g.personaFor('custom-v');
    expect(p?.name, 'Viridithas');
    expect(p?.family, 'custom');
    expect(p?.elo, 2500);
  });
}
