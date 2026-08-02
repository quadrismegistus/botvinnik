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

  // Per-move time, where the PGN carries it (#267). Two annotations exist and
  // they do not mean the same thing: %emt IS the elapsed time, while %clk is
  // the time REMAINING, which becomes an elapsed time only by differencing the
  // same side's consecutive readings and adding back the increment. lichess and
  // chess.com both write %clk; engines and some GUIs write %emt.
  final increment = _incrementSeconds(parsed.headers['TimeControl']);
  final lastClock = <String, Duration>{};

  final moves = <Map<String, dynamic>>[];
  for (final node in parsed.moves.mainline()) {
    final move = pos.parseSan(node.san);
    if (move == null) break; // illegal or unreadable: keep what we have
    final fenBefore = pos.fen;
    final color = pos.turn == Side.white ? 'w' : 'b';
    final thinkMs = _thinkMsFrom(node.comments, color, lastClock, increment);
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
      'thinkMs': ?thinkMs,
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

/// The increment from a PGN `TimeControl` header, or null when `%clk` cannot be
/// differenced at all under it.
///
/// Null is not "no increment" — it means REFUSE. Correspondence headers
/// ("1/259200", three days a move) and multi-period ones ("40/7200:3600") grant
/// time this importer cannot account for, and on a real chess.com daily game
/// differencing produced 50% nulls and hours-long garbage for the rest. Half
/// nothing and half wrong is worse than all nothing.
Duration? _incrementSeconds(String? header) {
  final h = header?.trim() ?? '';
  if (h.isEmpty || h == '-' || h == '?') return Duration.zero;
  if (RegExp(r'^\d+$').hasMatch(h)) return Duration.zero;
  final m = RegExp(r'^\d+\+(\d+)$').firstMatch(h);
  if (m != null) return Duration(seconds: int.parse(m.group(1)!));
  return null; // periods, correspondence, or something new: do not guess
}

/// H:MM:SS, MM:SS, or plain seconds with an optional fraction.
///
/// Bounded, because `total` is an unbounded double accumulated from whatever
/// the file says: `{[%emt 999…]}` with four hundred nines overflowed and
/// `Duration(...).round()` threw "Infinity or NaN toInt" out of gameFromPgn,
/// which could not throw before this existed — leaving the import dialog
/// spinning with no error and no way out. A merely large value stored a
/// NEGATIVE think time via int64 wraparound.
///
/// (No `v < 0` check: the regexes that feed this accept only `[0-9:.]`, so a
/// minus sign never reaches it. A guard that cannot fire is worse than none.)
Duration? _parseClock(String raw) {
  final parts = raw.split(':');
  if (parts.length > 3) return null;
  var total = 0.0;
  for (final part in parts) {
    final v = double.tryParse(part);
    if (v == null) return null;
    total = total * 60 + v;
  }
  // a day. Nothing honest about one move takes longer, and everything past
  // this is a malformed file rather than a long think.
  if (!total.isFinite || total < 0 || total > 86400) return null;
  return Duration(milliseconds: (total * 1000).round());
}

/// The elapsed time for one move, from its PGN comments.
///
/// `%emt` is taken as read. `%clk` is a remaining time, so it yields an elapsed
/// time only against this side's previous reading — which means the first move
/// of each side gets nothing, and a reading that goes backwards (an increment
/// larger than the header claims, a corrected clock, a PGN stitched from two
/// games) is dropped rather than guessed at.
int? _thinkMsFrom(List<String>? comments, String color,
    Map<String, Duration> lastClock, Duration? increment) {
  if (comments == null) return null;
  for (final c in comments) {
    final emt = RegExp(r'%emt\s+([0-9:.]+)').firstMatch(c);
    if (emt == null) continue;
    final d = _parseClock(emt.group(1)!);
    // Either way this side's remaining-time chain is broken: an elapsed time
    // cannot seed one. Without this the NEXT %clk differenced against a stale
    // reading and silently overstated by whatever the %emt move consumed —
    // 30s reported for a 20s move, persisted into the archive, in a file whose
    // stated policy is to drop rather than guess.
    lastClock.remove(color);
    if (d != null) return d.inMilliseconds;
    return null;
  }
  if (increment == null) return null; // a header we cannot account for
  for (final c in comments) {
    final clk = RegExp(r'%clk\s+([0-9:.]+)').firstMatch(c);
    if (clk == null) continue;
    final now = _parseClock(clk.group(1)!);
    if (now == null) {
      lastClock.remove(color); // an unreadable reading breaks the chain too
      return null;
    }
    final prev = lastClock[color];
    lastClock[color] = now;
    if (prev == null) return null; // nothing to difference against yet
    final spent = prev - now + increment;
    if (spent.isNegative) return null; // the clock went up: unreadable
    return spent.inMilliseconds;
  }
  return null;
}
