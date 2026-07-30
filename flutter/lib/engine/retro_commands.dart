// The UCI a retro engine is asked to move with — one definition, three
// transports (Web Worker, spawned process, linked archive).
//
// It lives alone, and is pure, so it can be TESTED. The order below is not a
// style choice: sending `position` without `ucinewgame` first is what handed
// whole games to a Stockfish stand-in, and the bug was invisible from the Dart
// side — the engine simply stopped answering. Three copies of an order that
// matters is three chances to drop it silently.

/// The commands that ask a retro engine for a move, in order.
///
/// [fen] is the position the game STARTED from and [moves] the line played
/// since, in UCI — not the current position on its own. The difference is
/// #244, and it is not cosmetic: a board rebuilt from a bare FEN has no move
/// history (`b.current.prev == nil`), and these engines read it.
///
///   * SARGON's `Development` term (`cmd/sargon/sargon/eval.go`) calls
///     `b.HasMoved`, which walks the move list. From a bare FEN it comes back
///     empty, so **every knight and bishop scores as undeveloped, −2 each, for
///     the whole game**, and `HasCastled` is never true so the king term is 0
///     instead of +6. On SARGON's crude scale that changes move choice.
///   * TUROCHAMP's quiescence (`quiescence.go`) uses `SecondToLastMove` to
///     decide whether a recapture is "considerable" — Turing's own rule,
///     absent at the root of every search.
///   * Both: `alphabeta.go` checks `Result().Outcome == Draw`, and a one-entry
///     repetition map cannot see a repetition against the game.
///
/// This also matches how the engines were MEASURED. `scripts/calibrate-bots.mts`
/// drives them with `position startpos moves …`, and so did the lichess-bot run
/// that produced the advertised human-pool ratings — so the bare-FEN client was
/// playing a subtly different bot from the one the roster advertises.
///
/// Compatible with the `ucinewgame` above: that resets `lastPosition`, so this
/// takes morlock's "New position" branch, which resets and then applies the
/// move list. The history is rebuilt each turn rather than relying on the
/// prefix-matching continuation path — the one with the empty-token bug
/// (herohde/morlock#6).
///
/// Cost is trivial at these lengths: the engines search 1–2 ply and replaying
/// 200 positions measured 35ms against a 500ms budget.
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
List<String> retroMoveCommands(
  String fen,
  int movetimeMs, {
  List<String> moves = const [],
}) =>
    [
      'ucinewgame',
      // No trailing `moves` with nothing after it: morlock splits the
      // remainder on spaces, so `position fen X moves ` yields one empty token
      // and the driver returns on it — the same fatal shape as the repeated
      // line. calibrate-bots.mts guards the identical case.
      if (moves.isEmpty)
        'position fen $fen'
      else
        'position fen $fen moves ${moves.join(' ')}',
      'go movetime $movetimeMs',
    ];
