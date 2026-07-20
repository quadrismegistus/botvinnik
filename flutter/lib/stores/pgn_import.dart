// Turning a pasted PGN into the same stored-game document the app archives,
// so an imported game steps through Review exactly like one you played.
//
// Pure — no database, no engine, no widgets — which is what makes it directly
// unit-testable. An import carries no grades: nothing here has been analysed,
// so there are no labels, no accuracy and no best-move arrows, and Review
// already reads every one of those as nullable.

import 'package:dartchess/dartchess.dart';

/// The document key that marks a game as imported rather than played. The
/// archive list keys off it: "Won/Lost" is meaningless for a game you were
/// not a player in.
const kImportedKey = 'imported';

/// Parse [pgn] into the archive's stored-game shape, or null if it carries no
/// legal moves. [now] is passed in rather than read so the result is
/// deterministic and testable.
///
/// The mainline only: variations are dropped, which is what "step through this
/// game" means. Parsing stops at the first move that does not fit the position
/// — a truncated import beats refusing a PGN with one bad ply near the end.
Map<String, dynamic>? gameFromPgn(String pgn, {required DateTime now}) {
  final PgnGame<PgnNodeData> parsed;
  Position pos;
  try {
    parsed = PgnGame.parsePgn(pgn);
    // honours a FEN header, so a study position imports from where it starts
    pos = PgnGame.startingPosition(parsed.headers);
  } catch (_) {
    return null;
  }

  final moves = <Map<String, dynamic>>[];
  for (final node in parsed.moves.mainline()) {
    final move = pos.parseSan(node.san);
    if (move == null) break; // illegal or unreadable: keep what we have
    final fenBefore = pos.fen;
    final color = pos.turn == Side.white ? 'w' : 'b';
    try {
      pos = pos.play(move);
    } catch (_) {
      break;
    }
    moves.add({
      'ply': moves.length + 1,
      'san': node.san,
      'uci': move.uci,
      'color': color,
      'fenBefore': fenBefore,
      'fenAfter': pos.fen,
      // no analysis behind an import, so nothing was lost by any move
      'wcDrop': 0.0,
    });
  }
  if (moves.isEmpty) return null;

  final headers = parsed.headers;
  final white = headers['White']?.trim();
  final black = headers['Black']?.trim();
  return {
    'id': 'import-${now.millisecondsSinceEpoch}-${moves.length}',
    'endedAt': (_headerDate(headers['Date']) ?? now).toIso8601String(),
    'result': headers['Result'] ?? '*',
    'pgn': pgn.trim(),
    'moveCount': moves.length,
    kImportedKey: true,
    'white': (white == null || white.isEmpty || white == '?') ? null : white,
    'black': (black == null || black.isEmpty || black == '?') ? null : black,
    'event': headers['Event'],
    'moves': moves,
  };
}

/// A PGN date is `YYYY.MM.DD`, often with `??` for unknown parts. Returns null
/// unless the whole thing is real, so the archive falls back to the import
/// time rather than sorting a game to the epoch.
DateTime? _headerDate(String? raw) {
  if (raw == null) return null;
  final parts = raw.trim().split('.');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, m, d);
}

/// How the archive list should name an imported game: the two players when the
/// PGN gave them, else the event, else a plain fallback.
String importedTitle(Map<String, dynamic> game) {
  final white = game['white'] as String?;
  final black = game['black'] as String?;
  if (white != null && black != null) return '$white — $black';
  return (white ?? black ?? game['event'] as String?) ?? 'Imported game';
}
