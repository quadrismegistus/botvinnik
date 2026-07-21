// The player's rating, refit from the archive.
//
// The archive is the whole state: every finished game is already stored with
// its result, its opponent's persona id and the two flags that take a game off
// the ruler, so the rating is BACKFILLED from history on every refresh rather
// than accumulated. Nothing is persisted — there is no rating row to migrate,
// and no way for a stored number to drift out of step with the games it claims
// to summarise.
//
// On the remeasured bots (#70/#110, #104/#113): those commits moved the NATIVE
// knot table and added the substrate switch, and neither touched the wasm
// table (see the diff of brain/bot.ts in 25e3c8f — only the `native:` array
// changes, and #110's own message records that brain-fixtures.json came out
// byte-identical "because nothing selects the native table yet"). Web is the
// only surface that has shipped, and web is wasm. So no archived game a user
// holds was played against a bot whose label has since changed meaning, and
// the backfill is over a consistent ruler. That would stop being true the day
// a native build ships and then gets recalibrated: at that point the record
// would need to carry its substrate, which today it does not.

import 'package:flutter/foundation.dart';

import '../brain/rating_api.dart';
import '../db/app_db.dart';

/// Above this standard error the fit exists but is not worth printing as a
/// number: the interval it comes with is wider than the gap between adjacent
/// halves of the roster, and a four-digit figure is read as a measurement.
///
/// A COUNT of games would have been the obvious gate and is the wrong one,
/// because the estimator's uncertainty does not follow the count alone. Run
/// against the shipped bundle over mixed results spread across Squares 1000 to
/// 1400, the se comes back 283, 206, 183, 162, 149, 139 for one through six
/// games — so 200 lets the number appear at the third. But four straight wins
/// over a single Square 1200 still reads 258, because the fit lands where the
/// player is expected to win nine times in ten and each further win says
/// almost nothing. That archive has four games and has not measured anything,
/// and gating on the se is what knows the difference. `playerElo.ts` describes
/// the same quantity in its own words: "huge until ~8-10 games".
const int kMaxUsefulSe = 200;

class PlayerRatingStore extends ChangeNotifier {
  final AppDb _db;
  final RatingApi _api;

  /// How often [refresh] looks for the game that just ended, and how long it
  /// keeps looking. Injectable so a test does not spend twenty seconds proving
  /// the give-up path.
  ///
  /// [pollDeadline] outlives GameController.kSaveGradeWaitSeconds (16) on
  /// purpose: after a checkmate the archive write waits out that full timeout,
  /// because the terminal move's backfill never arrives — a mate position has
  /// no lines to search. Polling for less than that would give up before the
  /// game it is waiting for was ever written.
  final Duration pollInterval;
  final Duration pollDeadline;

  PlayerRatingStore(
    this._db,
    this._api, {
    this.pollInterval = const Duration(milliseconds: 400),
    this.pollDeadline = const Duration(seconds: 20),
  });

  /// The current fit, or null when the archive holds nothing on the ruler.
  PlayerRating? rating;

  /// What the newest archived game did to the number, or null when it did
  /// nothing — either because it was refused, or because it is the first one
  /// and there is no earlier estimate to compare against.
  int? delta;

  /// True when the newest archived game did NOT enter the fit. Decided by the
  /// brain (see [_apply]), not by reading the flags here.
  bool lastGameRefused = false;

  /// Why, in words, for the one game in [lastGameRefused]. Display only: the
  /// exclusion itself is the brain's call, so if this prose ever drifts from
  /// `playerElo.ts` the cost is a vague sentence, never a wrong rating.
  String? refusedReason;

  /// A just-finished game is still on its way to the archive. The number shown
  /// meanwhile is the rating BEFORE that game, which is true rather than
  /// stale — but the card says so.
  bool scoring = false;

  bool _disposed = false;

  /// Bumped by every [refresh]. A poll from an earlier call — the store
  /// outlives the card, so an abandoned game can leave one running for the
  /// rest of its deadline — stops the moment a newer call starts, rather than
  /// carrying on to clear [scoring] underneath it.
  int _gen = 0;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Refit from the archive.
  ///
  /// [expectNewGame] is for the moment a game ends: GameController archives it
  /// asynchronously, so the record is not there yet when the recap builds.
  /// Refitting once, there and then, would show a rating that excludes the
  /// game the player just finished — a number that is quietly wrong for as
  /// long as the recap is on screen. So the fit runs immediately AND again
  /// when the archive grows.
  Future<void> refresh({bool expectNewGame = false}) async {
    final gen = ++_gen;
    var raw = await _db.listGames();
    if (_disposed || gen != _gen) return;
    _apply(raw);
    if (!expectNewGame) {
      // Cleared rather than left alone: this call may have superseded a poll
      // that set it, and that poll now returns without reaching its own reset.
      // A card stuck saying "Adding this game..." forever is the failure.
      scoring = false;
      _notify();
      return;
    }
    // The id to watch for change, taken from the RAW list rather than from
    // what [_fit] would keep: a bot-vs-bot game is dropped from the fit but is
    // still the record being waited on, and watching the filtered list would
    // sit out the whole deadline for one.
    final before = raw.isEmpty ? null : raw.first['id'];
    scoring = true;
    _notify();
    final deadline = DateTime.now().add(pollDeadline);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      if (_disposed || gen != _gen) return;
      raw = await _db.listGames();
      if (_disposed || gen != _gen) return;
      if (raw.isNotEmpty && raw.first['id'] != before) {
        _apply(raw);
        break;
      }
    }
    scoring = false;
    _notify();
  }

  void _apply(List<Map<String, dynamic>> raw) {
    final current = _api.estimate(_fit(raw));
    // The same fit with the newest game held back. Dropped from the RAW list —
    // listGames orders by endedAt DESC, so raw.first is the newest game
    // whether or not it survives the filter below. Dropping the head of the
    // FILTERED list instead would hold back a different, older game whenever
    // the newest one was filtered out, and the comparison further down would
    // then report that game as having counted.
    final previous =
        raw.isEmpty ? null : _api.estimate(_fit(raw.sublist(1)));

    rating = current;
    // Whether the newest game counted is read off the brain's OWN game counts.
    // Removing one record can only change that count by 0 or 1, so a count
    // that did not move means the estimator refused it — and asking this way
    // means the refusal rule lives in exactly one place.
    final counted =
        current != null && current.games == (previous?.games ?? 0) + 1;
    delta = counted && previous != null ? current.elo - previous.elo : null;
    lastGameRefused = raw.isNotEmpty && !counted;
    refusedReason = lastGameRefused ? _reasonFor(raw.first) : null;
  }

  /// The archive as the estimator gets it.
  ///
  /// Every exclusion is the brain's — botFallback, botUndos and botBothSides
  /// are all refused by estimatePlayerElo itself. This filtered here for one
  /// commit, because `botBothSides` was a Flutter-only field the brain's
  /// StoredGame did not declare; it does now, and the rule moved next to the
  /// other two so a future consumer of the archive cannot miss it.
  List<Map<String, dynamic>> _fit(List<Map<String, dynamic>> raw) =>
      [for (final g in raw) _forFit(g)];

  /// The record as the estimator gets it: everything except the move list.
  ///
  /// SUBTRACTIVE on purpose. A projection that copied out the fields the
  /// estimator reads today would silently stop feeding it a field added
  /// tomorrow — and the fields most likely to be added are more exclusions,
  /// which is the failure that counts assisted games as clean ones. Dropping
  /// `moves` is safe because nothing in `playerElo.ts` reads it (checked
  /// against the bundle: a record with no `moves` key at all fits fine), and
  /// it is worth doing because the moves are ~99% of the bytes and the whole
  /// archive is JSON-encoded on the UI thread for every fit.
  Map<String, dynamic> _forFit(Map<String, dynamic> game) =>
      Map<String, dynamic>.of(game)..remove('moves');

  /// Prose for one refused game. Ordered by what the player most needs to
  /// hear: the two flags that describe something they did or that happened to
  /// them come before the structural reasons.
  String? _reasonFor(Map<String, dynamic> game) {
    final undos = (game['botUndos'] as num?)?.toInt() ?? 0;
    if (game['botFallback'] == true) {
      return 'your opponent was substituted part-way through';
    }
    if (undos > 0) {
      return undos == 1 ? 'you took a move back' : 'you took $undos moves back';
    }
    if (game['botBothSides'] == true) return 'both sides were bots';
    if (game['botPersona'] == null) return 'there was no bot opponent';
    if (game['result'] == '*') return 'it has no result';
    return null;
  }

  /// The number is worth printing: there is a fit and its own error bar is
  /// small enough to distinguish it from a neighbouring one.
  bool get confident => rating != null && (rating!.se ?? 9999) <= kMaxUsefulSe;
}
