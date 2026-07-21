// Per-persona head-to-head record, aggregated from the archive.
//
// The archive is the whole state: every finished bot game already carries the
// three fields a record needs — the opponent's persona id, the game's result,
// and which colour the bot played (`botColor` is the side the human did NOT) —
// so the record is BACKFILLED from history every time it is asked for, rather
// than stored. Nothing new is persisted, the same shape as the player's rating
// (player_rating_store.dart).
//
// It is a LIGHTER thing than the rating, though, and counts differently. The
// rating is a calibrated measurement and refuses every game that could distort
// it: a substituted opponent, a takeback, a hint on the board, a casual game.
// A head-to-head record is not a measurement — it answers "how have the games
// you played against this face gone" — so it counts them all. The exclusions
// it DOES make are only the ones that would make the count answer a different
// question than the one the player asked:
//
//   - a game with no persona resolves to null (analysis, an imported PGN with
//     real player names) — not a game against a roster bot at all. This is the
//     same `if (!p) continue` guard estimatePlayerElo opens with.
//   - a bot-vs-bot game (`botBothSides`) has no human in it, so no human
//     result. playerColor falls back to White when both sides carry a persona,
//     so such a game archives looking like a human White game — the same trap
//     #144 fixed for crowns — and counting it would credit or debit the player
//     for a game nobody played.
//   - an undecided result ('*') is neither a win, a loss, nor a draw.

import 'package:flutter/foundation.dart';

import '../brain/types.dart';
import '../db/app_db.dart';

/// One persona's record from the human's point of view. Immutable so the map
/// below can be handed to a widget without a defensive copy; the adders return
/// a new value rather than mutating in place.
@immutable
class BotRecord {
  final int won;
  final int lost;
  final int drawn;
  const BotRecord({this.won = 0, this.lost = 0, this.drawn = 0});

  int get played => won + lost + drawn;

  BotRecord addWin() => BotRecord(won: won + 1, lost: lost, drawn: drawn);
  BotRecord addLoss() => BotRecord(won: won, lost: lost + 1, drawn: drawn);
  BotRecord addDraw() => BotRecord(won: won, lost: lost, drawn: drawn + 1);

  @override
  bool operator ==(Object other) =>
      other is BotRecord &&
      other.won == won &&
      other.lost == lost &&
      other.drawn == drawn;

  @override
  int get hashCode => Object.hash(won, lost, drawn);

  @override
  String toString() => 'BotRecord($won-$lost-$drawn)';
}

/// Aggregate the archive into a per-persona human W-L-D record.
///
/// Records are keyed by the RESOLVED persona id. [resolve] turns a stored id —
/// which may PREDATE a rename (the 2026-07-21 `square-*`/`fish-*` pass) — into
/// its current persona, so a game archived under `square-1000` counts under
/// `squarefish-1000`, the id the roster row carries. Comparing the raw stored
/// id instead silently drops every renamed game, the bug that shipped twice
/// this session (persona_rename_test.dart). Resolution is the caller's: pass
/// `GameController.personaFor`, which crosses the bridge to the brain's
/// `personaById` and honours the migration.
///
/// A win is `result == '1-0' && botColor == 'b'` (the human was White and won)
/// or `result == '0-1' && botColor == 'w'` (the human was Black and won) — the
/// same mapping as `playerScore` in brain/playerElo.ts.
Map<String, BotRecord> botRecordsFrom(
  Iterable<Map<String, dynamic>> games,
  Persona? Function(String?) resolve,
) {
  final records = <String, BotRecord>{};
  for (final g in games) {
    final p = resolve(g['botPersona'] as String?);
    if (p == null) continue; // analysis, imports, a persona no longer on roster
    if (g['botBothSides'] == true) continue; // no human — no human result
    final result = g['result'] as String?;
    final botColor = g['botColor'] as String?;
    final cur = records[p.id] ?? const BotRecord();
    if (result == '1/2-1/2') {
      records[p.id] = cur.addDraw();
    } else if (result == '1-0') {
      records[p.id] = botColor == 'b' ? cur.addWin() : cur.addLoss();
    } else if (result == '0-1') {
      records[p.id] = botColor == 'w' ? cur.addWin() : cur.addLoss();
    }
    // '*' (unfinished/abandoned) and any unexpected value count as nothing.
  }
  return records;
}

/// Holds the per-persona records for the roster picker. Refit from disk on
/// demand — like the Maia cache marks in the same sheet, the record is a claim
/// about the archive, so the archive is what it is read from every time the
/// sheet opens rather than a number accumulated and left to drift.
class BotRecordStore extends ChangeNotifier {
  final AppDb _db;
  BotRecordStore(this._db);

  /// Keyed by resolved persona id. Empty until the first [refresh].
  Map<String, BotRecord> records = const {};

  /// Recompute from the whole archive. [resolve] is passed in rather than held
  /// because the resolver lives on GameController, which this store is built
  /// beside at boot — taking it here keeps the two providers independent.
  Future<void> refresh(Persona? Function(String?) resolve) async {
    records = botRecordsFrom(await _db.listGames(), resolve);
    notifyListeners();
  }

  BotRecord recordFor(String personaId) =>
      records[personaId] ?? const BotRecord();
}
