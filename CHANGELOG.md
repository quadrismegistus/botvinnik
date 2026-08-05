# Changelog

Shipped work, newest first. Open work lives in
[GitHub issues](https://github.com/quadrismegistus/botvinnik/issues); this file
is the record of what landed. Design rationale that is still load-bearing lives
in [ROADMAP.md](ROADMAP.md); the blow-by-blow for anything here is in the git
history of the referenced PR.

The full pre-2026-07-19 roadmap — with the complete calibration saga and every
design note as it was written — is preserved in git history (it was this file's
predecessor, `ROADMAP.md` before the 2026-07-19 trim).

## 2026-08-04 (evening) — the skill report: your axes beside the typical player's

The first visible face of #268, plus the data infrastructure underneath it —
built end-to-end in one arc: decisions on the issue, an offline pipeline, a
real month of lichess, and a screen.

- **#268** — **the skill report.** Games tab → the insights icon: four axes —
  keeping a won game, defence when worse, endgame, clock discipline — each
  showing your mean win-chance drop and blunder rate beside the *typical
  player of your rating band*, from a peer baseline distilled offline from
  **56 million July 2026 lichess games** (624KB of tables shipped as an
  asset; the pipeline that builds them lives in `pipeline/lichess/`, is
  reproducible byte-for-byte, and computes with the app's own shipped brain
  code so both sides of every comparison mean the same thing). Honesty is
  structural: no percentile language (the tables pool moves, not players),
  sample floors instead of confident numbers over thin data, visible
  excluded-game counts, and "no baseline" rather than an invented one.
  Tactics and opening axes come later (Maia's per-position judgment and an
  ECO dataset respectively).
- **#268** — **clocks are recorded now.** Rated games stamp `[%clk]` into
  their archived PGNs; lichess imports fetch clock comments; one brain
  parser reads clocks out of any PGN. Chess.com imports always carried them.
  This is what feeds the clock-discipline axis — data accrues from the day
  it ships.
- **#292** — **Clear local games / Clear practice puzzles**, in Settings
  beside backup. Both refuse while sync is on (a local wipe under live sync
  is undone by the next pull — the same lesson as #258's server delete, in
  the other direction), confirm with a count, and leave the other store
  untouched.

## 2026-08-04 — practice knows the mistakes you keep making

- **#286** — **one practice item per position, counting repeats.** The dedupe
  key is now the position itself (first four FEN fields, en passant kept only
  when a capture can use it), so the trap you walk into on move 12 and again
  on move 14 is one item that remembers both. Repeats bump a visible **×N**
  badge, break due-date ties in the collection browser, and survive redos:
  bulk seeds carry their game id, a refusal barrage counts one occurrence per
  (position, move), and a sync pull from a device on an older build re-keys
  before merging. Existing collections migrate (and merge their split twins)
  once, at load.
- **#287** — **collected mates and sacrifices finally tag.** A stored move now
  keeps the engine's line behind its best move — but only on practice
  candidates, so the archive and the sync payload barely grow — and the motif
  tagger walks that line: back-rank and smothered mates and sacrifices appear
  on collected items and in the motif picker. All FOUR stored-move writers
  (live play, the refusal path, the background grader, and the lichess
  importer — the one the first pass missed and review caught) stay in step.
- **#291** — deleting the last collected item mid-game-session no longer
  strands the session behind the empty screen; the session ends with the
  collection.
- Hardening from the adversarial review: a malformed practice item can no
  longer brick boot, and review scrubbing stops paying a bridge call per
  frame for the practise-this-game count.

## 2026-08-04 — a motif tap mid-session obeys the game session's own rules

- **#289** — **filtering by motif mid-session no longer breaks the session's
  own rules.** `setMotifFilter` had a second implementation of "what does this
  session serve" that agreed with the real one on scope and nothing else — a
  motif tap could serve a position the drop bar was specifically withholding,
  re-serve an item the walk had already served (three serves in a two-mistake
  game), or reopen a session that had already finished, wiping its "done"
  note. Fixed by routing the filter through the same server every other path
  uses, in both directions, and deleting the second implementation rather
  than reconciling it. The motif picker is now hidden outright while a game
  session runs — a filter the walk ignores could only lie or cost you a
  mistake for nothing — and the session's completion note counts what the
  walk actually served rather than the scope it started with, which mid-session
  churn had been quietly inflating. A four-lens review caught two mutants that
  survived the first fix and filed a smaller pre-existing bug — deleting your
  only collected item mid-session strands you behind an empty screen — as
  #291, fixed in the practice-mistakes release above.

## 2026-08-03 — practice scoped to this game, and your side of it

A bug report from actual play: practising "this game's mistakes" served
puzzles from other games, and from the bot's own moves.

- **#285** — **"practise this game's mistakes" now means your mistakes, in
  this game.** A practice item's id is its FEN, deduped across the whole
  collection — so the old scope ("every collected item whose position also
  occurred in this game") pulled in the bot's positions, and through the
  shared-FEN dedupe, items collected in entirely different games. The scope
  now filters to positions where you were the one to move. A first attempt
  also matched the exact move played, which sounded more exact but silently
  dropped a real class of this game's own mistakes — a blunder caught by
  refusal mode, or one you took back — since neither ever lands in the move
  list; reverted in review before merge. Left open on purpose: two different
  games where you had the same colour at the same position still share one
  item, which the dedupe design makes defensible rather than wrong. A game
  with no "you" in it at all — a pasted PGN, a spectator import, bot-vs-bot —
  now shows no practice button rather than one that mixes both sides.

## 2026-08-03 — bestUci means one thing everywhere, and a quiet mate stops hiding as a positional tip

Two provenance bugs, both about a stored record carrying less than the code
reading it assumed — the second found while building the first.

- **#281** — **`bestUci` means the same thing everywhere now.** On the import
  paths the field marked a MISS (present only when you didn't play the top
  move); live play used the same field to name the engine's move outright —
  the exact ambiguity that made #276's correlation read zero on every
  imported game. It's now the engine's first choice on every analysed ply,
  for chess.com imports and live play alike; a new `topRecorded` flag marks
  which games' writers made that promise, so chess.com imports move from a
  dash to a real number. lichess stays a dash — its API genuinely doesn't
  expose the engine's move on unflagged plies, so a dash is more honest than
  a guess. Caught in review before merge: the first pass of the fix reached
  only one of three code paths that write a stored move, so the on-device
  chess.com import and the background grader still lost the field; all three
  now agree.
- **#283** — **a quiet forced mate no longer files under "open file."**
  Collected practice items carried a one-move stub instead of the engine's
  real mate distance, so the motif tagger — which already held back
  positional claims on a move that gives check — had no way to see that a
  *quiet* move forces mate too. Fixed by threading the grade's own mate count
  through instead of hardcoding it to null.

## 2026-08-02 — per-move think time, and how often you agree with the engine

- **#267** — **a move now remembers how long it took.** `MoveRecord` gets a
  `thinkMs`, filled by a wall-clock timer on the position rather than the
  in-game chess clock (which exists only in a minority of games with a time
  control), so "do I blunder in time trouble" can be asked of any game. Time
  spent in the background doesn't count, a takeback voids the measurement
  instead of attributing it to the wrong decision, and older games simply
  carry null rather than a fabricated zero. Pasted PGNs pick up times from
  `%clk`/`%emt` comments too — but the chess.com and lichess import paths
  don't carry that data over yet, so an in-app import from either service has
  no times.
- **#276** — **one number per game: how often you played the engine's first
  choice.** `engineCorrelation` sits beside accuracy in the Review summary,
  because the two disagree usefully — high correlation with low accuracy is a
  game where you saw everything and then hung a rook. It excludes forced
  moves (no real choice) and ungraded ones (a dash, never a 0%). Shipped
  cautious on imports specifically: the pre-existing `bestUci` ambiguity
  (fixed next release, #281) meant every imported game would otherwise have
  scored a structurally wrong 0%, so this release gates on this app's own
  grading marker and shows a dash for imports instead of a lie.

## 2026-08-01 — positional facts for the quiet moves

- **#269** — **four new detectors give quiet, non-tactical moves something to
  say.** Passed pawn, outpost, blockade, and open/half-open file join the
  twelve-value tactical vocabulary — mate, forks, pins and the rest — that
  previously left every quiet move explained by eval alone. Each ranks below
  every tactical motif, sacrifice, promotion and the material count, so a
  fork that happens to land on an open file still explains as a fork;
  positional prose speaks only when nothing sharper does. Deliberately
  narrow — no space, initiative, or "bad bishop" judgment, because a
  plausible-sounding positional sentence with nothing in the position to
  check it against is worse than staying silent. Sparse by design: it fires
  on a small minority of plies in real games, since most moves are still
  explained by a tactical fact or by eval alone.

## 2026-07-31 — the lichess bot catches up with the repo, and the database leaves your Documents folder

Two weeks of undocumented VPS drift folded back in, plus a macOS
storage-location fix and a README audit.

- **#149** (#260, #261) — **the deployed lichess bot (SquareFish) had been
  running two weeks of code nobody could see from this repo.** A branch on
  the VPS's disk — never merged — had added in-game decision commentary as a
  144-line duplicate of the bot's actual move-choice function, untested, with
  nothing to notice if the two diverged. That feature is now one function
  plus a callback, merged to `develop`, and measured behaviour-neutral
  against the previous build (a straight move-by-move diff can't be used
  here, since a single build differs from itself on ~28% of individual
  decisions thanks to unseeded weighted picks — so it was checked by
  distribution instead). Spectators now get their own greeting and
  commentary, having previously heard nothing at all, and the bot's whole
  configuration — the token aside — moved from a VPS-only file into the repo
  as overrides merged onto lichess-bot's own defaults.
- **deploy follow-ups** (#262) — landing the above on the actual VPS surfaced
  four more bugs, found by the deploy visibly breaking: regenerating the
  bot's config wiped hand-edits, including an option the engine doesn't
  support, which crash-looped the service for about two minutes; a spectator
  greeting silently never arrived because the length guard measured the
  unsubstituted template rather than the real message and so passed the
  exact string it existed to catch; a timeout setting reverted to its
  default, aborting a rated game whenever a human paused to look at the
  board; and the chat relay to lichess turned out to be an uncommitted patch
  to lichess-bot's own third-party checkout, which any `git pull` there would
  have silently deleted — it's now a vendored, checked-in patch the setup
  script applies.
- **#255** — **on macOS, the games database was being written into the
  user's real `~/Documents` folder**, not a private container — a side
  effect of dropping Apple's app sandbox to run player-supplied UCI engines
  (#183). The database now lives in Application Support on macOS
  (iOS/Android/web are untouched — Documents is correct for a sandboxed app
  there), migrated by rename only when nothing already exists at the new
  location. A pre-merge review caught the first version of this migration
  renaming the database before its `-wal`/`-journal` sidecars — a failure
  partway through could strand a database apart from the journal it needed,
  which on macOS reads as full corruption, not just lost transactions —
  fixed before it reached `main` by opening and cleanly closing the database
  first, so SQLite settles its own sidecar and only a single-file rename
  remains.
- **#256** — the vendored web-database worker (`sqflite_sw.js`) now records
  which package version produced it, checked in CI against `pubspec.lock`, so
  a routine dependency upgrade can't silently move the client library out of
  sync with a frozen worker.
- **#150** — **the README was audited claim by claim against the code.**
  Caught, among others: the privacy section said you "pick a Maia" to
  download it, when the macOS and iOS apps actually prefetch all three Maia
  bands (~10.5MB) unasked at first launch — web is genuinely opt-in — and a
  claimed "three-fact" board-overlay rule that doesn't exist in this
  codebase, a holdover from the retired Svelte app. Screenshots are now
  produced by a Playwright capture script rather than taken by hand, driving
  a fresh bot-vs-bot game and a seeded practice item so no real user data
  ends up in a committed image.
- **docs consistency** — three docs said the bundled Stockfish is version 16,
  an old comment left behind by a package upgrade — it's 18. `ARCHITECTURE.md`
  didn't mention the ChessGPT persona family at all, and `ROADMAP.md` still
  claimed native and web offered the same 32 personas; both now state 38
  defined, 35 playable, 32 on the web.

## 2026-07-30 — the web database gets a single writer, and a broken one gets a way out

- **#252** (#253) — **"database disk image is malformed" was one sqlite3
  instance per browser tab, racing over the same file.** Two tabs — or the
  installed PWA plus a tab — each ran their own sqlite3 with no locking
  between them; fixed by routing every tab through one shared-worker sqlite3
  instance instead. On Android Chrome before milestone 148 and Samsung
  Internet, the shared-worker path falls back to one dedicated worker per
  tab — still better than the old design, just not the same single-writer
  guarantee.
- **#254** — **a corrupt local database is no longer a dead end.** Boot used
  to render an unselectable "boot failed" wall with no reset anywhere in the
  app; now a failed check reaches a screen that explains what happened and
  offers to move the database aside (renamed on native, so the original file
  isn't destroyed; deleted on web, where there's nowhere to rename to). A
  same-day follow-up found the original corruption probe caught only a small
  fraction of realistic damage; a full-table scan now catches every case
  found to actually break the app, at no real cost since the app already
  reads the whole archive at boot. Deliberately a button the player presses,
  not an automated policy: an earlier automatic-recovery design was pulled
  from this same release before it reached `main`, because it would have
  deleted data that was mostly salvageable — deferred rather than shipped
  half-right.
- **#259** — **the "Start fresh" reset button looked like it worked and did
  nothing.** The corruption check left the corrupt file open when it threw,
  so the reset then tried to delete a file it was still holding open — and
  Flutter's own database-delete call silently swallows its own failure, so a
  delete that did nothing returned normally and the app believed it. The
  reset now verifies the file is actually gone and says so honestly when it
  isn't, pointing at "clear site data" as the manual fallback on web.
- **#247** — **the three retro artefacts (wasm, macOS binaries, iOS archive)
  are now rebuilt from a morlock revision recorded in the repo**, instead of
  a gitignored local checkout nothing could verify — a committed revision
  pin, a sync script that checks it out and refuses on a dirty tree, and CI
  that compares the pin against what the shipped artefacts actually contain.
  Found while rebuilding: on Intel Macs the app is built universal but staged
  arm64-only engine binaries, and the "is this engine available" check asked
  only whether the file existed rather than whether it could run — so an
  Intel Mac was offered all three retro bots and every game quietly played
  Stockfish under a retro bot's name.
- **#244** — **retro bots are now sent the whole game, not just the current
  position.** A board rebuilt from a bare FEN has no move history, and
  SARGON's development-scoring term and TUROCHAMP's quiescence search both
  read that history — every SARGON game was scoring every knight and bishop
  as permanently undeveloped. The calibration gym that produced the roster's
  advertised ratings had always sent the full move list, so this brings the
  app in line with what was actually measured. A same-day review caught a
  regression this introduced: castling by dragging the king onto its own
  rook (a legal alternate UCI spelling) now reached the wire and killed the
  retro engine outright — closed with a spelling conversion before the move
  is sent.
- **#258** — **you can delete your synced data from the server.** There are
  no accounts; the encrypted blob's ID is derived from your pairing phrase,
  so the device holding that phrase is the only thing that could ever have
  added this. Two separate buttons deliberately: turning off sync keeps your
  uploaded blob, deleting the blob keeps your local games. Sync auto-recreates
  a missing blob on its next run, so deleting also disables sync on that
  device, or the delete would silently undo itself within a minute.

## 2026-07-29 — refuse-blunders stops comparing two different searches

Four deploys in one day, most of the work downstream of one root cause: two
evals subtracted from two different searches.

- **#242** (#243) — **refuse-blunders could refuse a move the engine's own
  analysis called best.** The refusal drop was a subtraction of two evals
  from two different searches — a deep pre-move analysis for the "best"
  side, a shallow post-move check for the "played" side — so shallow-vs-deep
  noise got charged to the player; a move that forced mate in 12 was refused
  as a blunder because the shallow check couldn't see that far. Fixed by
  scoring a move already in the pre-move lines off those lines alone, with an
  explicit guard that the engine's own top move can never be refused. One
  layer under that: a "streamed" engine-line snapshot could fire on the first
  line of a new, deeper search while every other line in the same snapshot
  still held the previous depth, so a subtraction across two lines of the
  "same" snapshot could still mix searches — fixed by streaming a snapshot
  only once every line agrees on depth. The same pass also stopped the
  refusal check from running a redundant search whose answer nothing read,
  made a rematch keep your blunder-protection setting instead of silently
  dropping it, and logged to the console why a move was allowed rather than
  looking identical to simply approving it.
- **#245** — **a retro bot (TUROCHAMP, BERNSTEIN, SARGON) silently handed its
  game to a Stockfish stand-in from the second game onward.** morlock's UCI
  driver ends its session the moment it gets a `position` line identical to
  the previous one, which starting a second game against the same bot does
  exactly — and the death was silent inside a Web Worker, so the client
  waited out its timeout and a Stockfish stand-in played the rest of the game
  under the retro bot's name. Fixed by sending `ucinewgame` before every
  position, on all three transports (web, macOS, iOS), plus a net for other
  ways the driver can die: an unparseable Chess960 castling FEN is now
  refused with a reason instead of killing the engine, and a race where a
  superseded search's stale answer could land on a new position is closed.
- **#246** — **a release no longer evicts the vendored engines from the
  browser cache.** The cache name used to hash over the whole app bundle, so
  every deploy threw away Stockfish, Maia's ONNX runtime and the retro wasm
  even when none of them changed — the first retro or Maia move after a
  release paid for a multi-megabyte re-download, racing that move's own
  patience. Vendored assets now live in a separately-named cache keyed per
  file by content hash, so only a changed file is re-fetched; the app's own
  bundle deliberately stays on the cache that still rotates on every deploy,
  since a stale build beside a new one refuses to boot.
- **#249** — **practice no longer collects a puzzle whose answer is the move
  you played.** Found by auditing a real production queue: one item asked
  the player to correct a move with that same move stored as the answer — a
  puzzle that passes automatically, since the drill treats "played move
  equals stored best move" as a pass. Same underlying cause as the rest of
  the week's work; the guard now sits where puzzles are built, so it covers
  the refusal path and lichess import too.

## 2026-07-28 — the practice bar moves, retro's phone bug, and a backlog sweep

Two live defects, a process fix, and a cluster of small Practice/Review
polish that had been queued up.

- **#213** — **the practice win-chance filter and the refuse-blunders
  threshold used to be the same setting**, changed from a Settings control
  that never mentioned rated games — so lowering your practice bar also
  silently loosened what counted as a refusable blunder mid-game. They're now
  two persisted settings, and the practice-bar control itself moves out of
  Settings into a popup on the Practice tab, showing the live count of
  puzzles under the current bar.
- **#241** — **a retro bot could stand in as a Stockfish substitute for an
  entire game on the phone.** The wasm engine's preload was keyed on "the
  persona to move", which is null on the player's own turn — so in the
  ordinary seating (human White, bot Black) nothing preloaded until the
  bot's first turn, dumping a multi-megabyte download into a single move's
  patience budget, and one slow move that timed out latched the engine dead
  for the rest of the game. Fixed by preloading from whichever seat holds
  the persona and separating the per-move timeout from a longer overall boot
  deadline.
- **#214** — **Practice's advance button no longer throws an unattempted
  puzzle away.** The primary button is now a ladder — hint, another hint,
  show best, then next — so nothing advances until an answer is actually on
  screen; a plain-text skip survives, deliberately demoted, for "not this
  one, not now."
- **#95** — **the Lines pane now shows analysis progress as "depth 14 / 22"
  under a fill bar**, instead of a bare depth number nobody had a way to
  judge. A search that stops early is marked "final" rather than left
  looking like a stalled download frozen partway.
- **#239** — **Review's move list is usable in phone landscape now** — a
  wide-but-short viewport used to leave it unreadably thin. Landscape now
  lays the board beside the list instead of stacking, using an actual
  width-vs-height check rather than lowering the existing width-only
  breakpoint, which would have broken the portrait phones that breakpoint is
  tuned for.
- **#234** — **the clock now pauses while a rated game isn't the active
  window** — another app, a locked phone, a backgrounded tab all pause and
  resume automatically. Decided deliberately in the "pause generously"
  direction: there's no opponent to wrong, and time already spent still
  counts, so backgrounding can't rescue a game that was already lost on the
  clock.

## 2026-07-27 — blind mode on the analysis board, and ChessGPT

- **#148** — **"is this board hiding help" now has one answer instead of
  three.** Blind mode used to be gated differently by the Book/Lines panes,
  the Tree pane, and the board overlays, so turning blind on at the analysis
  board blanked the board while the Lines pane beside it kept listing engine
  evaluations. One predicate now covers all of them, and blind mode becomes
  usable on the analysis board as a self-testing tool — guess the move
  before the engine tells you — rather than only an opponent-facing secrecy
  switch. A related bug fixed alongside: starting a rated game force-suppresses
  arrows, threats and square control as part of the rated preset, and nothing
  recorded what your settings were beforehand, so those switches could stay
  stuck off app-wide after the game ended; the snapshot-and-restore is now
  persisted, so killing the app mid-rated-game doesn't strand it either.
- **#235** — **ChessGPT: a new bot family with no search at all** — a
  language model (Adam Karvonen's nanoGPT, trained on Lichess PGN) run
  through the same ORT runtime the app already ships for Maia, so its
  mistakes are its own rather than a dialled-down Stockfish's. Three
  variants ship, native-only, downloaded on demand with no prefetch —
  trained on human games, on Stockfish self-play, and on both. They land
  within about 80 Elo of each other on the project's own gym but diverge
  sharply in error rate: the Stockfish-trained net is both the strongest and
  the most error-prone of the three, and beats the human-trained net
  head-to-head. Weights were previously blocked on licensing; Karvonen set
  them to MIT on request and the nets are now published with pinned
  checksums. Built on the custom-UCI-engine seam from #183, which otherwise
  remains open as a general feature. Note: the project's first published
  strength figures for these nets were retracted — a harness bug fed the
  model a bare FEN it can't parse (it needs move history) and miscounted the
  resulting null moves as draws; the table above ships from the corrected
  harness.

## 2026-07-27 — Review shows the best move as a board, and what a four-way review caught

A fresh four-way adversarial review of the ChessGPT/blind-mode branch — after
it had already shipped — found three real production bugs that had escaped
review the first time.

- **#233** — **Review's verdict strip now shows the best move as a
  mini-board** (played move in red, engine's move in green, one blue arrow
  when they match) instead of a plain "best: Nf3" sentence, the same
  comparison widget Insights has used since #185.
- **#231** — **refusing a blunder in a rated game used to be completely
  silent.** There's no insight card on that screen, so a rejected move just
  snapped back with nothing explaining why. A transient message strip now
  says a move was refused and how many tries remain, without saying what was
  wrong with it — blind mode there is deliberate, and the message doesn't
  undercut it.
- Three bugs the review found, already live in production from the prior
  release: a capability check had collapsed two engines onto one flag,
  silently dropping **both** Maia and ChessGPT from the entire web roster
  (true on macOS, false on CI's Ubuntu box, so nothing caught it); ChessGPT
  could hang the board solid past move ~93 from a context-length overflow
  that escaped its own error handling; and refusal mode (#167) could eat a
  human's move outright if the engine died mid-check, because the refusal
  path was missing the `catch` its sibling method has carried since it was
  written. Filed alongside but fixed the same day (#238, below): a flag
  falling mid-move could archive a rated game one move short of the board.
- **CI now runs the Dart test suite in a real browser**, not just on the
  host VM plus compile-only web builds — exactly the gap that let the
  roster-flag bug above ship undetected.
- **#158** — the hand-rolled browser save/export path gets its first
  behavioural test, via Playwright driving the app's accessibility semantics
  tree rather than a widget harness — a technique the repo had twice
  concluded was impossible for Flutter web. The board itself is still out of
  that tool's reach (painted pixels, no semantics), so game-state testing
  still goes through the pure-Dart harness.
- **#238** — **a flag falling mid-move could archive a rated game one move
  short of the board.** Pressing the clock — which can synchronously trigger
  flag-fall and archive the game — happened *before* the move was applied,
  so a game that ended on time showed one fewer move than was actually on
  the board, and got rated on a position that never happened. Fixed by
  playing the move first and pressing the clock after.

## 2026-07-26 — rematch, insight arrows, and two CI/offline guards

Four independent fixes, built in parallel and shipped together.

- **#212** — **a Rematch button on the game-over screen** starts a fresh
  game against the same opponent with colours swapped and the time control
  carried forward. Only offered when there's an actual opponent — not on the
  analysis board, where both sides are already human. The per-attempt
  "refuse blunders" toggle deliberately doesn't carry over, since it's a
  practice setting rather than a property of the match.
- **#185** — **the Insights mini-board now draws even when you played the
  best move**, with the played move in red and the engine's in green,
  collapsing to a single blue arrow when they're the same move.
- **#159** — CI now dry-runs a WebAssembly build, so the claim that a
  particular file exists specifically to keep the app buildable to wasm is
  actually checked instead of merely asserted in a comment. Nothing ships as
  wasm yet; this keeps the option open without exercising it.
- **#177** — the offline chess.com importer script no longer wedges an
  entire month's archive on one shape-drifted game — a guard skips a record
  missing expected fields instead of throwing, mirroring an in-app fix
  already shipped for the same bug.

## 2026-07-25 — refuse-blunders practice mode

- **#167** — **a per-game "Refuse blunders" toggle rejects a move that loses
  too much win-chance before it commits, and makes you try again on the
  spot** instead of only grading it afterward. The board holds the piece
  while grading runs (capped at 2.5s, failing open if the engine is slow),
  then either commits the move or snaps it back with "try again (N left)";
  three refusals at one position let the next attempt through regardless. A
  refused move is still collected as a practice puzzle even though it was
  never actually played, and refusals are excluded from the Elo fit the same
  way a takeback is.

## 2026-07-25 — Review becomes the analysis board

- **#194** — **Review is no longer a static picture of a finished game —
  it's the same board widget the live game uses**, so square tinting, engine
  arrows, and the threat/win rings all come for free instead of being
  reimplemented. The old stored "you should have played this instead" arrow
  is gone; the live engine's own top-line arrow, drawn on the position after
  the move, replaces it. Review is deliberately cut loose from live-game
  settings — bot colour, blind mode — so a finished archived game can't leak
  state from whatever game happens to be live.
- **#196** — **playing a move in Review now branches into a variation
  instead of being refused**, navigated by path rather than by ply number:
  stepping back and then forward returns you to the line you were reading,
  but once you've retreated past a branch point, forward follows what was
  actually played. Variations print indented under the move they leave from;
  a branch reads "not played" with a "Back to the game" button, since an
  unplayed move was never graded.

## 2026-07-24 — Maia-3 moves-by-rating chart

A new "Humans" analysis panel, graduating the app from three fixed Maia-1
strength bands to one ELO-conditioned model, and using it to answer a
question Insights and the engine lines don't: is your move normal for your
level?

- **#221** — **a chart plots how often real players at every rating from 600
  to 2600 would play each candidate move**, powered by Maia-3's policy head
  in a single batched forward pass across the whole rating ladder. A
  hover/drag scrubber pins to the nearest rung and highlights its top move;
  a Now/Played toggle switches between curves for the live position and
  curves for the position before the move you actually played, with that
  move pinned on the chart. Reaches desktop browsers, iPad Safari, and
  native iOS/macOS/Android — iPhone Safari/PWA is excluded by the same WASM
  memory ceiling that already blocks Maia-1 there.

## 2026-07-23 — practice from your own games, deeper Insights

A practice-focused batch: drill the mistakes from a game you just reviewed, keep
playing a line past a puzzle you solved, and read the "why" on the Insights card.

- **#197** — **practise this game's own mistakes from Review.** A game's blunder
  positions are already collected as you play; the Review screen now scopes a
  practice session to just that game's positions and jumps you to the drill. The
  session is finite — it walks each mistake once and ends with the way back to
  the full queue (an earlier build looped forever, or re-served a lone mistake
  endlessly; fixed).
- **#143 (part 2)** — **"continue the line" from a passed puzzle.** After you
  find the strong move, the engine answers and the position one move later is
  served as a fresh target, so a one-move puzzle becomes a drill of the line it
  came from. Off a pass only; line continuations don't touch the schedule.
- **#123** — the **Insights card states the practice verdict** (whether the move
  was collected, and why) and **speaks the concrete threat** in words, not just
  an arrow.
- **#147** — blind mode no longer leaks hidden scores through a layout gap.

## 2026-07-23 — review mode, ratings, and a backlog sweep

A batch of finished-but-unmerged work plus two waves of small fixes.

- **#202** — **review mode: a win-chance chart, reachable from game-over**
  (#195, #198). The curve draws over a finished game in Review — one dot per
  graded ply, coloured by its label, fed from each game's stored evals through
  the brain's own `whitePovWinChance` so it matches the line the live chart
  drew. The ply you're on is ringed, tapping a point seeks the board there, and
  the game-over recap gains a "Review this game" button.
- **#201** — **downloaded/custom-engine games now count toward the player
  rating**, with a gym seam; and the bot picker's Elo-cap sliders snap to whole
  hundreds and clamp to each engine's real `UCI_Elo` range.
- **#164** — the Insights card gets **two play buttons** — "Best line" and "Your
  move" — instead of one control that silently meant either.
- **#143** — practice **"ease in" is a setting** now, not hardcoded: a switch in
  Settings → Practice picks easy-first warm-up vs strict due-order.
- **#144** — the won-clean **crowns gain their footer legend** (solid = clean
  win; outline = won with help).
- **Housekeeping:** #118 (ROADMAP testing docs rewritten), #120 (the maia3 spike
  removed from the typecheck), and #133 / #155 / #200 (regression tests and
  verification for the opponent-change reset, the stale practice verdict, and
  rated-undo enforcement — all already fixed, now locked in or confirmed).

## 2026-07-23 — private cross-device sync

- **#203** — **end-to-end-encrypted cross-device sync** (#210). The game archive
  and practice collection now sync across web/macOS/iOS with no account and no
  server that can read them — a device joins by entering the same phrase. The
  phrase becomes keys by PBKDF2-HMAC-SHA256 → HKDF (PBKDF2 not Argon2id: dart2js
  Argon2id benchmarked at 31s, so a WebCrypto primitive was the only viable KDF
  across web and native); the blob is AES-256-GCM in a self-describing,
  AAD-bound envelope, gzipped. The `blobId` is derived from the phrase too, so
  the server can't even enumerate blobs. Transport is a dumb Cloudflare R2 store
  behind a small Worker (`worker/`) with compare-and-swap over HTTP-native
  conditional PUT and a per-IP rate limit. The merge is `BackupService`'s
  convergent one (#138), so sync is transport + apply-on-read rather than a
  distributed-systems problem — proven by a two-device convergence test. Turn it
  on in Settings → Sync; it then syncs on launch, resume, after a game, while
  you practise, and on leaving. Phrases are NFC-normalized so an NFD and NFC form
  derive one key. Reviewed by four adversarial subagents — six findings fixed and
  independently verified.

- **engine orphan guard** (#210) — a UCI engine subprocess no longer outlives
  the app. `dispose()` only covered a clean exit; a force-quit, hot-restart, or
  crash left the child reparented to launchd and, if mid-search, burning a core
  (an orphaned velvet was found at 100% for 23h). Now killed on SIGINT/SIGTERM
  and app-detach, with a boot-time sweep reaping whatever a crash still leaked.
  Desktop only.

## 2026-07-21 — the Squares play at their labels again

The only change this month that alters how the app *plays*.

- **#113** — **native Squares were using the web's calibration table** (#104).
  The brain keeps two, because a persona label means different things
  depending on the engine underneath it; it defaults to `wasm`, and the only
  thing that ever flipped it was the Tauri shell, which is gone. So on macOS
  and iOS twelve of thirty-two personas mapped their labels through the WASM
  table while playing Stockfish 18 over FFI or a spawned process. Measured
  against the fresh native curve, **every Square was playing 17-150 points
  below its label**, 91 on average. The fix is one line at boot; each Square
  now picks a label 18-135 points higher and searches up to 2 ply deeper.

  The old in-source note guessed the opposite — "desktop Squares will play
  above label" — because it described the stale table rather than what the app
  was doing with it.

- **#110** — **the native grid, remeasured** (#70), against the Stockfish 18
  the macOS app actually bundles, n=100/pair on the same grid as the live wasm
  run. Every knot moved up, as the saturated-loss fix predicts. The more
  interesting result is that the substrates **re-converged**: the mean gap to
  wasm fell from ~200 to ~93, restoring the older finding that the choice layer
  dominates so completely that backbone quality barely moves strength — and
  reframing the large gap as evidence of a stale table rather than a real
  difference between engines.

  iOS needs no separate grid: `package:stockfish` vendors the same Stockfish 18
  with the same two nets, and the shaped search is depth-bounded, so it visits
  identical nodes on any hardware.

- **#111, #112** — 25 files of Gradle build cache, swept into #110 by
  `git add -A` and removed again. An Android scaffold on a spike branch carries
  its own `.gitignore`; checking out a branch without it deletes the rules
  while leaving the untracked cache on disk. `.gradle/` and `flutter/android/`
  are now ignored at the root, where it holds on any branch.

- Decision recorded: **Linux and Windows are the PWA**, not a native build.
  `flutter_js` gives JavaScriptCore only to iOS and macOS; Windows, Linux and
  Android all get a QuickJS with no BigInt, so `brain.js` does not parse and
  the app does not boot. Android has a route out (#109, confirmed on a real
  emulator); Linux and Windows would mean shipping our own JavaScriptCore,
  against a web app that already offers the full roster there offline.

## 2026-07-21 — one app

The SvelteKit app the project began as is gone, and the last two open
questions before an App Store attempt got answered rather than deferred.

- **#106** — **the Svelte app and the Tauri shell retired.** They shipped
  botvinnik.app until 2026-07-19 and were frozen the same day; keeping them
  cost a second implementation of every feature, fix and review for an app
  with no users. Preserved whole at the annotated tag `svelte-eol`.
  `static/{wasm,retro,garbo}` became `vendor/` — they are third-party engine
  builds the *Flutter* web build stages, and were only ever called "static"
  because SvelteKit named the directory. `lichessImport.ts` and
  `chesscomCore.ts` were rescued into `brain/`, where the offline harness
  still needs them.

  The load-bearing part was the type-checker. `npm run check` was
  `svelte-check`, whose include list came from `.svelte-kit/tsconfig.json` —
  so it reached `brain/` only through the Svelte files importing it, and never
  reached `scripts/` at all. Replacing it with a plain `tsc` surfaced 19
  pre-existing errors, one of which was that the **live lichess bot's UCI
  wrapper still imported a path deleted in the #26 restructure**. It could not
  have run from a current checkout; only the VPS's older copy kept SquareFish
  alive, and it would have broken on the next pull.

- **#103** — **notarization layout** (#67, structurally): the bundled engines
  move to `Contents/MacOS` and are signed with the app's identity in the same
  build phase. Executable code in `Contents/Resources` is a rejection, because
  the hardened runtime treats Resources as data. What remains is a Developer
  ID certificate, which is a purchase rather than a change.

- **#102** — **Android answered** (#46): it needs JavaScriptCore, not QuickJS.
  The BigInt in `brain.js` is **chess.js's**, from its Zobrist hashing — not
  js-chess-engine's as the issue assumed — so nothing can be dropped to avoid
  it, and the QuickJS `flutter_js` ships for Android has no BigInt at all
  (verified against its atom table, and by an A/B of the same QuickJS built
  with and without `CONFIG_BIGNUM`). Both bundles fail to *parse* there.

- **#105** — the architecture diagram still drew Svelte deploying the site.

- Issue hygiene: five shipped issues were closed (#51, #59, #60, #74, #85),
  four of them open only because a PR named them in its title without a
  closing keyword in the body. #74 had been live on lichess four days before
  it was filed. Thirteen more were corrected where their premises had gone
  stale, and **#104** was filed for something no issue described: native
  Squares map their labels through the WASM calibration table while playing a
  different engine, because `setBotSubstrate` is never called from Flutter.

## 2026-07-20 — the native roster closes

macOS and iOS now offer the same **32 personas** the web does. Every remaining
engine crossed in a different way, and none of them the way its stub predicted.

- **#96** — **Maia native** (#44): `package:onnxruntime` replaces ort-web (ORT's
  C API over `dart:ffi`, its isolate session keeping the forward pass off the
  UI thread), `HttpClient` and Application Support replace fetch and IndexedDB.
  The chess did not move: `assets/maia-brain.js` runs the same `brain/maia/`
  encode/decode in an embedded JavaScriptCore, so a move is encode-in-JS →
  infer-in-Dart → decode-in-JS. A second bundle rather than two more exports on
  `brain.js`, which is a script tag on the web and would have carried lc0's
  1858-string policy index to every visitor. Verified against the move the WEB
  plays, three bands across four positions. Brought two things with it: the
  macOS bundle's first outbound socket (`com.apple.security.network.client`),
  and the discovery that nothing type-checked the Flutter app's own TypeScript.
- **#97** — **retro on iOS** (#80): iOS has no child processes, so the same
  morlock source builds with `-buildmode=c-archive` and is driven over
  `dart:ffi`. Three transports now share one `build()` switch, so the
  calibration means the same thing on all of them. The boundary has two
  subtleties that only show up at runtime: a `NativeCallable.listener` runs
  *after* the call returns, so Go hands over a `malloc`'d line and Dart frees
  it; and Go's `emit` takes the same lock as `retro_stop`, so teardown cannot
  race a callback. And two the linker finds: `-force_load` (nothing references
  symbols resolved at runtime, so they get stripped) and `[sdk=…]`-conditional
  paths rather than an xcframework (both slices are arm64).
- **#98** — **Garbo native** (#43): the last web-only family, and the cheapest,
  because replacing a Worker does not mean writing a message loop —
  garbochess's search is one long *synchronous* call, so everything it emits is
  buffered by the time the call returns. Four lines of shim and a background
  isolate, which is what keeps a ~1s search off the UI thread. `Isolate.kill`
  turned out to reclaim the Dart heap and nothing else: the JavaScriptCore
  context is native memory only the child can free, measured at ~167MB per
  disposed engine, so teardown asks rather than kills.
- **#99** — a **crash**: disposing a retro engine mid-search aborted the app.
  Ending a session sent `quit`, and morlock handles that by returning from its
  driver loop without clearing the active-search flag — so a search still
  finishing sends its bestmove on a closed channel. In a Worker or a child
  process that is an invisible engine death; in a `c-archive` it is SIGABRT in
  the app's own process. Reachable by switching bots mid-think.
- Fixes found by review along the way: nothing in CI ever *executed* the Maia
  bundle (a source edit decoding the policy from the wrong side merged green —
  there is a golden fixture and a smoke test now), an ORT run that outlived its
  timeout could hand the next position the previous one's policy, and the
  **web** Garbo client could answer with the previous position's move.

Only Dala (#45) is desktop-only, in both apps, as it always was.

## 2026-07-20 — the UI backlog, and a harness to hold it

The Flutter UI backlog cleared, plus the first tests that reach the state
machine those bugs kept turning up in.

- **#93** — a wide-window **menu bar** (#63): Game (new game, import PGN),
  View (the panel toggles in view-bar order, flip, blind mode), Help. In-app
  rather than a native `PlatformMenuBar`, because the wide layout runs on the
  web too, where that does not exist. The app bar drops its keyboard icon
  while the menu is up rather than offer the same thing twice.
- **#92** — **PGN import** (#48): paste a game, it is archived and opens in
  Review. The parse is a pure function, which is why it is directly testable;
  an import carries no grades and Review already read every one of those as
  nullable. An import also has no *you* in it, so it shows the PGN's players
  instead of Won/Lost and opens from White's side. Plus **per-panel collapse**
  (#63) — folding a panel to its header, which is not the same as closing it.
- **#91** — the **threat line** is playable (#86): the chip gets its own play
  button that runs the line the threat was judged on. Deliberately the judged
  window, not the engine's raw pv — `gain` is counted over the settled
  exchange, so replaying further would show captures the number never
  credited. `judgeTacticalWin` gained the same field for the green mirror.
- **#90** — a pure-Dart **GameController test harness** (fake engine deps, no
  browser, no device), and with it the botThinking clobber (#87) and the
  practice-collect guard pinned as regressions. Each was verified RED against
  its own pre-fix code first.
- **#88** — **FEN input** (#85): start from a pasted position, which doubles as
  the way to reproduce a reported board state instead of playing into it.
  **Panel reorder** (#59), and **tab-aware keyboard shortcuts** (#60) — blind
  mode in Play, `r`/`n`/`b`/`?` in Practice, arrows in Review, with the help
  sheet grouped by tab from one source.
- Fixes: practice no longer collects puzzles on the analysis board (that is
  exploration, not blunders to drill); undo and browse-to-start return to the
  FEN a game began from rather than the standard start; a new game during a
  bot's turn no longer clobbers the fresh turn's state; the frozen Svelte
  MaterialBar valued a rook at 3.
- Process: `main ← develop ← PRs`, so work lands on `develop` and only a
  release deploys.

## 2026-07-20 — App Store prep, native retro on macOS, and the board's second pass

Everything after the deploy: getting the native app submittable, and a second
pass over the play surface.

- **#84** — board player plates (name + captured material, above and below) and
  a bot-vs-bot move-delay setting. The same pass reworked the play surface: the
  plates reserve their height so the column never scrolls; a light tray so the
  black captures read on the dark ground; a **NavigationRail** on wide windows,
  handing the bottom bar's height to a board that is height-bound in the split
  view; and the under-board **grade strip removed** — its verdict already lived
  in the Insights card, so the threat (now a chip) and the Maia loading bar
  moved there and the board reclaimed the ~66px. Follow-ups filed: #85 (FEN
  input), #86 (full threat line).
- **#83** — new-game flow: choose a player per side (you or any bot), which
  yields bot-vs-bot for free; Practice only collects when it is your move;
  opponent selection moved out of the app-bar title into the New Game sheet.
- **#82** — App Store code-side prep: the encryption-exemption flag and the
  `PrivacyInfo.xcprivacy` manifests wired into the macOS/iOS bundles, plus the
  submission docs.
- **#81** — in-app source link and licence text for GPL-3.0 compliance on the
  App Store (the Lichess posture, decided in #76).
- **#79** — native retro on macOS: the three morlock engines build to UCI
  binaries, bundled in the app and spawned with `Process.start` (sandbox-safe
  only from inside the bundle). iOS is the harder half, split to #80.
- **#78** — Review opens at the start of a game, not the end (#61).
- Housekeeping (late 2026-07-19): the 945-line `ROADMAP.md` migrated to GitHub
  issues and trimmed to an index of design invariants, with this CHANGELOG
  split out; third-party notices completed (retro/morlock MIT, Garbo BSD-3,
  Go `wasm_exec.js` BSD-3, Maia/Dala weights GPL-3.0).

## 2026-07-19 — the roster closes and Flutter takes the deploy

Flutter web reached **parity** (32 of 35 personas; Dala needs a native lc0
sidecar and is desktop-only in both apps) and took the botvinnik.app apex from
the frozen Svelte app.

- **#41** — Maia download shows real streamed progress. The old "downloading"
  line lived in `statusLine`, which only renders when the game is over, so it
  was never once shown — the actual reason the first Maia move looked like a
  hang. Now a live bar in the grade strip: streamed `{received, total}` while
  the weights arrive, a named indeterminate phase while the runtime compiles.
- **#40** — the phone board takes the full width. It was height-capped by a
  96px reserve meant to keep some panel on screen — worth it on a desktop
  window, 13% of the board on a phone that has the height to spare. Now
  width-conditional; Review had the same defect and got the same fix.
- **#39** — deploy switch. `pages.yml` builds and ships `flutter/`. The
  load-bearing piece is a tombstone at the Svelte worker's path
  (`flutter/web/service-worker.js`): SvelteKit's worker is cache-first for the
  shell, so without it a returning browser serves cached Svelte forever and the
  new app never loads. Verified by simulating the deploy on one origin.
- **#38** — Maia on Flutter web. Six personas, three ONNX nets, one Worker.
  The pure encoding/decoding moved to `brain/maia/` and is now shared by both
  apps. Nothing about Maia lands in git (built at stage time; runtime from the
  pinned `onnxruntime-web`). The app's only third-party request, and only on
  first use of a Maia.
- **#37** — Garbo (Gary Linscott's 2011 hand-written JS engine) on Flutter
  web, and the three Worker clients folded onto one `js_worker.dart` interop.
- **#36** — retro bots (TUROCHAMP 1948, BERNSTEIN 1957, SARGON 1978) on
  Flutter web, as wasm in their own Worker. The Flutter app's first browser
  tests (`flutter/e2e/`).
- **#35** — Flutter web is a real offline PWA: shell-only precache,
  cache-on-first-use, no third-party requests, content-hashed cache version.
- **#33** — Practice/Review wide-window layout, the analysis-budget change,
  and the **Svelte freeze** (see `svelte/FROZEN.md`).
- **#32** — Horizon (js-chess-engine) plays on Flutter, the first roster
  family to cross the synchronous brain bridge (20 → 22 personas).
- **#31** — `ARCHITECTURE.md` added; ROADMAP brought current.
- **#30** — stop shipping Maia weights and the commentary corpus to every
  visitor; entry chunk 188KB → 82KB gz.
- **#29** — wide-window UX and the board-overlay grammar (threat/win rings,
  control wash, the three-fact rule).

## 2026-07-18 — the platform split

- **#28** — GPL-3.0 license and third-party notices.
- **#27** — wide-window panels and the Lines pane.
- **#26** — repo layout: `brain/`, `svelte/`, `flutter/` as peers, with the
  brain consumed by both apps.
- **#24** — Flutter on the web: a dartchess fork splitting the 64-bit bitboard
  into 32-bit halves for the JS number path.
- **#23** — Flutter board theming, overlay controls, and a macOS build.

## 2026-07-17 — PWA, deploy, explanations

- **#22** — app icon (robot knight), PWA + desktop.
- **#21** — installable + offline PWA (manifest, service worker, icons).
- **#20** — deploy to botvinnik.app, dropping the `/botvinnik` base path.
- **#19** — move-explanation sprint: audit vs cook.py themes, mate-pattern /
  promotion / sacrifice detectors, absurd-claim fixes.

## 2026-07-11 — the Svelte app

- **#1** — the browser-only chess practice app: client-side Stockfish, the
  grading pipeline, practice and review, game storage, and (later parked) a
  Tauri desktop shell with a native engine and in-app importer.

Between #1 and #19, the Svelte app grew its sidebar redesign, game review UI,
bot-weakening research and the shaped choice-layer, and the persona roster and
its calibration against human-pool anchors — recorded in the pre-trim ROADMAP
(git history) and in the project memory notes.
