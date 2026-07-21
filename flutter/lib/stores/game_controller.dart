// The live game: position, bot reply loop, and the grading pipeline —
// the Dart translation of +page.svelte's orchestration, same semantics:
//
//   gradeMove(pre-move analysis lines) → backfillGrade(post-move analysis)
//
// One depth-22/3000ms MultiPV-5 analysis per reached position (the arbiter's
// `analysis` priority); the "pre" lines of a move are the "post" analysis of
// the previous one, cached by FEN. Bot searches run at `botMove` priority
// and preempt analysis, so replies stay snappy.

import 'dart:async';
import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../brain/bot_api.dart';
import '../brain/chess_api.dart';
import '../brain/grading_api.dart';
import '../brain/types.dart';
import '../db/app_db.dart';
import '../engine/arbiter.dart';
import '../engine/garbo_engine.dart';
import '../engine/maia_engine.dart';
import '../engine/maia_progress.dart';
import '../engine/retro_engine.dart';
import 'lines_tree_model.dart';
import 'practice_controller.dart';
import 'redo_stack.dart';
import 'chess_clock.dart';
import 'settings_store.dart';

/// How long archiving a finished game waits for in-flight grading.
///
/// Must stay comfortably ABOVE [kAnalysisMovetimeMs]: a grade pipeline awaits
/// the analysis of the position after its move, so the slowest grade cannot
/// land sooner than the slowest analysis. Set below it, and finishing a game
/// during a deep search would archive it without its closing labels — silently,
/// since the wait times out rather than failing.
const int kSaveGradeWaitSeconds = 16;

class MoveRecord {
  final int ply; // 1-based, like the web
  final String san;
  final String uci;
  final String color; // 'w' | 'b' — who moved
  final String fenBefore;
  final String fenAfter;
  MoveGrade? grade;

  MoveRecord({
    required this.ply,
    required this.san,
    required this.uci,
    required this.color,
    required this.fenBefore,
    required this.fenAfter,
  });
}

class GameController extends ChangeNotifier {
  final SearchArbiter _arbiter;
  final BotApi _bot;
  final GradingApi _grading;
  final SettingsStore _settings;
  final AppDb? _db;
  final PracticeController? _practice;
  ChessApi? _chess;

  Position position = Chess.initial;
  /// The position the game began from — the standard start, or a FEN handed to
  /// [newGame]. This is what ply 0 shows and what undoing the first move
  /// returns to; without it both fall back to the standard start on a game that
  /// started from a FEN.
  String _startFen = Chess.initial.fen;
  Move? lastMove;
  final List<MoveRecord> moves = [];
  bool botThinking = false;
  String gameSeed = _newSeed();
  bool _saved = false;

  // analysis cache: fen → future of its MultiPV-5 deep lines
  final Map<String, Future<List<EngineMove>?>> _analysis = {};
  // the deepest streamed snapshot per fen — grading falls back to these when
  // an analysis was cancelled because the board moved on
  final Map<String, List<EngineMove>> _partials = {};
  // grade pipelines still in flight — save waits for them (bounded)
  final Set<Future<void>> _pendingGrades = {};
  int _gen = 0;

  // at most one retro worker alive, matching the active persona
  RetroEngine? _retro;
  String? _retroKey;
  // garbo has a single configuration, so one lazy engine is enough
  GarboEngine? _garbo;
  // maia likewise: the worker holds one ort session per band, so a single
  // engine serves all six personas without reloading between them
  MaiaEngine? _maia;

  /// Non-null while a Maia move is waiting on its weights or on the runtime
  /// rather than on inference, with enough detail to show a real bar.
  ///
  /// Surfaced by the Insights card, NOT by [statusLine]. statusLine looks like the
  /// right home and is not: both of its call sites sit behind
  /// `if (game.gameOver)`, so nothing it returns is ever visible during a
  /// game. The download line lived there and was never once shown — which is
  /// exactly why the first Maia move looked like a hang.
  MaiaProgress? maiaProgress;

  /// At least one move this game came from the Stockfish stand-in rather than
  /// the persona's own engine — see the fallback at the end of [_pickBotMove].
  ///
  /// Sticky for the game, because that is the unit the fact applies to: one
  /// substituted move means the opponent you played was not the one on the
  /// card, and no later success un-plays it. Reset by [newGame].
  ///
  /// This is the only trace the substitution leaves. Nothing about the fallback
  /// fails — no crash, no error, no missing move — so without the flag the
  /// player, the saved game, and `estimatePlayerElo` all believe the persona
  /// played. `estimatePlayerElo` already drops games carrying `botFallback`
  /// ("opponent wasn't really the persona — off the ruler"); until this was
  /// recorded it never saw one. Issue #117.
  final Set<String> _standInPersonas = {};

  /// True when [personaId] was ever stood in for this game. The plate asks per
  /// side: in a bot-vs-bot game one persona can fail while the other plays
  /// itself, and a per-game bool put the chip on both — an accusation against
  /// the one that never failed.
  bool stoodInFor(String? personaId) =>
      personaId != null && _standInPersonas.contains(personaId);

  /// Any substitution at all this game — what the saved record stores, since
  /// `StoredGame.botFallback` is one boolean for the whole game.
  bool get botFallback => _standInPersonas.isNotEmpty;

  /// Takebacks the human used against the bot this game.
  ///
  /// The urgent half of the pair. `playerElo.ts` already drops any
  /// game carrying a takeback from the rating fit ("assisted result — off the
  /// ruler") — an assisted result is real practice but not a measurement — and
  /// until this was written it never saw one, so the drop was dead code and a
  /// rating would have counted games the player rewound. Issue #144.
  ///
  /// Counted in [undo], given back by [redo] (see there), reset by [newGame].
  int _botUndos = 0;
  int get botUndos => _botUndos;

  /// Whether the engine's hint overlays were on the board for any human move
  /// this game — the other half of the clean-win question.
  ///
  /// Sampled per move rather than read at save time: blind mode and the three
  /// overlay switches are all toggleable mid-game (they do not restart it —
  /// see [_settingsSig]), so what the switches say at mate is not what the
  /// player had while playing. Sticky for the game, like [botFallback]: help
  /// taken once cannot be untaken by switching the overlays off afterwards.
  bool _botHintsUsed = false;
  bool get botHintsUsed => _botHintsUsed;

  /// This game was started as a RATED game — the New Game sheet's mode that
  /// puts the result on the record: blind, hint overlays off, and the ordinary
  /// exclusions still apply on top.
  ///
  /// A recorded INTENT rather than something re-derived at save time from the
  /// four switches. Every one of those defaults to help ON (see
  /// SettingsStore.load), so "was this game unassisted?" answered from them
  /// rates no game a default install plays; and it re-decides what "assisted"
  /// means on every read. The argument in full is beside the exclusion in
  /// `brain/playerElo.ts`, which is the only thing that acts on this.
  ///
  /// Sticky for the game and reset by [newGame], and deliberately NOT cleared
  /// when a switch is flipped mid-game: turning arrows back on sets
  /// [_botHintsUsed], and that is what takes the game off the ruler. The
  /// record then states both true things — the player meant to be on the
  /// record, and then took help — rather than silently forgetting the intent.
  ///
  /// A takeback needs nothing here either: `botUndos > 0` already excludes,
  /// and it excludes for the same reason in a rated game as in a casual one.
  bool _rated = false;

  /// The clock, in a rated game that was given a time control. Null otherwise —
  /// a casual game has no clock, and a rated game without a chosen control is
  /// still a rated game.
  ///
  /// Owned here rather than by the screen because it has to survive a rebuild
  /// and because flag-fall is a RESULT, which only the controller can archive.
  ChessClock? _clock;
  ChessClock? get clock => _clock;

  /// The side that ran out of time, if one did. Like [_resigned], the position
  /// cannot express it.
  ClockSide? _flagged;
  bool get rated => _rated;

  /// What the board is drawing right now, from the player's side: the three
  /// engine overlays, with blind mode suppressing all of them. Kept in step
  /// with [engineArrowUcis], [threat] and [controlMap] — each gates on exactly
  /// this pair of conditions.
  /// Was the engine legible to the player on this move?
  ///
  /// Just `!blind`, and the overlay switches deliberately do NOT appear.
  /// `blind` already gates every one of them — engineArrowUcis, threat and
  /// controlMap each check it — AND the Lines pane, the Book and the tree,
  /// which show the engine's principal variations in text.
  ///
  /// It used to read `!blind && (any overlay switch)`, which is the predicate
  /// for the BOARD overlays, and the two are not the same set. With every
  /// overlay off — exactly what the rated preset does — that form was
  /// insensitive to blind: start a rated game, press `b`, read the best line
  /// off the Lines pane, play it by hand, and the record archived clean and
  /// counted toward the rating.
  ///
  /// Blind off does not prove the player LOOKED — they may have closed every
  /// panel. It proves the engine was available, which is the most that can
  /// honestly be claimed, and the conservative direction to be wrong in.
  bool get _assisted => !blind;

  GameController(this._arbiter, this._bot, this._grading, this._settings,
      [this._db, this._practice, ChessApi? chessApi]) {
    _chess = chessApi;
    if (chessApi != null) linesTree = LinesTreeModel(chessApi);
    _lastSettingsSig = _settingsSig(); // see the field: NOT a late initializer
    _syncRetro();
    _settings.addListener(_onSettings);
    _analysisFor(position.fen);
    _maybeBotTurn();
  }

  static String _newSeed() => 'm${Random().nextInt(1 << 30)}';

  String get playerColor => _settings.playerColor;
  bool get botEnabled => _settings.botEnabled;
  List<Persona> get rosterPersonas => _bot.personas();

  // Each side is a bot (a persona) or the human (null). The source of truth is
  // the settings; these resolve the ids to personas.
  Persona? get whitePersona => _personaOf(_settings.whitePersonaId);
  Persona? get blackPersona => _personaOf(_settings.blackPersonaId);
  Persona? _personaOf(String? id) => personaFor(id);

  /// Resolve a persona id — including one renamed since it was stored.
  ///
  /// Anything that turns a PERSISTED id into something a player sees must come
  /// through here rather than scanning [rosterPersonas]: archived games and
  /// saved opponents still carry pre-rename ids, and a raw scan misses them
  /// silently (the New Game sheet showed the literal "Bot", the picker
  /// highlighted nothing).
  ///
  /// Memoised because it crosses the JS bridge — the archive would otherwise
  /// make one call per row per rebuild.
  final Map<String, Persona?> _personaCache = {};
  Persona? personaFor(String? id) => id == null
      ? null
      : _personaCache.putIfAbsent(id, () => _bot.personaById(id));

  /// The persona of the side to move, or null if the human is on the move.
  Persona? get personaToMove =>
      position.turn == Side.white ? whitePersona : blackPersona;

  /// A representative persona for UI that wants one name (e.g. the Maia
  /// download line): the mover, else whichever side has a bot.
  Persona? get persona => personaToMove ?? whitePersona ?? blackPersona;

  /// True when the side to move is the human. Analysis (both human) is always
  /// the player's turn; bot-vs-bot never is.
  bool get isPlayerTurn => personaToMove == null;

  /// The bot plays both sides — nobody's move is the human's.
  bool get botBothSides => whitePersona != null && blackPersona != null;
  /// Whether the given side ('w'/'b') is played by the human.
  bool isHumanSide(String color) =>
      color == 'w' ? whitePersona == null : blackPersona == null;
  /// The human resigned this game. Position-derived results cannot express it:
  /// a resignation leaves a perfectly playable board.
  ///
  /// It matters beyond the scoreboard. Without a way to resign, a game the
  /// player was losing ends by being abandoned, and an abandoned game archives
  /// as '*', which brain/playerElo.ts drops. So every game a player would have
  /// resigned was invisible to their rating, and the estimate read high — worse
  /// against stronger opponents, where you resign more often.
  bool _resigned = false;
  bool get resigned => _resigned;

  bool get gameOver => position.isGameOver || _resigned || _flagged != null;
  /// Whose colour sits at the bottom of the board (follows orientation).
  bool get whiteAtBottom => (playerColor == 'w') != flipped;
  /// The position actually on screen: a browsed ply, a hover preview, or live.
  String get displayFen => browseFen ?? previewFen ?? position.fen;

  String get statusLine {
    final flag = _flagged;
    if (flag != null) {
      final loser = flag == ClockSide.white ? 'White' : 'Black';
      final winner = flag == ClockSide.white ? 'Black' : 'White';
      return '$loser ran out of time — $winner wins';
    }
    if (_resigned) {
      return 'You resigned — ${playerColor == 'w' ? 'Black' : 'White'} wins';
    }
    if (position.isCheckmate) {
      final winner = position.turn == Side.white ? 'Black' : 'White';
      return 'Checkmate — $winner wins';
    }
    if (position.isStalemate) return 'Stalemate';
    if (position.isInsufficientMaterial) return 'Draw — insufficient material';
    if (!botEnabled) {
      return 'Analysis — ${position.turn == Side.white ? "White" : "Black"} to move';
    }
    // a dead engine used to show the boot-error screen; boot no longer waits
    // for it, so without this the symptom is a board whose bot never moves
    if (_arbiter.engineError != null) return 'Engine unavailable — no analysis';
    final mover = personaToMove;
    if (mover == null) return 'Your move';
    final side = position.turn == Side.white ? 'White' : 'Black';
    if (botBothSides) {
      // two bots (or one twice): name the side so it is followable
      return botThinking
          ? '${mover.name} is thinking… ($side)'
          : '${mover.name} to move ($side)';
    }
    return botThinking ? '${mover.name} is thinking…' : '${mover.name} to move';
  }

  /// The grade shown in the strip/insight card: the player's latest move —
  /// or, on the analysis board, simply the latest move of either side.
  MoveGrade? get lastPlayerGrade {
    for (var i = moves.length - 1; i >= 0; i--) {
      // bot-vs-bot has no "player" side, so show whichever move is latest
      if (!botEnabled || botBothSides || moves[i].color == playerColor) {
        return moves[i].grade;
      }
    }
    return null;
  }

  /// The win chance the last graded move started from, the one it ended on,
  /// and the drop between them — mover's perspective, 0..100.
  ///
  /// This is the number the label is computed from (insights.ts classifies on
  /// win% drop: 20 is a blunder, 10 a mistake, 5 an inaccuracy) and the number
  /// practice collects on. It shares [_wcDrop] with [_storedMoveOf] so the
  /// figure the card prints and the figure `maybeCollect` decides on cannot be
  /// two different computations that drift.
  ///
  /// `before` is the best move's eval at [MoveGrade.fenBefore], i.e. what the
  /// position was worth to the mover before it chose; `after` is what the move
  /// it played is worth. Both are the mover's own view, so in an ordinary bot
  /// game they are the player's.
  ///
  /// Null until the grade is BACKFILLED, and that gate is load-bearing rather
  /// than cosmetic: `gradeMove` leaves `evalPawns` null for a move outside the
  /// pre-move MultiPV lines — which is most bad moves, the ones this number
  /// exists for — and `winChance(null, null)` is 50. Ungated, the card would
  /// print a confident delta against an eval the engine never produced, and it
  /// would print it for exactly the moves whose delta matters. The label is
  /// withheld until backfill for the same reason.
  ({double before, double after, double drop})? get lastGradeWinChance {
    final g = lastPlayerGrade;
    if (g == null || !g.backfilled) return null;
    // Memoised on the grade OBJECT, not on a copy of its numbers: grading
    // replaces the record's grade wholesale (gradeMove, then backfillGrade)
    // and never edits one in place, so identity is exact here. Worth doing —
    // this getter is read from build() and the card rebuilds on every
    // streamed analysis update, and each miss is four synchronous calls
    // across the JS bridge.
    if (!identical(g, _wcGrade)) {
      _wcGrade = g;
      _wcCache = (
        before: _grading.winChance(g.bestEval, g.bestMate),
        after: _grading.winChance(g.evalPawns, g.mate),
        // NOT before - after: the drop is whatever the collector collects on,
        // clamp included, and it is defined in exactly one place.
        drop: _wcDrop(g),
      );
    }
    return _wcCache;
  }

  MoveGrade? _wcGrade;
  ({double before, double after, double drop})? _wcCache;

  /// The win% a grade gave away: what the best move was worth minus what the
  /// move played is worth, both mover-POV.
  ///
  /// Clamped at zero because the two numbers come from different searches —
  /// the backfilled eval is the deeper one, and it can land slightly above the
  /// pre-move best. A negative loss is not a thing this measures.
  double _wcDrop(MoveGrade g) => (_grading.winChance(g.bestEval, g.bestMate) -
          _grading.winChance(g.evalPawns, g.mate))
      .clamp(0.0, 100.0);

  String _settingsSig() =>
      '${_settings.whitePersonaId}|${_settings.blackPersonaId}';

  /// Assigned in the CONSTRUCTOR, not by a `late` field initializer.
  ///
  /// A late initializer runs on first READ, and the only read is the
  /// comparison in [_onSettings] — so it used to compute itself from the
  /// settings as they already were AFTER the change, find them equal, and skip
  /// the restart. Measured: the first opponent change of a session left the
  /// game running (moves intact, new persona on move); every later one worked,
  /// which is why it survived. It matters here because [_rated] is cleared by
  /// [newGame]: a rated game whose opponent was swapped part-way would
  /// otherwise archive as a rated result against a bot that only played half
  /// of it.
  late String _lastSettingsSig;

  void _onSettings() {
    final sig = _settingsSig();
    if (sig == _lastSettingsSig) {
      // Only the overlay switches need a fresh probe. Colour pickers and
      // opacity sliders notify on every drag frame, and re-probing there
      // queued dozens of engine searches ahead of the position's analysis.
      final overlaySig = '${_settings.showThreats}|${_settings.blind}';
      if (overlaySig != _lastOverlaySig) {
        _lastOverlaySig = overlaySig;
        _probeThreat();
      }
      notifyListeners();
      return;
    }
    _lastSettingsSig = sig;
    _syncRetro();
    // NOT newGame(). The only caller that changes players is the New Game
    // sheet, and its very next line calls newGame(fromFen:) itself — with the
    // FEN, which this cannot know. Resetting here too meant every opponent
    // change bumped the generation twice, started two analyses, and wiped to
    // the standard start before the sheet immediately redid it with the FEN.
    //
    // Measured through the sheet's real sequence: 2 resets per change before
    // this, 1 after. Making _lastSettingsSig eager (an earlier attempt at the
    // same issue) went the other way — it took the FIRST change from 1 to 2.
    //
    // The contract this creates: changing players is not itself a new game;
    // the caller starts one. setPlayers says so.
  }

  /// Keep at most one retro worker alive, matching the active persona.
  ///
  /// Called when the persona changes as well as at move time, so the wasm is
  /// compiling while the player is still setting up rather than during the
  /// bot's first think — 4.4MB is a visible pause if you pay for it there.
  /// Switching away disposes it: keeping a second engine's worker resident
  /// costs the memory for nothing.
  RetroEngine? _syncRetro() {
    // match the side to move: in bot-vs-bot the retro engine alternates with
    // the mover (a per-move worker rebuild if the two sides are different
    // retros, which is rare and acceptable for a watch feature).
    final spec = personaToMove?.retro;
    final key = spec == null ? null : '${spec['engine']}:${spec['ply']}';
    if (key != _retroKey) {
      _retro?.dispose();
      _retro = null;
      _retroKey = key;
      if (spec != null && RetroEngine.supported) {
        _retro =
            RetroEngine(spec['engine'] as String, (spec['ply'] as num).toInt());
      }
    }
    return _retro;
  }

  // ---- game actions ----

  /// Whether [fen] is a full, legal position we can start from — used to
  /// validate a pasted FEN before handing it to [newGame].
  static bool isPlayableFen(String fen) {
    try {
      Chess.fromSetup(Setup.parseFen(fen.trim()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start a fresh game. [fromFen] drops onto an arbitrary position instead of
  /// the standard start (an analysis board when both sides are the human) —
  /// the caller must have validated it with [isPlayableFen].
  ///
  /// [rated] marks the game as one that counts (see [_rated]). It records the
  /// choice only: turning blind on and the overlays off is the SHEET's job,
  /// because those are the player's persistent settings and this class does
  /// not own them. Defaulting to false is what makes every other caller —
  /// the settings listener no longer restarts on an opponent change; the
    // New Game sheet does that itself —
  /// start a casual game, which is the right answer for all of them.
  void newGame({String? fromFen, bool rated = false, TimeControl? timeControl}) {
    _browsePly = null;
    _redoStack.clear();
    _gen++;
    _arbiter.bumpGeneration();
    position = fromFen == null
        ? Chess.initial
        : Chess.fromSetup(Setup.parseFen(fromFen.trim()));
    _startFen = position.fen;
    lastMove = null;
    moves.clear();
    botThinking = false;
    // A Maia download outlives the game that started it — the request is
    // abandoned but its future is not, so nothing else clears this. Left set,
    // the strip claimed the NEXT persona was downloading a model it does not
    // have, for up to 90s.
    //
    // Both halves are needed. Clearing alone left a race: the abandoned
    // request was still in the engine's _pending, so a progress message
    // arriving just after this line passed the is-this-wanted check and set
    // it straight back.
    maiaProgress = null;
    _maia?.cancelPending();
    _resigned = false;
    _standInPersonas.clear();
    _botUndos = 0;
    _botHintsUsed = false;
    _rated = rated;
    _clock?.dispose();
    _flagged = null;
    _clock = rated && timeControl != null
        ? (ChessClock(timeControl)
          ..onFlag = (side) {
            // A result, so it archives like one. The board is still legal,
            // exactly as with a resignation.
            _flagged = side;
            _gen++;
            _arbiter.bumpGeneration();
            botThinking = false;
            notifyListeners();
            _saveGame();
          })
        : null;
    _undoWasCounted.clear();
    _saved = false;
    gameSeed = _newSeed();
    _analysis.clear();
    _partials.clear();
    _controlCache.clear(); // per-fen maps would accrete for the process life
    // Not a correctness fix — the memo is keyed on the grade object and the
    // new game's grades are new objects, so a stale entry can never be
    // returned. This drops the reference so a finished game's last grade is
    // not held alive by the controller.
    _wcGrade = null;
    _wcCache = null;
    _threat = null;
    _analysisFor(position.fen);
    _syncTree(); // playedSans is empty → the model wipes itself
    _probeThreat();
    notifyListeners();
    _maybeBotTurn();
  }

  /// Moves taken off by undo, in game order, so redo can put them back
  /// exactly as they were — including their grades, which cost engine time
  /// to earn. Any new move discards them (see _apply).
  final RedoStack _redoStack = RedoStack();

  /// One flag per batch sitting in [_redoStack]: whether that undo added to
  /// [_botUndos]. Same order as the stack (newest undo at the front, which is
  /// the batch redo takes first), so a redo gives back the takeback the undo it
  /// undoes actually counted — and a game whose bot was switched off partway
  /// cannot come out with a negative count.
  final List<bool> _undoWasCounted = [];

  bool get canUndo =>
      !botThinking &&
      (botEnabled
          ? moves.any((m) => m.color == playerColor)
          : moves.isNotEmpty);
  bool get canRedo => _redoStack.isNotEmpty && !botThinking;

  /// Undo the last player move (and the bot reply on top of it);
  /// on the analysis board, one ply at a time.
  /// Concede the game: archive it as a loss and stop play.
  ///
  /// Only in a real game — the analysis board has no opponent to concede to —
  /// and only while one is in progress. Saving here rather than waiting for
  /// something else to notice, because nothing else will: no move follows a
  /// resignation.
  void resign() {
    if (!botEnabled || _resigned || position.isGameOver || moves.isEmpty) return;
    _resigned = true;
    _gen++; // a bot turn in flight must not answer a game that has ended
    _arbiter.bumpGeneration();
    botThinking = false;
    notifyListeners();
    _saveGame();
  }

  void undo() {
    _browsePly = null;
    if (moves.isEmpty || botThinking) return;
    // in a bot game there must be a player move to take back: undoing the
    // bot's lone opening move would leave the bot on turn with input dead
    if (botEnabled && !moves.any((m) => m.color == playerColor)) return;
    // Counted HERE, below every early return, so a takeback that was refused
    // — the bot still thinking, or nothing of yours left to take back — is not
    // recorded as one. On the analysis board there is no result to assist, so
    // nothing is counted there either.
    final counted = botEnabled;
    if (counted) _botUndos++;
    _undoWasCounted.insert(0, counted);
    _gen++;
    _arbiter.bumpGeneration();
    final undone = <MoveRecord>[];
    if (botEnabled) {
      while (moves.isNotEmpty && moves.last.color != playerColor) {
        undone.add(moves.removeLast());
      }
      if (moves.isNotEmpty) undone.add(moves.removeLast());
    } else {
      undone.add(moves.removeLast());
    }
    // prepended: this batch is OLDER than anything a previous undo stored
    _redoStack.pushUndone(undone);
    final fen = moves.isEmpty ? _startFen : moves.last.fenAfter;
    position = Chess.fromSetup(Setup.parseFen(fen));
    lastMove =
        moves.isEmpty ? null : NormalMove.fromUci(moves.last.uci);
    _saved = false; // a re-finished game is a new game to archive
    _threat = null;
    _analysisFor(position.fen);
    _syncTree();
    _probeThreat();
    notifyListeners();
    _maybeBotTurn(); // safety: never leave the bot on turn (no-op otherwise)
  }

  /// Put back what undo took off. Replays the stored moves rather than
  /// re-deriving them, so the grades and explanations come back intact
  /// instead of being recomputed — or lost.
  void redo() {
    _browsePly = null;
    if (_redoStack.isEmpty || botThinking) return;
    // An undo→redo round trip taught you nothing and changed nothing: the same
    // moves go back on the same board, so it is not a takeback and must not
    // cost the game its clean crown or its place in the rating fit. Only a
    // round trip can reach here — any divergent move clears the redo stack
    // (see _apply), which is what makes the takeback stand.
    if (_undoWasCounted.isNotEmpty && _undoWasCounted.removeAt(0)) {
      _botUndos--;
    }
    _gen++;
    _arbiter.bumpGeneration();
    // one undo's worth: the player move and the bot's reply that sat on it
    moves.addAll(_redoStack.takeBatch(
        botEnabled: botEnabled, playerColor: playerColor));
    position = Chess.fromSetup(Setup.parseFen(moves.last.fenAfter));
    lastMove = NormalMove.fromUci(moves.last.uci);
    _threat = null;
    _analysisFor(position.fen);
    _syncTree();
    _probeThreat();
    notifyListeners();
  }

  /// The human plays a move (already validated by the board).
  void playerMove(NormalMove move, String san) {
    if (!isPlayerTurn || botThinking || gameOver) return;
    // the sample point: what the board was showing at the moment a human move
    // was committed (see [_botHintsUsed]). Bot replies come through _apply
    // directly, so only human moves are sampled.
    if (botEnabled && _assisted) _botHintsUsed = true;
    _apply(move, san);
    _maybeBotTurn();
  }

  /// Play a uci directly (tree/lines tap) — same rules as a board move.
  void playUci(String uci) {
    if (!isPlayerTurn || botThinking || gameOver) return;
    final move = NormalMove.fromUci(uci);
    if (!position.isLegal(move)) return;
    // Both callers are a machine handing you a move to play — the engine's
    // lines in the tree pane, and the opening book. Taking one is help whatever
    // the overlay switches say, so this does not go through [_assisted].
    // Set after the legality check: a tap that plays nothing is not help taken.
    if (botEnabled) _botHintsUsed = true;
    final (_, san) = position.makeSan(move);
    playerMove(move, san);
  }

  // ---- internals ----

  void _apply(NormalMove move, String san) {
    // The clock, before anything else touches the position: the side that just
    // moved is the one whose turn it currently IS, and playUnchecked below
    // flips that. First move starts it rather than pressing — there is nothing
    // to bank yet.
    final c = _clock;
    if (c != null) {
      final mover = ClockSide.fromChar(position.turn == Side.white ? 'w' : 'b');
      if (moves.isEmpty) {
        c.start(mover);
      }
      c.press(mover);
    }
    stopPreview();
    // a new move makes the undone future unreachable — without this, redo
    // after a divergent move replayed a stale record onto the wrong position
    _redoStack.clear();
    _undoWasCounted.clear(); // nothing left to redo, so nothing left to refund
    final fenBefore = position.fen;
    position = position.playUnchecked(move);
    lastMove = move;
    final record = MoveRecord(
      ply: moves.length + 1,
      san: san,
      uci: move.uci,
      color: position.turn == Side.white ? 'b' : 'w',
      fenBefore: fenBefore,
      fenAfter: position.fen,
    );
    moves.add(record);
    _syncTree(); // extend the played path (and prune the old anchor's churn)
    notifyListeners();
    // the board moved on: older analyses wrap up at depth 12 and yield the
    // engine — only the current position gets the full budget (web semantic;
    // without this a fast game builds a 3s-per-ply backlog)
    _arbiter.cancelAnalyses(exceptFen: position.fen);
    // post-analysis = next move's pre-lines; streamed partials backfill this
    // move's grade the moment the child search passes depth 10 (web parity —
    // the label shouldn't wait out the full 3s budget)
    final gen = _gen;
    _analysisFor(position.fen,
        onUpdate: (lines) => _earlyBackfill(record, lines, gen));
    _probeThreat();
    late final Future<void> pipeline;
    pipeline = _gradePipeline(record, _gen)
      ..whenComplete(() => _pendingGrades.remove(pipeline));
    _pendingGrades.add(pipeline);
    if (gameOver) _saveGame();
  }

  void _earlyBackfill(MoveRecord record, List<EngineMove> lines, int gen) {
    if (gen != _gen || lines.isEmpty || lines.first.depth < 10) return;
    final grade = record.grade;
    if (grade == null || grade.backfilled) return;
    record.grade = _grading.backfillGrade(grade, lines);
    notifyListeners();
  }

  /// Debug/self-test only: archive the game regardless of game-over state.
  Future<void> debugForceSave() => _saveGame();

  String get _result {
    // Before the position checks: the board is still playable, which is the
    // whole point of resigning.
    if (_resigned) return playerColor == 'w' ? '0-1' : '1-0';
    // Flag-fall, before the position checks for the same reason: the board is
    // still playable, which is the point.
    final flagged = _flagged;
    if (flagged != null) return flagged == ClockSide.white ? '0-1' : '1-0';
    if (position.isCheckmate) {
      return position.turn == Side.white ? '0-1' : '1-0';
    }
    if (position.isGameOver) return '1/2-1/2';
    return '*';
  }

  /// Archive the finished game — the web's saveCurrentGame, same StoredGame
  /// shape (JSON-compatible with the IndexedDB store for future import).
  Future<void> _saveGame() async {
    final db = _db;
    if (db == null || moves.isEmpty || _saved) return;
    _saved = true;
    // Snapshot the finished game BEFORE the wait below. The wait can run for
    // seconds, and an undo during it would otherwise archive a truncated game
    // with a result that no longer matches. The records themselves are safe to
    // hold: grading fills them in place (which is what we are waiting for) and
    // undo only removes them from the list.
    final played = List<MoveRecord>.of(moves);
    final p = botEnabled ? persona : null;
    final result = _result;
    final botName = p == null ? 'Analysis' : '${p.name} (${p.elo})';
    final youAreWhite = playerColor == 'w';
    // snapshotted with the rest: a new game during the grade wait below clears
    // it, and the record being written belongs to the game that just ended
    final fallback = botFallback;
    // The same shape and the same hazard. All three are per-game counters that
    // newGame resets, and after a checkmate the player starts the next game
    // while this wait is still running — reading them below archives the NEW
    // game's help against the old game's result. That is exactly the bug
    // botFallback shipped with two days ago (#117), and these two would have
    // repeated it verbatim. botEnabled is read here for the same reason.
    final wasBotGame = botEnabled;
    // Bot-vs-bot has no human in it, so nothing about it is a human result.
    // playerColor falls back to 'w' when BOTH sides carry a persona, so such a
    // game archives as "the human was White" and would otherwise collect a
    // Won-clean crown for a game nobody played.
    final bothBots = _settings.whitePersonaId != null &&
        _settings.blackPersonaId != null;
    final undos = wasBotGame ? _botUndos : 0;
    final hintsUsed = wasBotGame && _botHintsUsed;
    // Snapshotted here for the same reason as the two above, and it is the one
    // that would be hardest to notice going wrong: a player who mates and then
    // starts a casual game during the grade wait would otherwise archive the
    // rated game they just won as unrated, and the rating would simply never
    // move. Bot-vs-bot and the analysis board can never be rated — the sheet
    // does not offer it — but `wasBotGame` is asserted here anyway, because
    // this record is what the rating trusts.
    final rated = wasBotGame && _rated;

    // let in-flight grading land so the archive gets labels (bounded — the
    // terminal move's backfill may never come: a mate position has no lines)
    if (_pendingGrades.isNotEmpty) {
      await Future.wait(_pendingGrades.toList())
          .timeout(const Duration(seconds: kSaveGradeWaitSeconds),
              onTimeout: () => []);
    }

    final stored = played.map(_storedMoveOf).toList();

    final record = {
      'id': 'g-${DateTime.now().millisecondsSinceEpoch}-${played.length}',
      'endedAt': DateTime.now().toIso8601String(),
      'result': result,
      'pgn': _pgn(played, result, botName, youAreWhite),
      'botElo': p == null ? null : p.elo + 240, // internal scale (SCALE_OFFSET)
      if (p != null) 'botPersona': p.id,
      // omitted rather than false when clean: the schema field is optional and
      // estimatePlayerElo tests it for truthiness, so absent and false mean the
      // same thing — and every game saved before this existed is absent.
      if (fallback) 'botFallback': true,
      // omitted at zero for the same reason as botFallback — playerElo reads
      // `(g.botUndos ?? 0) > 0`, so absent and 0 already mean the same thing
      if (undos > 0) 'botUndos': undos,
      // Written even when FALSE, unlike the two above, because here absent
      // carries its own meaning: "hints unknown". Every game archived before
      // this shipped lacks the field, and the archive refuses those the clean
      // crown rather than crediting them with a discipline nobody recorded.
      // An explicit false is the only way to say "known clean".
      if (wasBotGame) 'botHintsUsed': hintsUsed,
      // Omitted rather than false, like botFallback: `playerElo` gates on
      // `g.rated !== true`, so absent and false already mean the same thing —
      // and absent is what every game archived before rated mode existed says.
      if (rated) 'rated': true,
      if (bothBots) 'botBothSides': true,
      // the snapshot, not a fresh read of playerColor: the crown asks which
      // side the human was on, and this is the one line below the wait that
      // was still asking the live settings
      'botColor': p == null ? null : (youAreWhite ? 'b' : 'w'),
      'moveCount': played.length,
      'whiteAccuracy': _bridgeAccuracy(stored, 'w'),
      'blackAccuracy': _bridgeAccuracy(stored, 'b'),
      'labelCounts': {
        'w': _grading.labelCounts(stored, 'w'),
        'b': _grading.labelCounts(stored, 'b'),
      },
      'labelVersion': 1,
      'moves': stored,
    };
    await db.saveGame(record);
  }

  double? _bridgeAccuracy(List<Map<String, dynamic>> stored, String color) =>
      _grading.gameAccuracy(stored, color);

  String _pgn(List<MoveRecord> played, String result, String botName,
      bool youAreWhite) {
    final white = youAreWhite ? 'You' : botName;
    final black = youAreWhite ? botName : 'You';
    final date =
        DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '.');
    final sb = StringBuffer()
      ..writeln('[White "$white"]')
      ..writeln('[Black "$black"]')
      ..writeln('[Date "$date"]')
      ..writeln('[Result "$result"]')
      ..writeln();
    for (var i = 0; i < played.length; i++) {
      if (i.isEven) sb.write('${i ~/ 2 + 1}. ');
      sb.write('${played[i].san} ');
    }
    sb.write(result);
    return sb.toString();
  }

  Future<void> _maybeBotTurn() async {
    if (!botEnabled || isPlayerTurn || gameOver || botThinking) return;
    final p = personaToMove;
    if (p == null) return;
    botThinking = true;
    notifyListeners();
    final gen = _gen;
    // let the analysis of the player's move reach depth 10 before the bot's
    // reply search preempts it — the player's grade label lands in <1s and
    // the bot pausing a beat before answering reads human anyway
    final graded = position.fen;
    final sprintStart = DateTime.now();
    while (gen == _gen &&
        (_partials[graded]?.firstOrNull?.depth ?? 0) < 10 &&
        DateTime.now().difference(sprintStart).inMilliseconds < 1500) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // Generation changed under us (a new game). Whoever bumped it owns
    // botThinking now — newGame sets it false and may immediately start the new
    // game's own bot turn (setting it true again); undo/redo can't run while it
    // is true — so clearing it here would clobber that fresh turn, re-enabling
    // re-entry. Just bail. (The finally guards the same way: it only touches
    // botThinking when gen == _gen.)
    if (gen != _gen) return;
    try {
      final picked = await _pickBotMove(p);
      final uci = picked.uci;
      if (gen != _gen || uci == null) return;
      final move = NormalMove.fromUci(uci);
      if (!position.isLegal(move)) return;
      final san = _sanOf(position, move);
      // Committed here, not where the stand-in was chosen: this is past the
      // generation check, so an abandoned turn cannot stamp the game that
      // replaced it, and past the legality check, so a turn that produced no
      // move does not claim a substitution that never reached the board.
      if (picked.standIn) _standInPersonas.add(p.id);
      _apply(move, san);
      // If the NEXT side to move is also a bot, keep going on our own — this
      // is what makes bot-vs-bot play itself, and it is a no-op in a normal
      // game (after the bot moves it is the human's turn, so isPlayerTurn is
      // true). The delay makes it watchable; the gen check stops it the
      // instant a new game or undo bumps the generation, and _apply's gameOver
      // handling ends it at mate/stalemate. Fires after this invocation's
      // finally has cleared botThinking, so the recursive call is not blocked.
      if (!gameOver && !isPlayerTurn) {
        Future.delayed(Duration(milliseconds: _settings.botDelayMs)).then((_) {
          if (gen == _gen && !gameOver && !isPlayerTurn) _maybeBotTurn();
        });
      }
    } catch (e, st) {
      // Every call site here is fire-and-forget and the app installs no
      // zone guard, so without this an exception — a bridge StateError, a
      // dead engine — becomes an unhandled async error and leaves the board
      // silently dead: bot on turn, nothing thinking, input refused. Contained
      // here it is at least logged, and undo still recovers (it hands the turn
      // back, so this method returns early rather than retrying the failure).
      debugPrint('[bot] move selection failed: $e\n$st');
    } finally {
      if (gen == _gen) {
        botThinking = false;
        notifyListeners();
      }
    }
  }

  /// The bot's move, and whether it came from the Stockfish stand-in rather
  /// than the persona's own engine.
  ///
  /// Returned rather than written straight to [botFallback] because this
  /// method awaits — a turn abandoned mid-await by a new game would otherwise
  /// resume and stamp the flag on the game that replaced it. The caller commits
  /// it after its own generation check, and only once the move is really played.
  Future<({String? uci, bool standIn})> _pickBotMove(Persona p) async {
    final fen = position.fen;
    if (p.family == 'squarefish') {
      final label = p.shapedLabel!;
      final lines = await _arbiter.search(
        fen: fen,
        depth: _bot.shapedSearchDepth(label),
        multiPv: kBotMultiPv,
        priority: SearchPriority.botMove,
      );
      if (lines == null || lines.isEmpty) return (uci: null, standIn: false);
      final lastTo =
          lastMove is NormalMove ? (lastMove as NormalMove).uci.substring(2, 4) : null;
      final pick = _bot.shapedMove(
            lines: lines,
            label: label,
            seed: gameSeed,
            fen: fen,
            lastMoveTo: lastTo,
          ) ??
          lines.first.uci;
      return (uci: _bot.avoidRepetition(pick, _fenHistory(), lines), standIn: false);
    }
    if (p.family == 'horizon') {
      // no engine search at all — js-chess-engine runs inside the JS runtime
      // that is already loaded, and answers in ~2-5ms. avoidRepetition gets
      // the app's own analysis lines (what repetition.ts documents wanting):
      // this branch is synchronous throughout, so they describe THIS position,
      // and an empty list degrades to returning the move unchanged.
      final uci = _bot.horizonMove(fen, p.jsceLevel ?? 1);
      if (uci != null) {
        return (uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines), standIn: false);
      }
      debugPrint('[bot] horizon had no move; falling back to the engine');
    }
    if (p.family == 'retro') {
      // Its own worker, never the arbiter: a 1948 engine has no business in
      // the queue that serialises the Stockfish every grade depends on, and
      // its answer is not an analysis of anything. See retro_engine_web.dart.
      //
      // Unlike horizon this awaits, so the position can move on underneath
      // it — which is fine, because _maybeBotTurn re-checks the generation
      // and the move's legality before anything reaches the board.
      final uci = await _syncRetro()?.move(fen);
      if (uci != null) {
        return (uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines), standIn: false);
      }
      debugPrint('[bot] retro had no move; falling back to the engine');
    }
    if (p.family == 'garbo') {
      // Same shape as retro: its own worker, never the arbiter. Unlike retro
      // there is nothing to configure, so the engine is built on first use
      // rather than tracked against the persona.
      if (GarboEngine.supported) {
        _garbo ??= GarboEngine();
        final uci = await _garbo!.move(fen, movetimeMs: p.garboMs ?? 1000);
        if (uci != null) {
          return (uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines), standIn: false);
        }
      }
      debugPrint('[bot] garbo had no move; falling back to the engine');
    }
    if (p.family == 'maia') {
      // Maia wants the game's HISTORY, not just the position — it was trained
      // with eight plies of it and its move distribution sharpens accordingly.
      // _fenHistory() is already oldest-first with the current position last,
      // which is the order the net expects.
      final band = p.maiaBand;
      if (MaiaEngine.supported && band != null) {
        _maia ??= MaiaEngine(onProgress: (p) {
          maiaProgress = p;
          notifyListeners();
        });
        final uci = await _maia!.move(
          _fenHistory(),
          band: band,
          temperature: p.maiaTemp ?? 0,
        );
        if (maiaProgress != null) {
          maiaProgress = null;
          notifyListeners();
        }
        if (uci != null) {
          return (uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines), standIn: false);
        }
      }
      debugPrint('[bot] maia had no move; falling back to the engine');
    }
    // Stockfish, and the fallback for anything that could not answer for
    // itself. internalElo rather than numericElo: only stockfish carries
    // numericElo, and a family without an implementation here should play at
    // its own rating rather than crash on a null.
    //
    // This IS the "different opponent wearing the persona's name" that
    // roster_picker refuses to offer, and the two are complementary rather
    // than contradictory: the picker gates unimplemented families so a player
    // can never CHOOSE one, and this is the safety net for an id that arrives
    // some other way — a stored personaId from an older build, or from the
    // web, where the roster is larger. A stand-in beats the alternative here,
    // which used to be `p.numericElo!` throwing and wedging the bot's turn.
    //
    // It is not free, though: grading a game against the rating you THINK you
    // played corrupts the player-rating fit, so the substitution is recorded.
    //
    // Tested here rather than at each `falling back to the engine` log above
    // because this is the one place that cannot drift: every family that gets
    // its own branch reaches this line only by failing, and a family that never
    // gets a branch at all (dala, #45) reaches it without one. Marking at the
    // log sites would silently miss the second kind, and would need a new call
    // adding every time a family is added.
    //
    // `stockfish` is the exception because this block IS its engine — the only
    // family that arrives here having played itself. Flagging it too would put
    // the mark on every stockfish game and leave the flag meaning nothing.
    final standIn = p.family != 'stockfish';
    final internalElo = p.numericElo ?? _bot.internalElo(p);
    final spec = _bot.botSpec(internalElo);
    switch (spec['kind'] as String) {
      case 'sampler':
        final lines = await _arbiter.search(
          fen: fen,
          depth: (spec['depth'] as num).toInt(),
          multiPv: 24,
          priority: SearchPriority.botMove,
        );
        if (lines == null || lines.isEmpty) return (uci: null, standIn: false);
        final pick = _bot.fishMove(
              lines: lines,
              internalElo: internalElo,
              alpha: (spec['alpha'] as num?)?.toDouble(),
            ) ??
            lines.first.uci;
        return (uci: _bot.avoidRepetition(pick, _fenHistory(), lines), standIn: standIn);
      case 'skill':
        final lines = await _arbiter.search(
          fen: fen,
          depth: (spec['depth'] as num).toInt(),
          multiPv: 1,
          extraOptions: [
            ['Skill Level', '${spec['level']}'],
          ],
          priority: SearchPriority.botMove,
        );
        return (uci: lines?.isNotEmpty == true ? lines!.first.uci : null, standIn: standIn);
      default: // ucielo
        final lines = await _arbiter.search(
          fen: fen,
          depth: 0,
          multiPv: 1,
          movetimeMs: (spec['movetimeMs'] as num).toInt(),
          extraOptions: [
            ['UCI_LimitStrength', 'true'],
            ['UCI_Elo', '${spec['elo']}'],
          ],
          priority: SearchPriority.botMove,
        );
        return (uci: lines?.isNotEmpty == true ? lines!.first.uci : null, standIn: standIn);
    }
  }

  /// The engine's live view of the current position (deepest streamed
  /// snapshot) — feeds the Lines pane as the search deepens.
  List<EngineMove> get currentLines => _partials[position.fen] ?? const [];

  bool get blind => _settings.blind;

  /// What the panes may show: nothing forward-looking in blind mode during
  /// a live bot game (web: visibleLines).
  List<EngineMove> get visibleLines =>
      blind && botEnabled ? const [] : currentLines;

  // ---- overlays: opponent threat (null-move probe) + square control ----

  Map<String, dynamic>? _threat; // {fen, uci, san, gain} — fen-gated
  final Map<String, Map<String, String>> _controlCache = {};

  /// Top engine moves for the board's green arrows (web: top-3, fading).
  List<String> get engineArrowUcis {
    if (!_settings.showArrows || blind) return const [];
    return [for (final l in currentLines.take(_settings.arrowCount)) l.uci];
  }

  /// The live threat, when it is fresh and wanted — the move the opponent
  /// would play with a free move, and what it nets them.
  Map<String, dynamic>? get threat {
    if (!_settings.showThreats || blind) return null;
    final t = _threat;
    return t != null && t['fen'] == position.fen ? t : null;
  }

  /// The threat arrow's uci.
  String? get threatUci => threat?['uci'] as String?;

  /// The threat in algebraic notation, e.g. 'Be6'.
  String? get threatSan => threat?['san'] as String?;

  /// What the threat nets them, in pawns. NULL MEANS MATE: the brain reports
  /// Infinity there and JSON has no way to carry it across the bridge.
  double? get threatGain => (threat?['gain'] as num?)?.toDouble();

  /// Current squares of the pieces the threat wins (the mated king for a
  /// mate): attacked by the threat move THIS INSTANT, and lost even under
  /// best defense in the line. A forked queen that escapes is neither.
  List<String> get threatTargets =>
      ((threat?['targets'] as List?) ?? const []).cast<String>();

  /// The threat's line as UCIs — the window the gain was judged over, not the
  /// engine's raw pv, so replaying it never shows a capture the gain did not
  /// credit. Played from [threatProbeFen].
  List<String> get threatLine =>
      ((threat?['line'] as List?) ?? const []).cast<String>();

  /// The null-move position the threat line starts from (it is the opponent's
  /// move there). The base for a preview of [threatLine].
  String? get threatProbeFen => threat?['probeFen'] as String?;

  // the green mirror: memoised per (fen, top line) — the judge is a pure
  // bridge call, cheap but not free, and this getter runs on every rebuild
  Map<String, dynamic>? _winCache;
  String? _winKey;

  /// What the side to move's OWN top line wins — judged by the same rules as
  /// the threat (attacked after ply 1, falls in the window, no even trades).
  /// Costs no engine time: the line is the live analysis already streaming.
  Map<String, dynamic>? get tacticalWin {
    if (!_settings.showThreats || blind) return null;
    // in a bot game, "your line" only exists on YOUR turn — during the bot's
    // think the streamed lines are ITS tactics, and green rings for them
    // would invert the overlay's meaning (your own king ringed "win")
    if (botEnabled && !isPlayerTurn) return null;
    final chess = _chess;
    if (chess == null) return null;
    final lines = currentLines;
    if (lines.isEmpty) return null;
    // mate is load-bearing: an unchanged pv can convert cp→mate as the
    // search deepens, and the judgment flips with it
    final key = '${position.fen}|${lines.first.mate}|${lines.first.pv.join(' ')}';
    if (_winKey != key) {
      _winKey = key;
      _winCache = chess.judgeTacticalWin(position.fen, {
        'pv': lines.first.pv,
        'mate': lines.first.mate,
      });
    }
    return _winCache;
  }

  /// Current squares of the pieces YOUR top line wins (the enemy king for a
  /// mate) — drawn as green rings in the engine-arrow grammar.
  List<String> get winTargets =>
      ((tacticalWin?['targets'] as List?) ?? const []).cast<String>();

  /// Square-control tint for the current position, when wanted.
  Map<String, String>? get controlMap {
    if (!_settings.showControl || blind) return null;
    final chess = _chess;
    if (chess == null) return null;
    return _controlCache.putIfAbsent(
        position.fen, () => chess.controlSquares(position.fen));
  }

  String? _lastOverlaySig;
  String? _probeInFlightFen; // one probe per position, never a queue of them

  Future<void> _probeThreat() async {
    final chess = _chess;
    if (chess == null || !_settings.showThreats || blind) return;
    final fen = position.fen;
    if (_probeInFlightFen == fen) return;
    final probe = chess.threatProbeFen(fen);
    if (probe == null) {
      _threat = null;
      return;
    }
    final gen = _gen;
    _probeInFlightFen = fen;
    List<EngineMove>? lines;
    try {
      lines = await _arbiter.search(
        fen: probe,
        ownerFen: fen, // stale when the BOARD moves on, not the probe position
        depth: 14,
        multiPv: 1,
        movetimeMs: 500,
        priority: SearchPriority.threatProbe,
      );
    } catch (_) {
      lines = null; // an engine error must not wedge the in-flight flag
    } finally {
      if (_probeInFlightFen == fen) _probeInFlightFen = null;
    }
    if (gen != _gen || lines == null || lines.isEmpty) return;
    final judged = chess.judgeThreat(fen, {
      'pv': lines.first.pv,
      'mate': lines.first.mate,
    });
    // keep the probe position with the verdict: the judged line is played FROM
    // the null-move position (it is the opponent's move there), so that — not
    // the live fen — is what a preview of the threat has to start from.
    _threat = judged == null ? null : {...judged, 'probeFen': probe};
    if (position.fen == fen) notifyListeners();
  }

  // ---- view-only navigation ----
  //
  // Browsing and flipping never touch the game: the moves list, the engine
  // and the grading pipeline all carry on against the live position. Only
  // what the board draws changes.

  /// Plies into the game, or null when following the live position.
  /// 0 is the starting position, k is the position after moves[k-1].
  int? _browsePly;
  bool _flipped = false;

  bool get browsing => _browsePly != null;
  bool get flipped => _flipped;

  String? get browseFen {
    final p = _browsePly;
    if (p == null) return null;
    return p == 0 ? _startFen : moves[p - 1].fenAfter;
  }

  NormalMove? get browseLastMove {
    final p = _browsePly;
    if (p == null || p == 0) return null;
    return NormalMove.fromUci(moves[p - 1].uci);
  }

  /// Where the cursor sits, for a move list to highlight.
  int get browsePly => _browsePly ?? moves.length;

  void toggleFlip() {
    _flipped = !_flipped;
    notifyListeners();
  }

  /// Steps the cursor; stepping past the last move returns to live.
  void browseBy(int delta) {
    if (moves.isEmpty) return;
    final next = (browsePly + delta).clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    notifyListeners();
  }

  void browseTo(int ply) {
    if (moves.isEmpty) return;
    final next = ply.clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    notifyListeners();
  }

  /// Back to the live position — also the escape hatch from a preview.
  void browseLive() {
    if (previewing) stopPreview();
    if (_browsePly == null) return;
    _browsePly = null;
    notifyListeners();
  }

  /// The game-long exploration map (null until wired with a ChessApi).
  LinesTreeModel? linesTree;

  void _syncTree() {
    linesTree?.ingest(
      lines: currentLines,
      fen: position.fen,
      playedSans: moves.map((m) => m.san).toList(),
      height: 300,
    );
  }

  Future<List<EngineMove>?> _analysisFor(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    return _analysis.putIfAbsent(
        fen,
        () => _arbiter.analysis(fen, onUpdate: (lines) {
              _partials[fen] = lines;
              if (fen == position.fen) {
                _syncTree();
                notifyListeners();
              }
              onUpdate?.call(lines);
            }));
  }

  /// White-POV win chance per graded ply — the chart's data.
  List<({int ply, String san, double wc, String? label})> get chartPoints => [
        for (final m in moves)
          if (m.grade != null)
            (
              ply: m.ply,
              san: m.san,
              wc: _grading.whitePovWinChance(
                  m.color, m.grade!.evalPawns, m.grade!.mate),
              label: m.grade!.label,
            )
      ];

  // ---- line preview: animate an explanation's line on the main board ----

  List<String> _previewFens = [];
  List<NormalMove?> _previewMoves = [];
  int _previewIndex = 0;
  Timer? _previewTimer;

  bool get previewing => _previewTimer != null;

  /// Which preview is running — the Insights move line or the threat line.
  /// Both share [previewing] and starting either stops the other, so a button
  /// needs this to know whether IT is the one playing.
  String? _previewTag;
  String? get previewTag => previewing ? _previewTag : null;
  String? get previewFen =>
      previewing ? _previewFens[_previewIndex] : null;
  NormalMove? get previewLastMove =>
      previewing ? _previewMoves[_previewIndex] : null;

  /// Plays [ucis] out from [baseFen] on the board, one move per beat,
  /// then returns to the live position. Tap again to stop early.
  void startPreview(String baseFen, List<String> ucis, {String? tag}) {
    _browsePly = null; // the board prefers browseFen; an unseen preview is a dead key
    stopPreview();
    Position pos;
    try {
      pos = Chess.fromSetup(Setup.parseFen(baseFen));
    } catch (_) {
      return;
    }
    final fens = <String>[baseFen];
    final lastMoves = <NormalMove?>[null];
    for (final uci in ucis) {
      final m = NormalMove.fromUci(uci);
      if (!pos.isLegal(m)) break;
      pos = pos.playUnchecked(m);
      fens.add(pos.fen);
      lastMoves.add(m);
    }
    if (fens.length < 2) return;
    _previewFens = fens;
    _previewMoves = lastMoves;
    _previewIndex = 0;
    _previewTag = tag; // only once we have actually committed to starting
    _previewTimer = Timer.periodic(const Duration(milliseconds: 850), (t) {
      if (_previewIndex >= _previewFens.length - 1) {
        // linger on the final position for a beat, then come home
        t.cancel();
        _previewTimer = Timer(const Duration(milliseconds: 1200), stopPreview);
        return;
      }
      _previewIndex++;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopPreview() {
    if (_previewTimer == null) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    notifyListeners();
  }

  Future<void> _gradePipeline(MoveRecord record, int gen) async {
    final t0 = DateTime.now();
    void log(String msg) => debugPrint(
        'grade[${record.ply} ${record.san}] +${DateTime.now().difference(t0).inMilliseconds}ms $msg');
    // pre-lines: the completed (or cancelled-with-partials) analysis of the
    // position the move was played from, falling back to streamed partials
    var pre = await _analysisFor(record.fenBefore);
    final preFromFuture = pre != null && pre.isNotEmpty;
    if (pre == null || pre.isEmpty) pre = _partials[record.fenBefore];
    log('pre: ${preFromFuture ? "future" : "partials"} '
        'depth=${pre?.firstOrNull?.depth} lines=${pre?.length}');
    if (gen != _gen || pre == null || pre.isEmpty) {
      log('ABORT: no pre-lines');
      return;
    }
    var grade = _grading.gradeMove(
      ply: record.ply,
      fenBefore: record.fenBefore,
      san: record.san,
      uci: record.uci,
      color: record.color,
      preLines: pre,
    );
    record.grade = grade;
    notifyListeners();
    log('graded (rank=${grade.rank})');
    // the child search may already have streamed past depth 10 while we
    // waited on the pre-lines — backfill from the snapshot immediately
    final snap = _partials[record.fenAfter];
    if (snap != null) _earlyBackfill(record, snap, gen);
    if (record.grade?.backfilled == true) log('early backfill from snapshot');

    var child = await _analysisFor(record.fenAfter);
    final childFromFuture = child != null && child.isNotEmpty;
    if (child == null || child.isEmpty) child = _partials[record.fenAfter];
    log('child: ${childFromFuture ? "future" : "partials"} '
        'depth=${child?.firstOrNull?.depth}');
    if (gen != _gen ||
        child == null ||
        child.isEmpty ||
        child.first.depth < 10) {
      log('ABORT: no usable child (label=${record.grade?.label})');
      return;
    }
    record.grade = _grading.backfillGrade(record.grade ?? grade, child);
    notifyListeners();
    log('backfilled label=${record.grade?.label}');

    // auto-collect big mistakes as practice puzzles (web maybeCollect) — but
    // only YOUR mistakes, and only in a real GAME. Practice drills your own
    // blunders against a bot; a bot's move (either side of bot-vs-bot) is not
    // yours to fix, and the analysis board (both sides human, botEnabled false)
    // is exploration — its "mistakes" are deliberate, not puzzles to drill.
    //
    // A blunder you TOOK BACK still lands here, and that is deliberate (decided
    // 2026-07-21). The generation check above looks like it would prevent it —
    // undo() bumps _gen — but it never fires for a takeback: undo() refuses
    // while botThinking, the bot starts thinking the instant you move, and
    // grading has collected long before undo is permitted. That check guards
    // against a NEW GAME landing mid-grade. Do not "fix" it into cancelling
    // collection: you played the blunder, and taking it back does not mean you
    // would find the move next time.
    //
    // Deliberately inconsistent with playerElo.ts, which DOES drop takeback
    // games from the rating fit — rating measures outcomes, practice measures
    // errors. The consequence is that PracticeController.remove() is the only
    // way out of a puzzle you consider noise, and it has no UI yet (#137).
    final practice = _practice;
    if (practice != null && botEnabled && isHumanSide(record.color)) {
      final prevUci =
          record.ply >= 2 ? moves[record.ply - 2].uci : null;
      await practice.maybeCollect(_storedMoveOf(record),
          setupUci: prevUci);
    }
  }

  Map<String, dynamic> _storedMoveOf(MoveRecord m) {
    final g = m.grade;
    final wcDrop = g == null ? 0.0 : _wcDrop(g);
    return {
      'ply': m.ply,
      'san': m.san,
      'uci': m.uci,
      'color': m.color,
      'fenBefore': m.fenBefore,
      'fenAfter': m.fenAfter,
      'evalPawns': g?.evalPawns,
      'mate': g?.mate,
      'pctBest': g?.pctBest,
      'wcDrop': wcDrop,
      'depth': g?.depth ?? 0,
      if (g?.label != null) 'label': g!.label,
      if (g != null) 'bestSan': g.bestSan,
      if (g != null) 'bestUci': g.bestUci,
      if (g?.explanation != null) 'explanation': g!.explanation!.raw,
    };
  }

  List<String> _fenHistory() =>
      [_startFen, ...moves.map((m) => m.fenAfter)];

  String _sanOf(Position pos, Move move) {
    final (_, san) = pos.makeSan(move);
    return san;
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _retro?.dispose();
    _garbo?.dispose();
    _maia?.dispose();
    // Its ticker is a live Timer: left running it outlives the tree, which
    // flutter_test reports as a pending timer and a device reports as a clock
    // still counting down a game nobody is playing.
    _clock?.dispose();
    super.dispose();
  }
}
