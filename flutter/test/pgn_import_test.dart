// PGN import: a pasted game becomes the archive's stored-game document.
// Pure input → output, so it needs no harness at all.
//
//   cd flutter && flutter test test/pgn_import_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/pgn_import.dart';

final _now = DateTime.utc(2026, 7, 20, 12);

const _scholars = '''
[Event "Casual game"]
[White "Alice"]
[Black "Bob"]
[Date "2026.03.04"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0
''';

void main() {
  group('gameFromPgn', () {
    test('replays the mainline into stored moves', () {
      final g = gameFromPgn(_scholars, now: _now)!;
      expect(g['moveCount'], 7);
      final moves = (g['moves'] as List).cast<Map<String, dynamic>>();
      expect(moves.first['san'], 'e4');
      expect(moves.first['uci'], 'e2e4');
      expect(moves.first['color'], 'w');
      expect(moves.first['ply'], 1);
      expect(moves.last['san'], 'Qxf7#');
      expect(moves.last['color'], 'w');
      // every move carries the positions Review steps between
      for (final m in moves) {
        expect(m['fenBefore'], isA<String>());
        expect(m['fenAfter'], isA<String>());
      }
      // and each move's fenAfter is the next one's fenBefore
      for (var i = 1; i < moves.length; i++) {
        expect(moves[i]['fenBefore'], moves[i - 1]['fenAfter']);
      }
    });

    test('keeps the headers worth showing', () {
      final g = gameFromPgn(_scholars, now: _now)!;
      expect(g['result'], '1-0');
      expect(g['white'], 'Alice');
      expect(g['black'], 'Bob');
      expect(g[kImportedKey], isTrue);
      expect(importedTitle(g), 'Alice — Bob');
      // the PGN date, not the import time
      expect((g['endedAt'] as String).startsWith('2026-03-04'), isTrue);
    });

    test('falls back to the import time when the date is unusable', () {
      const pgn = '[Date "????.??.??"]\n[Result "*"]\n\n1. e4 *';
      final g = gameFromPgn(pgn, now: _now)!;
      expect((g['endedAt'] as String).startsWith('2026-07-20'), isTrue);
    });

    test('honours a FEN header so a study position imports from its start', () {
      const pgn = '[FEN "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"]\n[Result "*"]\n\n1. e4 *';
      final g = gameFromPgn(pgn, now: _now)!;
      final first = (g['moves'] as List).first as Map<String, dynamic>;
      expect(first['fenBefore'], startsWith('4k3/8/8/8/8/8/4P3/4K3'));
      expect(first['uci'], 'e2e4');
    });

    test('takes the mainline and drops variations', () {
      const pgn = '[Result "*"]\n\n1. e4 (1. d4 d5) 1... e5 2. Nf3 *';
      final moves =
          (gameFromPgn(pgn, now: _now)!['moves'] as List).cast<Map>();
      expect(moves.map((m) => m['san']), ['e4', 'e5', 'Nf3']);
    });

    test('truncates at the first move that does not fit, keeping the rest', () {
      // Nf6 is not legal for White on move 2 — keep e4/e5 rather than refuse
      const pgn = '[Result "*"]\n\n1. e4 e5 2. Nf6 *';
      final moves =
          (gameFromPgn(pgn, now: _now)!['moves'] as List).cast<Map>();
      expect(moves.map((m) => m['san']), ['e4', 'e5']);
    });

    test('returns null for input with no legal moves', () {
      expect(gameFromPgn('', now: _now), isNull);
      expect(gameFromPgn('not a pgn at all', now: _now), isNull);
      expect(gameFromPgn('[Result "*"]\n\n*', now: _now), isNull);
    });

    test('titles an import with whatever the PGN gave', () {
      expect(importedTitle({'white': 'A', 'black': 'B'}), 'A — B');
      expect(importedTitle({'event': 'Candidates'}), 'Candidates');
      expect(importedTitle(const {}), 'Imported game');
    });
  });
}
