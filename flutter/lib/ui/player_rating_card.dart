// The player's rating, shown in the game-over recap.
//
// Placed there rather than kept permanently on screen because that is the one
// moment the number can have changed: a result just landed, and the recap is
// already the place the app says what the game was. The two other candidates
// were rejected for a reason each — the Play app bar at 375px is already
// carrying undo, redo, blind mode and a labelled New game button beside a
// title that has to shrink to fit them, and Settings and the archive belong to
// other work this wave.
//
// Nothing here decides what counts. The card asks [PlayerRatingStore], which
// asks the brain; when it says a game was refused, that is the brain's own
// game count having failed to move, not a rule reimplemented in the UI.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/player_rating_store.dart';

class PlayerRatingCard extends StatefulWidget {
  /// A game has just ended and its record may not have reached the archive
  /// yet — wait for it rather than printing a rating that excludes it.
  final bool afterGame;

  const PlayerRatingCard({super.key, this.afterGame = false});

  @override
  State<PlayerRatingCard> createState() => _PlayerRatingCardState();
}

class _PlayerRatingCardState extends State<PlayerRatingCard> {
  @override
  void initState() {
    super.initState();
    // Mounted once per game-over: the recap is behind `if (game.gameOver)`, so
    // the card is torn down when the next game starts and rebuilt when it
    // ends. That is what makes initState the right hook — there is no stale
    // instance to re-trigger.
    context
        .read<PlayerRatingStore>()
        .refresh(expectNewGame: widget.afterGame);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlayerRatingStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_outlined,
                  size: 13, color: Colors.white38),
              const SizedBox(width: 6),
              const Text('YOUR RATING',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.1,
                      color: Colors.white38,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ..._body(store),
          if (store.refusedReason != null && !store.scoring) ...[
            const SizedBox(height: 4),
            Text('This game did not count: ${store.refusedReason}.',
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
          if (store.scoring) ...[
            const SizedBox(height: 4),
            // ASCII dots rather than U+2026: the ellipsis is not on the short
            // list of non-ASCII characters known to be covered here.
            const Text('Adding this game...',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ],
      ),
    );
  }

  List<Widget> _body(PlayerRatingStore store) {
    final rating = store.rating;
    if (rating == null) {
      return const [
        Text('No rated games yet',
            style: TextStyle(fontSize: 14, color: Colors.white70)),
        SizedBox(height: 2),
        Text(
            'Finish a game against a bot from the roster. Games with takebacks '
            'and games where the opponent had to be substituted are not rated.',
            style: TextStyle(fontSize: 11, color: Colors.white38)),
      ];
    }

    // Below the confidence floor the number itself is withheld. An estimate
    // from one or two games carries an error bar wide enough to cover most of
    // the roster, and a precise-looking figure is read as a measurement — so
    // what is shown instead is the progress towards one.
    if (!store.confident) {
      final n = rating.games;
      return [
        const Text('Not enough rated games yet',
            style: TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 2),
        Text(
            '${n == 1 ? '1 game counts' : '$n games count'} so far. A couple '
            'more and the estimate is worth a number.',
            style: const TextStyle(fontSize: 11, color: Colors.white38)),
      ];
    }

    // A loose fit is printed WITH its error bar rather than withheld: the
    // number is real, its precision is what is in doubt, and saying so is more
    // use than a progress message that reverses when the player wins well.
    final delta = store.delta;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${rating.elo}',
              style: const TextStyle(
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF81B64C))),
          // Not while scoring: `delta` is still the previous fit's, so a green
          // up-arrow sat on a game the player had just lost, for as long as the
          // save's grade wait ran. `refusedReason` was already gated this way.
          if (delta != null && delta != 0 && !store.scoring) ...[
            const SizedBox(width: 8),
            Icon(delta > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13,
                color: delta > 0
                    ? const Color(0xFF81B64C)
                    : const Color(0xFFCA3431)),
            Text('${delta.abs()}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: delta > 0
                        ? const Color(0xFF81B64C)
                        : const Color(0xFFCA3431))),
          ],
        ],
      ),
      const SizedBox(height: 2),
      Text(
          // '·' and '—' are the only non-ASCII punctuation known to be covered
          // by the bundled Roboto; anything else here is a font download on
          // web. That rules out '±', so the error bar is spelled out.
          'from ${rating.games} rated '
          '${rating.games == 1 ? 'game' : 'games'}'
          '${rating.se == null ? '' : ' · give or take ${rating.se}'}',
          style: const TextStyle(fontSize: 11, color: Colors.white38)),
    ];
  }
}
