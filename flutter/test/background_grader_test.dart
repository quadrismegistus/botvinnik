// The background grading pass (#170): grade ungraded archived games and seed
// practice from the blunders, without ever spoiling live play.
//
// The arbiter's PRIORITY contract — that a background grade yields to and is
// preempted by everything above it — is pinned in arbiter_test.dart against the
// real SearchArbiter. Here the concern is the SERVICE's own behaviour: which
// games it grades, that it seeds only the human's mistakes, that it stops the
// instant a game is on the board, and that an interruption checkpoints per game
// rather than starting the archive over. The arbiter and grading are faked so
// this runs in pure Dart; what the brain does with a grade is covered by
// lichess_import_test / practice_collection_test.
//
//   cd flutter && flutter test test/background_grader_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/background_grader.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';

// Distinct legal-enough FEN strings; nothing in the faked path parses them, but
// real ones keep the fixtures honest about what a stored move carries.
const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _afterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
const _afterE5 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
const _afterNf3 =
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
const _afterNc6 =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

/// An ungraded archived game in the shape the import paths and pgn_import.dart
/// produce: fenBefore/fenAfter/san/uci/color/ply on every move, a label on
/// none. [botColor] is the side the human did NOT play, so botColor 'b' means
/// the human is White.
Map<String, dynamic> _ungraded(String id,
        {String botColor = 'b', bool fourMoves = false}) =>
    {
      'id': id,
      'endedAt': '2026-07-20T12:00:00.000Z',
      'result': '1-0',
      'pgn': '1. e4 e5',
      'source': 'chesscom',
      'botColor': botColor,
      'white': 'me',
      'black': 'them',
      'moveCount': fourMoves ? 4 : 2,
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': _start,
          'fenAfter': _afterE4,
          'wcDrop': 0.0,
        },
        {
          'ply': 2,
          'san': 'e5',
          'uci': 'e7e5',
          'color': 'b',
          'fenBefore': _afterE4,
          'fenAfter': _afterE5,
          'wcDrop': 0.0,
        },
        if (fourMoves) ...[
          {
            'ply': 3,
            'san': 'Nf3',
            'uci': 'g1f3',
            'color': 'w',
            'fenBefore': _afterE5,
            'fenAfter': _afterNf3,
            'wcDrop': 0.0,
          },
          {
            'ply': 4,
            'san': 'Nc6',
            'uci': 'b8c6',
            'color': 'b',
            'fenBefore': _afterNf3,
            'fenAfter': _afterNc6,
            'wcDrop': 0.0,
          },
        ],
      ],
    };

/// A game already carrying grades — must be left alone.
Map<String, dynamic> _graded(String id) => {
      'id': id,
      'endedAt': '2026-07-19T12:00:00.000Z',
      'botColor': 'b',
      'moveCount': 1,
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': _start,
          'fenAfter': _afterE4,
          'wcDrop': 2.0,
          'label': 'best',
          'depth': 20,
        },
      ],
    };

/// Records the seeds handed to collectAll, without the brain round trip the
/// real one makes. collectAll is the only method the grader calls on it.
class RecordingPractice implements PracticeController {
  final List<List<({Map<String, dynamic> move, String? setupUci})>> calls = [];

  @override
  Future<int> collectAll(
      List<({Map<String, dynamic> move, String? setupUci})> seeds,
      {int minDepth = 8}) async {
    calls.add(seeds);
    return seeds.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

BackgroundGrader _grader(
  MemoryDb db,
  RecordingPractice practice,
  ValueNotifier<bool> live,
) =>
    BackgroundGrader(
      // resolves every search immediately with depth-15 lines
      FakeArbiter(searchLines: kFakeLines),
      db,
      // SavingGrading: gradeMove returns a blunder-shaped grade; gameAccuracy /
      // labelCounts answer so a save can complete
      SavingGrading(),
      practice,
      live,
      () => live.value,
    );

void main() {
  test('grades every ungraded game and leaves graded ones alone', () async {
    final db = MemoryDb([_ungraded('g1'), _graded('done'), _ungraded('g2')]);
    final practice = RecordingPractice();
    final live = ValueNotifier(false);
    final grader = _grader(db, practice, live);

    grader.start();
    await grader.pass;

    // both ungraded games written back, the already-graded one never touched
    expect(db.writes..sort(), ['g1', 'g2']);
    expect(db.writes, isNot(contains('done')));
    // and the write really carries grades now
    expect((db.games['g1']!['moves'] as List).first['label'], 'blunder');
    expect(db.games['g1']!['labelVersion'], 1);
  });

  test('seeds practice from the human\'s moves only', () async {
    // human is White (botColor 'b'); a four-move game has two White plies
    final db = MemoryDb([_ungraded('g1', fourMoves: true)]);
    final practice = RecordingPractice();
    final grader = _grader(db, practice, ValueNotifier(false));

    grader.start();
    await grader.pass;

    expect(practice.calls, hasLength(1)); // one collectAll for the game
    final seeds = practice.calls.single;
    expect(seeds.map((s) => s.move['color']).toSet(), {'w'},
        reason: 'only the human (White) plies are seeded, never the opponent');
    expect(seeds.map((s) => s.move['uci']).toList(), ['e2e4', 'g1f3']);
    // the second seed carries the opponent's move into its position, for replay
    expect(seeds[1].setupUci, 'e7e5');
  });

  test('no human color means grade-only: no practice seeded', () async {
    final game = _ungraded('g1')..remove('botColor'); // e.g. a pasted PGN
    final db = MemoryDb([game]);
    final practice = RecordingPractice();
    final grader = _grader(db, practice, ValueNotifier(false));

    grader.start();
    await grader.pass;

    expect(db.writes, ['g1']); // still graded
    expect(practice.calls, isEmpty); // but nothing collected — no "you"
  });

  test('an empty-moves game is skipped, not crashed on', () async {
    final summary = _ungraded('summary')..['moves'] = <dynamic>[];
    final db = MemoryDb([summary, _ungraded('g1')]);
    final practice = RecordingPractice();
    final grader = _grader(db, practice, ValueNotifier(false));

    grader.start();
    await grader.pass;

    expect(db.writes, ['g1']); // the real game graded, the summary passed over
  });

  test('does not run while a live game is on the board', () async {
    final db = MemoryDb([_ungraded('g1')]);
    final practice = RecordingPractice();
    final live = ValueNotifier(true); // a game is being played from the start
    final grader = _grader(db, practice, live);

    grader.start();
    await grader.pass; // null while paused — completes at once
    expect(db.writes, isEmpty,
        reason: 'no archived game may be graded during live play');

    live.value = false; // the game ends
    await grader.pass;
    expect(db.writes, ['g1'], reason: 'grading is free to run once the game is over');
  });

  test('checkpoints per game across an interruption', () async {
    final live = ValueNotifier(false);
    // flip the board live the instant the first game is written back, as a real
    // game starting mid-sweep would
    final db = _InterruptingDb(
      [_ungraded('g1'), _ungraded('g2')],
      onFirstWrite: () => live.value = true,
    );
    final practice = RecordingPractice();
    final grader = _grader(db, practice, live);

    grader.start();
    await grader.pass;
    expect(db.writes, ['g1'],
        reason: 'the sweep stopped after the game it had finished');
    expect((db.games['g2']!['moves'] as List).first['label'], isNull,
        reason: 'g2 was left ungraded for later, not half-written');

    // the game ends: the sweep resumes and finishes g2 WITHOUT redoing g1 — a
    // finished game is the checkpoint
    live.value = false;
    await grader.pass;
    expect(db.writes, ['g1', 'g2']);
    expect((db.games['g2']!['moves'] as List).first['label'], 'blunder');
  });
}

/// A MemoryDb that fires [onFirstWrite] exactly once, on the first saveGame —
/// the seam a test uses to make a game appear mid-sweep.
class _InterruptingDb extends MemoryDb {
  final void Function() onFirstWrite;
  bool _fired = false;
  _InterruptingDb(super.initial, {required this.onFirstWrite});

  @override
  Future<void> saveGame(Map<String, dynamic> storedGame) async {
    await super.saveGame(storedGame);
    if (!_fired) {
      _fired = true;
      onFirstWrite();
    }
  }
}
