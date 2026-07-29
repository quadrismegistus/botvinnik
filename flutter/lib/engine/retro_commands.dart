// The UCI a retro engine is asked to move with — one definition, three
// transports (Web Worker, spawned process, linked archive).
//
// It lives alone, and is pure, so it can be TESTED. The order below is not a
// style choice: sending `position` without `ucinewgame` first is what handed
// whole games to a Stockfish stand-in, and the bug was invisible from the Dart
// side — the engine simply stopped answering. Three copies of an order that
// matters is three chances to drop it silently.

/// The commands that ask a retro engine for a move in [fen], in order.
///
/// `ucinewgame` FIRST, every time. morlock's UCI driver treats a `position`
/// line that PREFIXES the last one as a continuation of the game and parses
/// the remainder as moves — so an IDENTICAL line leaves an empty remainder,
/// `Move(ctx, "")` fails, and the driver RETURNS, which ends the engine. In a
/// worker that death is silent: the client waits out its whole timeout and
/// stands in, for the rest of the game, because the badge is sticky.
///
/// Reachable in one new game (the bot's opening `position` repeats verbatim)
/// and by a takeback that replays the same move. Reported upstream as
/// herohde/morlock#6; `ucinewgame` resets the driver's `lastPosition` and
/// costs nothing here, because a client that always sends a whole FEN and
/// never a `moves` list was already taking the engine's reset path.
List<String> retroMoveCommands(String fen, int movetimeMs) => [
      'ucinewgame',
      'position fen $fen',
      'go movetime $movetimeMs',
    ];
