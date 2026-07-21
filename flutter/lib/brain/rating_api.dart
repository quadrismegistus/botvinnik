// The player's own rating, fit by the brain from the archived games.
//
// `estimatePlayerElo` (brain/playerElo.ts) is the entire model: a 1-D maximum
// likelihood fit over the logistic Elo model with the ROSTER's ratings held
// fixed, plus one virtual draw to keep an all-win record finite. None of that
// is reimplemented here. This file marshals a list of StoredGame records over
// and decodes what comes back.
//
// What the estimator DROPS matters as much as what it fits, and every drop
// happens on the far side of this call:
//
//   - no persona on the record (analysis and imported games)
//   - `botFallback` — the opponent was the Stockfish stand-in, not the persona
//   - `botUndos > 0` — the human took the result back at least once
//   - an undecided result ('*')
//
// So the records handed to [estimate] have to arrive with those fields intact.
// [PlayerRatingStore] is where that is arranged; test/player_rating_test.dart
// runs the real bundle over realistic records to prove it actually happens.

import 'js_bridge.dart';

/// One fit. All three numbers come from the brain; nothing here is derived.
class PlayerRating {
  /// Display scale (lichess-rapid-equivalent), the same scale the roster's
  /// personas are labelled on. Lands on the estimator's 5-point grid.
  final int elo;

  /// Standard error from the Fisher information at the MLE. Null when the
  /// brain returned Infinity — JSON has no such value, so it crosses as null.
  final int? se;

  /// How many games entered the fit. NEVER the number of games handed over:
  /// the difference is exactly the set the estimator refused, which is why
  /// this is the field the exclusion tests assert on.
  final int games;

  const PlayerRating({required this.elo, required this.se, required this.games});

  factory PlayerRating.fromJson(Map<String, dynamic> j) => PlayerRating(
        elo: (j['elo'] as num).round(),
        se: (j['se'] as num?)?.round(),
        games: (j['games'] as num).toInt(),
      );
}

class RatingApi {
  final JsBridge _bridge;
  const RatingApi(this._bridge);

  /// Null when no game in [games] is on the ruler — an empty archive, or one
  /// holding nothing but analysis, imports, substituted and taken-back games.
  PlayerRating? estimate(List<Map<String, dynamic>> games) {
    final raw = _bridge.call('estimatePlayerElo', args: [games]);
    if (raw == null) return null;
    return PlayerRating.fromJson((raw as Map).cast<String, dynamic>());
  }
}
