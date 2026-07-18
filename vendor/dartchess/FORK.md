# This is a fork

Upstream: <https://github.com/lichess-org/dartchess>
Forked from: **commit `ddd6668`**, version **0.13.1**

## Why

dartchess targets native platforms only. It stores bitboards as 64-bit
integers, which a JavaScript number cannot represent, so the library does not
compile for the web — and `chessground` depends on it, which means the board
cannot either.

## What changed

- **`lib/src/square_set.dart`** is now a conditional export over two
  implementations. `square_set_native.dart` is upstream's file with one
  additive constructor (`SquareSet.fromHiLo`) and is otherwise byte-identical,
  so native behaviour and performance are unchanged. `square_set_web.dart`
  stores the board as a record of two 32-bit halves — the only representation
  that stays const-constructible, which the class needs for its 13 constant
  bitboards.
- **`lib/src/setup.dart`** — `Pockets` packed 60 bits into one field; it is now
  one 30-bit field per side, which fits everywhere and needs no split.
- **`board.dart`, `castles.dart`, `debug.dart`** — 64-bit literals rewritten
  through `SquareSet.fromHiLo`.
- **`test/web_perft_test.dart`** — new; perft with no file I/O so it runs in
  both VMs.

## Verifying a rebase

```sh
dart test -x full_perft                        # native: 22,795 tests
dart test -p chrome test/web_perft_test.dart   # web: the 32-bit halves
```

Perft node counts are exact and published, so a single wrong bit fails loudly.
After rebasing onto a newer upstream, re-apply the four changes above and run
both suites before trusting the result.

## Licence

dartchess is GPLv3, and this is a modified version being distributed — the
source-disclosure obligation applies to these changes too. They live here, in
the same public repository as the rest of the app.
