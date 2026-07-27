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
import 'dart:convert';
import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../brain/bot_api.dart';
import '../brain/chess_api.dart';
import '../brain/grading_api.dart';
import '../brain/types.dart';
import '../db/app_db.dart';
import '../engine/arbiter.dart';
import '../engine/chessgpt_engine.dart';
import '../engine/custom_engine_runner.dart';
import '../engine/garbo_engine.dart';
import '../engine/maia_engine.dart';
import '../engine/maia_progress.dart';
import '../engine/playable_families.dart';
import '../engine/retro_engine.dart';
import 'custom_engine.dart';
import 'engine_catalog.dart';
import 'lines_tree_model.dart';
import 'maia_status.dart';
import 'practice_controller.dart';
import 'review_controller.dart';
import 'review_tree.dart';
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

  /// Player-added UCI engines (null in tests and where the feature is off). The
  /// config source; the running processes are [_customRunners] below.
  final CustomEngineStore? _customEngines;

  /// One live engine process per custom persona actually played this session,
  /// built on first use and disposed with the controller — the same lifecycle
  /// as [_maia] / [_garbo], never the arbiter's queue.
  final Map<String, CustomEngineRunner> _customRunners = {};

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

  /// The record [_saveGame] just wrote — the exact StoredGame map — held so the
  /// game-over recap can open it in review straight away, without a round-trip
  /// through the archive. Null until a game is archived, and cleared the moment
  /// a new or re-opened game makes it stale.
  Map<String, dynamic>? _lastSavedGame;
  Map<String, dynamic>? get lastSavedGame => _lastSavedGame;

  // analysis cache: fen → future of its MultiPV-5 deep lines
  final Map<String, Future<List<EngineMove>?>> _analysis = {};
  // the deepest streamed snapshot per fen — grading falls back to these when
  // an analysis was cancelled because the board moved on
  final Map<String, List<EngineMove>> _partials = {};
  // fens whose analysis future has RESOLVED — see [analysisSettled]. Cleared
  // wherever _analysis is, and only wherever _analysis is: an entry here is a
  // claim about the future held there, so the two must never disagree.
  final Set<String> _settledFens = {};
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

  /// One ChessGPT engine per VARIANT, because each holds an OrtSession over
  /// its own 26MB net. Keyed rather than single so that a game against one
  /// variant does not tear down and rebuild the session when the next game
  /// picks another — the same reasoning as _customRunners.
  final Map<String, ChessGptEngine> _chessGpt = {};

  /// Per-band Maia load state, watched by the roster picker and New Game sheet
  /// so a download, a compile, and — the point — a FAILURE with its reason are
  /// visible where the opponent is chosen, not just as a silent stand-in.
  final MaiaStatus maiaStatus = MaiaStatus();

  /// The one place the Maia engine is built, so a move and a warm-up share the
  /// same instance and the same progress wiring. Lazy: nothing pays for a Maia
  /// worker until a Maia is actually picked or played.
  MaiaEngine _ensureMaia() => _maia ??= MaiaEngine(
        onProgress: (p) {
          maiaProgress = p;
          notifyListeners();
        },
        onBandStatus: (band, {progress, error}) {
          maiaStatus.update(
            band,
            error != null
                ? MaiaBandState.failed(error)
                : progress != null
                    ? MaiaBandState.loading(progress)
                    : const MaiaBandState.ready(),
          );
        },
      );

  /// Warm a Maia opponent's weights and session the moment it is chosen, not on
  /// its first move. On a phone the 3.5MB download plus the WebAssembly compile
  /// can outrun a move's patience and leave a Stockfish stand-in for the whole
  /// game (the badge is sticky per game); loading during the New-Game sheet's
  /// setup-to-first-move window is what avoids that. A no-op for a non-Maia
  /// persona or a platform without Maia, and fire-and-forget — a failure just
  /// means the first move falls back exactly as it would have.
  void warmUpMaia(String? personaId) {
    if (!MaiaEngine.supported) return;
    final p = personaFor(personaId);
    if (p == null || p.family != 'maia') return;
    final band = p.maiaBand;
    if (band == null) return;
    _ensureMaia().warmUp(band);
  }

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

  /// This game was started with "refuse blunders" on (issue #167): a human
  /// move that loses more than [SettingsStore.collectThreshold] is graded
  /// BEFORE it commits, in [_maybeRefuse], and rejected rather than played —
  /// the position stays put for a retry, and the rejected move is still
  /// collected as a practice puzzle. Per-game like [_rated], set by
  /// [newGame], not a persistent setting: this is a mode you choose for a
  /// session, not a standing preference.
  bool _refuseBlunders = false;
  bool get refuseBlunders => _refuseBlunders;

  /// How many times [_maybeRefuse] actually refused a move this game — NOT
  /// how many times the player retried. Persisted like [_botUndos] and
  /// excluded from the rating fit the same way, but as its own field: a
  /// refusal is not a takeback (nothing was ever committed to take back),
  /// and the reason text an excluded game shows should say what happened.
  int _refusedMoves = 0;
  int get refusedMoves => _refusedMoves;

  /// Refused attempts at each position this game, keyed by fenBefore — reset
  /// per-position once a move there is allowed through (found acceptable, or
  /// relented after [kMaxRefusalAttempts]). Bounded by game length; cleared
  /// wholesale by [newGame].
  final Map<String, int> _refusalAttempts = {};
  static const int kMaxRefusalAttempts = 3;

  /// True while a [_maybeRefuse] call for generation [_refusalPendingGen] is
  /// awaiting a grade. Gates [playerMove]/[playUci] the same way
  /// [botThinking] does — without it, a second move fired before the
  /// first's check resolves could apply against a position [_apply] has
  /// already moved past (playUnchecked does not validate legality against
  /// the CURRENT position, only the one the move was computed from).
  ///
  /// [_refusalPendingGen] exists because this flag is shared across calls,
  /// not per-call: a stale check for an ABANDONED generation (a new game or
  /// undo landed while it was still awaiting its capped grade) must not
  /// clear a FRESH check's flag out from under it when it finally resolves
  /// — that reopens the gate mid-check and lets two `_maybeRefuse` calls
  /// race the same position. The guard below and the `finally` in
  /// [_maybeRefuse] both compare against `_gen` so only the call that
  /// actually owns the flag for the CURRENT generation may release it — no
  /// gen-bumping call site (newGame, undo, ...) needs to remember to reset
  /// this itself; the comparison self-heals the moment `_gen` moves on.
  bool _refusalPending = false;
  int? _refusalPendingGen;

  /// Set by [_maybeRefuse] when a move is refused, for the UI to say so — a
  /// silent snap-back reads as a misclick, not a refusal. Cleared the moment
  /// any move actually commits, or a new game starts.
  String? refusalMessage;

  /// The position a refusal check is deliberating over: the move the player
  /// just let go of, shown on the board for the length of the check so the
  /// piece lands where they dropped it instead of snapping back to an
  /// unchanged board while a search runs. Null whenever no check is in flight.
  ///
  /// PRESENTATIONAL ONLY, and deliberately so — no [MoveRecord], no clock
  /// press, no [_apply]. There is nothing to roll back if the move is refused:
  /// this clears and the board re-syncs to [position], which never moved. The
  /// board hands the pending position `PlayerSide.none`, matching the
  /// [_refusalPending] gate in [playerMove] — you cannot move again until the
  /// check answers either way.
  String? pendingFen;
  NormalMove? pendingMove;

  /// Both of the transient refusal-mode surfaces at once: the message about
  /// the last refused move and the board's optimistic view of the one being
  /// checked. Every path that moves the conversation on (new game, undo,
  /// redo, browsing) drops both — a message about a move you are no longer
  /// looking at is noise, and a pending position that outlives its check
  /// would leave the board showing a move that never happened.
  void _clearRefusalUi() {
    refusalMessage = null;
    refusalDrop = null;
    refusalRefutationUci = null;
    _refusalAfterFen = null;
    pendingFen = null;
    pendingMove = null;
  }

  /// What the refused move would have cost, in win chance. Set on every
  /// refusal, in every mode — it is the number the refusal is a judgement
  /// about, and withholding it while still refusing tells the player the move
  /// is bad without telling them how bad, which is the least useful half.
  double? refusalDrop;

  /// The opponent's punishing reply to the refused move, as a uci — the "why".
  ///
  /// Set ONLY when help is not being withheld and the game is not rated. It is
  /// the same bargain practice strikes with its refutation preview (#215): it
  /// names what the wrong move RUNS INTO, never what the right move is, so it
  /// answers "why not" without answering "what instead".
  ///
  /// Deliberately NOT the grade's bestPv, which is exactly the best move.
  String? refusalRefutationUci;

  /// The position the refused move would have REACHED, kept because
  /// [refusalRefutationSan] has to render the reply against it.
  ///
  /// Not [pendingFen], which is cleared the moment the board snaps back — so a
  /// getter reading that resolved to null every time, in exactly the state the
  /// message is on screen.
  String? _refusalAfterFen;

  /// [refusalRefutationUci] as SAN, for a line a player can read.
  ///
  /// Rendered from the position the refused move would have REACHED, not the
  /// live one — the refutation is the opponent's reply there, and naming it
  /// against the current board would print a different move or none at all.
  String? get refusalRefutationSan {
    final uci = refusalRefutationUci;
    final after = _refusalAfterFen;
    final chess = _chess;
    if (uci == null || after == null || chess == null) return null;
    try {
      return chess.san(after, uci);
    } catch (_) {
      return null;
    }
  }

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
  /// Deliberately [blind], the SETTING, and not [hidingHelp]. The question
  /// here is whether help was AVAILABLE to you while you played — which is
  /// what decides whether the game counts for your rating — not whether it
  /// happened to be on screen at some instant.
  ///
  /// Honestly: at the ONLY call site the two are equivalent, so no test can
  /// tell them apart. [playerMove] returns early on `gameOver`, so the
  /// `!gameOver` clause is always true where this is read, and the call site
  /// already guards on `botEnabled` — leaving `!blind` either way. This is
  /// therefore about keeping two different questions from collapsing into one
  /// name, not about a live difference. It becomes a real one the moment
  /// anything reads `_assisted` from somewhere a finished game can reach.
  bool get _assisted => !blind;

  GameController(this._arbiter, this._bot, this._grading, this._settings,
      [this._db,
      this._practice,
      ChessApi? chessApi,
      this._customEngines,
      this._review = false]) {
    _chess = chessApi;
    if (chessApi != null) linesTree = LinesTreeModel(chessApi);
    _lastSettingsSig = _settingsSig(); // see the field: NOT a late initializer
    _syncRetro();
    _settings.addListener(_onSettings);
    // Not for a review board: it has no game open yet, so this queued a second
    // full depth-22 / MultiPV-5 search of the START position on the one shared
    // engine at boot, whose result nobody would ever read. The provider is
    // created eagerly (KeyboardControls reads it in the first shell build), so
    // this cost was paid on every launch whether or not Review was opened.
    // showReview asks for the real position when a game is opened.
    if (!_review) _analysisFor(position.fen);
    _maybeBotTurn();
  }

  static String _newSeed() => 'm${Random().nextInt(1 << 30)}';

  /// This controller drives the Review tab over a FINISHED game rather than a
  /// live one (#194). It is a second instance, constructed with no db and no
  /// practice controller, so the save path (`_saveGame` returns on a null db),
  /// the rating and the clock cannot fire on it at all.
  ///
  /// What the flag itself buys is independence from [SettingsStore]: the
  /// settings-derived getters below are how a controller learns it is a bot
  /// game, whose colour the player has, and whether blind mode is on — all of
  /// which belong to the LIVE game and would otherwise leak into a review of
  /// some other game entirely. Forcing them here is what makes review an
  /// analysis board over the record instead of the current game wearing the
  /// record's positions.
  final bool _review;
  bool get reviewing => _review;

  /// The colour the reviewed game is read from — the human's side, or White
  /// for an import that has no "you" in it. Orientation only; there is no
  /// player to be on the move in a finished game.
  String _reviewColor = 'w';

  String get playerColor => _review ? _reviewColor : _settings.playerColor;

  /// False in review: a finished game has no bot to move, which is what makes
  /// [personaToMove] null, [isPlayerTurn] true, `_maybeBotTurn` return at its
  /// first line, and the board offer PlayerSide.both — the analysis board's
  /// own semantics, arrived at by the analysis board's own route.
  bool get botEnabled => !_review && _settings.botEnabled;

  /// The brain's built-in roster, plus any custom engines the player added —
  /// but only where they can actually run (native desktop), so the picker never
  /// offers one it would have to stand in for.
  List<Persona> get rosterPersonas => [
        // Filtered by family, not merely by the brain's nativeOnly flag: that
        // flag says "needs the native shell", and Dala needs one AND has no
        // implementation. Offering it would put three personas in the sheet
        // that quietly play as a Stockfish stand-in.
        ..._bot
            .personas(native: wantsNativeRoster)
            .where((p) => playableFamilies.contains(p.family)),
        if (_customEngines != null && CustomEngineRunner.supported)
          ..._customEngines.personas,
      ];

  // Each side is a bot (a persona) or the human (null). The source of truth is
  // the settings; these resolve the ids to personas.
  // Null in review for the same reason botEnabled is false there: the live
  // game's opponent has nothing to do with the archived game on the board, and
  // a non-null persona here would put a bot on the move in a finished game.
  Persona? get whitePersona =>
      _review ? null : _personaOf(_settings.whitePersonaId);
  Persona? get blackPersona =>
      _review ? null : _personaOf(_settings.blackPersonaId);
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
  Persona? personaFor(String? id) {
    if (id == null) return null;
    // Custom engines resolve fresh (an edit changes the persona), never cached;
    // the brain's immutable personas are cached.
    final custom = _customEngines?.byPersonaId(id);
    if (custom != null) return custom.toPersona();
    return _personaCache.putIfAbsent(id, () => _bot.personaById(id));
  }

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

  // The rule-forced draw dartchess's stateless Position cannot see (#186),
  // cached by (generation, ply) so it recomputes after any move / undo / redo /
  // new game but not on every gameOver read.
  int? _drawCacheGen;
  int? _drawCachePly;
  String? _drawCache;
  String? get _drawByRule {
    if (_drawCacheGen == _gen && _drawCachePly == moves.length) return _drawCache;
    _drawCacheGen = _gen;
    _drawCachePly = moves.length;
    return _drawCache = _ruleDrawReason();
  }

  bool get gameOver =>
      position.isGameOver || _resigned || _flagged != null || _drawByRule != null;
  /// Whose colour sits at the bottom of the board (follows orientation).
  bool get whiteAtBottom => (playerColor == 'w') != flipped;
  /// The position actually on screen: a browsed ply, a hover preview, or live.
  String get displayFen => browseFen ?? previewFen ?? position.fen;

  String get statusLine {
    // _resigned before _flagged, matching [_result]: if both were somehow set,
    // the two must not name different winners.
    if (_resigned) {
      return 'You resigned — ${playerColor == 'w' ? 'Black' : 'White'} wins';
    }
    final flag = _flagged;
    if (flag != null) {
      final loser = flag == ClockSide.white ? 'White' : 'Black';
      final winner = flag == ClockSide.white ? 'Black' : 'White';
      return '$loser ran out of time — $winner wins';
    }
    if (position.isCheckmate) {
      final winner = position.turn == Side.white ? 'Black' : 'White';
      return 'Checkmate — $winner wins';
    }
    if (_drawByRule != null) return _drawByRule!;
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
        // Recorded BEFORE the skip, not inside it. Gating the bookkeeping too
        // let the remembered signature go stale on a review board with no game
        // open: toggle threats off while it is closed and the skip leaves the
        // old signature, so toggling them back ON later compares equal and
        // never probes — the arrow stays missing until the cursor moves.
        _lastOverlaySig = overlaySig;
        // `_tree != null` for the review board: without a game open there is
        // nothing to probe, and a threat probe OUTRANKS analysis — so toggling
        // overlays on the Play tab preempted the live board's own search on
        // behalf of a review board nobody had opened.
        if (_review && _tree == null) {
          notifyListeners();
          return;
        }
        _probeThreat();
        // Toggling blind changes which nodes the tree lays out (#147). The
        // model only recomputes y on ingest, and analysis stops at depth 22 /
        // 3s — without this, flipping blind after it settled would leave the
        // last sighted layout on screen, ghost positions and all.
        _syncTree();
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
  /// [rated] marks the game as one that counts (see [_rated]), and applies or
  /// releases the rated preset — blind on, arrows/threats/control off — via
  /// [_applyRatedPreset] and [_restoreAfterRated].
  ///
  /// That suppression deliberately lives HERE and not at the New Game sheet's
  /// Start button, where it started. Those are the player's persistent
  /// settings, so applying them somewhere that never runs again is precisely
  /// how a single rated game left blind on and three overlays off across the
  /// whole app, Review included, until the player hunted down four switches.
  /// This method is the only place that runs at both ends: it also runs when
  /// the next casual game starts, which is when they can be handed back.
  ///
  /// Defaulting to false is what makes every other caller start a casual game
  /// — which is the right answer for all of them.
  void newGame(
      {String? fromFen,
      bool rated = false,
      bool refuseBlunders = false,
      TimeControl? timeControl}) {
    // The review board has no game to start, and this is the last unguarded
    // bumpGeneration on it — which voids EVERY queued and running search of
    // every priority on the arbiter shared with the live game, including a bot
    // move in flight. undo/redo/resign are already guarded; this was the trap
    // left for whoever wires the next control into the Review tab.
    if (_review) return;
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
    // The preset lives HERE, not at the New Game sheet's Start button, because
    // this is the only place that also runs when the mode ends — a suppression
    // applied somewhere that cannot undo it is how the switches got stranded.
    if (rated) {
      _applyRatedPreset();
    } else {
      _restoreAfterRated();
    }
    _refuseBlunders = refuseBlunders;
    _refusedMoves = 0;
    _refusalAttempts.clear();
    _refusalPending = false;
    _refusalPendingGen = null;
    _clearRefusalUi();
    _clock?.dispose();
    _flagged = null;
    _clock = rated && timeControl != null
        ? (ChessClock(timeControl)
          ..onFlag = (side) {
            // A flag on an already-decided game is a no-op. The clock is
            // stopped at every ending so its ticker cannot get here — but a
            // flag arriving by any other path must not overwrite a mate, a
            // draw or a resignation that already stands.
            if (gameOver) return;
            // A result, so it archives like one. The board is still legal,
            // exactly as with a resignation.
            _flagged = side;
            // As in [resign]: the veil lifts at gameOver, and #147 bakes blind
            // into the tree's LAYOUT, which is only recomputed on ingest.
            _syncTree();
            _gen++;
            _arbiter.bumpGeneration();
            botThinking = false;
            notifyListeners();
            // NOT while a move is being applied. [_apply] presses the clock
            // after the move is on the board (#238) but BEFORE it registers
            // that move's grade pipeline in _pendingGrades — and _saveGame
            // waits on exactly that list for the labels. Saving from here
            // therefore archived the flagging move with `label` absent and
            // `depth: 0`, while the live record got its grade a moment later,
            // and the accuracy figures were computed over the blank. It is
            // the only ending that got this wrong: mate and the draws save
            // from _apply's own tail, which runs below the registration, and
            // an ordinary ticker flag is not inside _apply at all.
            //
            // _apply's tail saves for us — it already does, on `gameOver`,
            // which this has just made true.
            if (!_applying) _saveGame();
          })
        : null;
    _undoWasCounted.clear();
    _saved = false;
    _lastSavedGame = null;
    gameSeed = _newSeed();
    _analysis.clear();
    _settledFens.clear();
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

  /// One tap from the recap into an identical game with the sides swapped
  /// (#212) — lichess/chess.com convention, and the whole point of the
  /// button: New Game re-prompts for opponent and settings every time,
  /// Rematch re-prompts for nothing. Guarded by [canRematch]; a no-op call
  /// (e.g. a stale button reference on a review board) is silently ignored
  /// rather than asserting, the same posture [resign] takes.
  ///
  /// Follows the New Game sheet's own documented sequence at its Start
  /// button: [SettingsStore.setPlayers] can itself trigger a restart through
  /// the settings listener (`_onSettings`), and that restart is always
  /// unrated — so the explicit [newGame] call below, carrying the real
  /// rated/timeControl, has to run LAST or its result would be immediately
  /// clobbered. Read the swap and the rated/clock state from `this` and
  /// `_settings` BEFORE calling setPlayers, for the same reason: nothing
  /// downstream of setPlayers may be trusted to still hold the values this
  /// game just finished with.
  ///
  /// Rated carries over on purpose, unlike the sheet's own Rated switch
  /// (which resets to unticked every time the sheet opens — see the comment
  /// on [_rated]'s declaration). That reset exists to stop a forgotten
  /// sticky checkbox from quietly rating games the player never chose to
  /// rate; Rematch is not that. It is one explicit tap, taken with the
  /// just-finished result still on screen, so continuing under the same
  /// terms is exactly as deliberate as re-ticking the box would be — and a
  /// rematch of a CASUAL game stays casual for the same reason in reverse:
  /// the tap carries the previous choice forward, it does not invent a rated
  /// one. [refuseBlunders] is NOT carried — it is off by default in
  /// [newGame] like every other caller, because #167 gives it no comparable
  /// "same terms" claim: it is a practice toggle for THIS attempt, not a
  /// property of the match being continued.
  void rematch() {
    if (!canRematch) return;
    final white = _settings.whitePersonaId;
    final black = _settings.blackPersonaId;
    final wasRated = _rated;
    // Only a rated game ever carries a clock (see newGame's own
    // `rated && timeControl != null` guard) — a casual rematch has nothing
    // to carry regardless of what _clock holds over from before.
    final timeControl = wasRated ? _clock?.control : null;
    // The rated preset comes back with the flag, because newGame applies it
    // (see _applyRatedPreset). Without that, a rated rematch was born
    // un-ratable: the switches are handed back when a game ends, so the next
    // one would start with help on, `_assisted` true at the first move, and
    // playerElo dropping the game — a game that says "rated", shows nothing,
    // and cannot count.
    // Before newGame, and newGame last: newGame's own _maybeBotTurn has to
    // see the swapped personas, or the wrong side gets the opening move.
    // (An earlier version of this comment claimed setPlayers itself triggers
    // an unrated restart through the settings listener. It does not —
    // _onSettings' changed-signature branch calls _syncRetro and nothing
    // else, and says so. The ordering is still required, for the reason
    // above.)
    _settings.setPlayers(white: black, black: white);
    newGame(rated: wasRated, timeControl: timeControl, fromFen: _startFen);
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

  // Both false in review: there is no move of yours to take back in someone
  // else's finished game, and `moves` there is the archive rather than a line
  // being built — see [showReview] on why nothing may mutate it.
  bool get canUndo =>
      !_review &&
      !botThinking &&
      !_rated && // #168: no takebacks in a rated game
      (botEnabled
          ? moves.any((m) => m.color == playerColor)
          : moves.isNotEmpty);
  bool get canRedo =>
      !_review && _redoStack.isNotEmpty && !botThinking && !_rated;

  /// Whether the recap offers Rematch. Requires an actual opponent as well
  /// as [gameOver]: analysis (both sides human) has nothing for the sides
  /// swap to do — swapping two nulls is a no-op — and "rematch" promises a
  /// continuation against SOMEONE, which that mode never had.
  ///
  /// AND the finished game has to be finished with. [newGame] bumps the
  /// generation, which makes an in-flight [_gradePipeline] return before it
  /// writes the backfilled label and before the practice-collect guard — so a
  /// fast tap here threw away the grade and the puzzle for the very move that
  /// ended the game, which is the one most worth keeping. That race has always
  /// existed (any New Game does it), but Rematch is the first one-tap path
  /// sitting directly under the result, which turns it from rare into normal.
  /// The wait is the length of one grade, and [_saveGame] is already waiting
  /// on the same futures.
  bool get canRematch =>
      !_review && gameOver && botEnabled && _pendingGrades.isEmpty;

  /// Undo the last player move (and the bot reply on top of it);
  /// on the analysis board, one ply at a time.
  /// Concede the game: archive it as a loss and stop play.
  ///
  /// Only in a real game — the analysis board has no opponent to concede to —
  /// and only while one is in progress. Saving here rather than waiting for
  /// something else to notice, because nothing else will: no move follows a
  /// resignation.
  void resign() {
    // gameOver, not position.isGameOver: a game already ended by a flag must
    // not also be resigned — that stacked _resigned on top of _flagged and the
    // two disagreed about who won.
    if (!botEnabled || gameOver || moves.isEmpty) return;
    _resigned = true;
    // The veil lifts at gameOver, and #147 bakes blind into the tree's LAYOUT
    // rather than its paint — the model only recomputes y on ingest. Without
    // a resync here the pane draws every node at the default y the blind
    // layout left them on, stacked. _apply does this for mate and the draws;
    // resign and flag-fall are the two endings that bypass it.
    _syncTree();
    _clock?.stop();
    _gen++; // a bot turn in flight must not answer a game that has ended
    _arbiter.bumpGeneration();
    botThinking = false;
    notifyListeners();
    _saveGame();
  }

  void undo() {
    if (_review) return; // see canUndo
    _browsePly = null;
    // A refusal message describes a specific just-attempted move; taking a
    // move back moves the conversation on regardless of whether refusal mode
    // is even the reason (review follow-up, #167/#224).
    _clearRefusalUi();
    // A rated game does not permit takebacks — that is part of what "rated"
    // means (#168), and it is also what stops the clock and the position from
    // desyncing: there is no coherent way to un-press a chess clock, so the
    // honest answer is to not take the move back at all.
    if (moves.isEmpty || botThinking || _rated) return;
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
    _lastSavedGame = null; // the old record no longer matches the live game
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
    if (_review) return; // see canUndo
    _browsePly = null;
    _clearRefusalUi(); // see undo
    if (_redoStack.isEmpty || botThinking || _rated) return;
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
    // In review a move does not append to the game — it branches the tree
    // (#196). `moves` stays the archived mainline; the variation lives beside
    // it and the played line is always still there to come back to.
    if (_review) {
      reviewPlay(move, san);
      return;
    }
    // _refusalPendingGen == _gen, not just _refusalPending: a stale pending
    // flag left by an abandoned generation's check must not block moves in
    // the CURRENT one (see the field docs on _refusalPending).
    final refusalPending = _refusalPending && _refusalPendingGen == _gen;
    if (!isPlayerTurn || botThinking || refusalPending || gameOver) return;
    // the sample point: what the board was showing at the moment a human move
    // was committed (see [_botHintsUsed]). Bot replies come through _apply
    // directly, so only human moves are sampled.
    if (botEnabled && _assisted) _botHintsUsed = true;
    if (_refuseBlunders && botEnabled) {
      unawaited(_maybeRefuse(move, san));
      return;
    }
    _apply(move, san);
    _maybeBotTurn();
  }

  /// Refusal-mode gate (issue #167): grades [move] BEFORE it commits. If the
  /// drop clears [SettingsStore.collectThreshold] and the player has not
  /// already struck out [kMaxRefusalAttempts] times at this position, the
  /// move is refused — collected as a practice puzzle exactly like a played
  /// mistake would be, via a hand-built stored-move map since no [MoveRecord]
  /// ever exists for it — and [_apply] is never called, so there is nothing
  /// to roll back and no conflict with [undo]'s botThinking guard (the bot
  /// never gets a turn here). The board shows the attempted move meanwhile via
  /// [pendingFen], which is a view of it and not a commit of it, and reverts
  /// to [position] — which never advanced — the instant the refusal lands.
  ///
  /// Otherwise the move is allowed through exactly as it would be without
  /// refusal mode. This includes the FAIL-OPEN case: if the child search
  /// never reaches depth 10 within the cap, [_computeGrade] returns an
  /// un-backfilled grade, whose `evalPawns`/`mate` are null — computing a
  /// drop from that would read as a nonsense number (winChance(null, null)
  /// is 50, not "unknown"), so an un-backfilled grade is treated as "no
  /// drop known" and the move goes through. Refusal mode must never leave a
  /// human move hanging indefinitely on a slow engine, and must never refuse
  /// (or silently allow) a blunder on a number it does not actually have.
  Future<void> _maybeRefuse(NormalMove move, String san) async {
    final gen = _gen;
    _refusalPending = true;
    _refusalPendingGen = gen;
    // Whether this move's fate is settled — refused, or handed to [_apply].
    // Read by the catch below, which must fail open on a move nothing has
    // decided yet and MUST NOT touch one that is already decided: the refusal
    // path awaits a database write after the refusal is on screen, and
    // applying the move there would commit the very move it just refused,
    // under its own "that costs -18%" message.
    var decided = false;
    try {
      final fenBefore = position.fen;
      final uci = move.uci;
      final color = position.turn == Side.white ? 'w' : 'b';
      final candidateFen = position.playUnchecked(move).fen;
      final attempts = _refusalAttempts[fenBefore] ?? 0;

      // Everything above here is synchronous, so this paints in the frame the
      // player let go of the piece: the check is fast now, but no search is
      // instant, and a board that sits unchanged while one runs reads as a
      // dropped move rather than a considered one.
      refusalMessage = null; // the previous attempt's, not this one's
      pendingFen = candidateFen;
      pendingMove = move;
      notifyListeners();

      List<EngineMove>? refutation;
      final grade = await _computeGrade(
        ply: moves.length + 1,
        fenBefore: fenBefore,
        san: san,
        uci: uci,
        color: color,
        fenAfter: candidateFen,
        gen: gen,
        onChild: (c) => refutation = c,
        cap: const Duration(milliseconds: 2500),
      );
      if (gen != _gen) return; // superseded (undo/new game) while we waited

      final drop =
          (grade != null && grade.backfilled) ? _wcDrop(grade) : 0.0;
      // `grade != null` here, not just `drop >= threshold`: the two happen to
      // coincide today only because collectThreshold's UI floor is 5 (never
      // 0), so a null grade's drop-of-0.0 can never clear it — correct by
      // luck, not by construction. Spelling it out means the `grade!`
      // unwraps below stay safe even if that floor is ever lowered.
      if (grade != null &&
          drop >= _settings.collectThreshold &&
          attempts < kMaxRefusalAttempts) {
        decided = true;
        _refusalAttempts[fenBefore] = attempts + 1;
        _refusedMoves++;
        final left = kMaxRefusalAttempts - attempts - 1;
        refusalDrop = drop;
        // The cost is named in every mode, rated and blind included. The
        // refusal already tells the player the move is bad; withholding the
        // size of it tells them that and nothing more, which is the least
        // useful half of the judgement. It is also what makes the message
        // worth showing at all in the rated shell, where there are no panels
        // and this line is all there is (#231).
        final cost = '−${drop.round()}%';
        refusalMessage = left > 0
            ? 'That costs $cost — try again ($left left)'
            : 'That costs $cost — one more try lets it through';
        // The WHY, and only where help is not being withheld. The first ply of
        // the opponent's best line from the position the move would have
        // reached: what it runs into, never what to play instead.
        _refusalAfterFen = candidateFen;
        refusalRefutationUci = (!hidingHelp && !_rated)
            ? (refutation?.isNotEmpty ?? false)
                ? refutation!.first.pv.firstOrNull
                : null
            : null;
        // Snap the board back NOW, with the message — not after the collect
        // below, which is a database write the player should not be watching
        // their own piece hover through.
        pendingFen = null;
        pendingMove = null;
        notifyListeners();
        final practice = _practice;
        if (practice != null) {
          final storedMove = {
            'ply': moves.length + 1,
            'san': san,
            'uci': uci,
            'color': color,
            'fenBefore': fenBefore,
            'fenAfter': candidateFen,
            'evalPawns': grade.evalPawns,
            'mate': grade.mate,
            'pctBest': grade.pctBest,
            'wcDrop': drop,
            'depth': grade.depth,
            if (grade.label != null) 'label': grade.label,
            'bestSan': grade.bestSan,
            'bestUci': grade.bestUci,
            if (grade.explanation != null)
              'explanation': grade.explanation!.raw,
          };
          final prevUci = moves.isNotEmpty ? moves.last.uci : null;
          await practice.maybeCollect(storedMove, setupUci: prevUci);
        }
        notifyListeners();
        return;
      }

      _refusalAttempts.remove(fenBefore);
      // Cleared before [_apply], not after: _apply notifies, and it must not
      // paint a frame in which the move is both committed and still pending.
      _clearRefusalUi();
      // Before the call, not after: a throw from inside [_apply] leaves the
      // move half-applied, and re-applying it is worse than not.
      decided = true;
      _apply(move, san);
      _maybeBotTurn();
    } catch (e, st) {
      // FAIL OPEN, and this is the whole point of the branch. Every await
      // above crosses the JS bridge or the arbiter, and this method is
      // fire-and-forget with no zone guard — so a throw skipped _apply
      // entirely and the `finally` then cleared pendingFen on the way out.
      // The piece snapped home, no message, no attempt counted: the player's
      // move simply vanished, which is indistinguishable from a misclick and
      // is exactly what pendingFen exists to prevent. With a dead engine EVERY
      // move vanished, for as long as it stayed dead — while the same dead
      // engine with refusal mode OFF still let the game be played.
      //
      // _maybeBotTurn has carried this catch since it was written, for the
      // same reason and with the same wording. This one was missing it.
      //
      // The move goes through. Refusing needs a number, and a thrown search
      // has not got one — the doc above already commits to letting a move
      // through rather than refusing on a number we do not actually have, and
      // there is no weaker version of that promise for the case where the
      // engine threw instead of merely being slow.
      debugPrint('[refuse] check failed, letting the move through: $e\n$st');
      // `gen == _gen` as well as `!decided`, and the success path has had that
      // guard all along (see the `if (gen != _gen) return` above). Failing
      // open must not open onto a DIFFERENT game: a throw landing after
      // newGame or undo would otherwise apply a move from the abandoned
      // generation to the live board, and call _maybeBotTurn so the bot
      // answers it. Reachable in exactly the situation that makes this catch
      // necessary — a dead engine means moves keep failing, which is what
      // makes a player start a new game in the middle of a check.
      if (!decided && gen == _gen) {
        _clearRefusalUi();
        _apply(move, san);
        _maybeBotTurn();
      }
    } finally {
      // Only release the flag if this call still owns it for the CURRENT
      // generation — a stale call for an abandoned generation must not clear
      // a fresh call's in-flight flag out from under it, and must not tear
      // down the board view that check is showing. Every gen-bumping path
      // (newGame, undo, redo, browse) clears the pending view itself.
      if (_refusalPendingGen == gen) {
        _refusalPending = false;
        if (pendingFen != null) {
          pendingFen = null;
          pendingMove = null;
          notifyListeners();
        }
      }
    }
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
    _applying = true;
    try {
      _applyInner(move, san);
    } finally {
      _applying = false;
    }
  }

  void _applyInner(NormalMove move, String san) {
    // Who will have pressed, read BEFORE playUnchecked flips the turn — but
    // the press itself happens after the move is on the board, further down.
    //
    // It used to press here, first thing, and that was the bug in #238.
    // [ChessClock.press] calls `_fall` SYNCHRONOUSLY when the mover is already
    // through zero (the <=100ms window between the time running out and the
    // ticker polling), and `_fall` runs `onFlag`, which archives the game. All
    // of it ran while the move that triggered it was still unplayed: `moves`
    // did not have it and `position` had not advanced, so the archive was
    // written one move short of the board in front of the player — and `_saved`
    // was then true, so the `_saveGame()` at the bottom of this method, which
    // would have written the right thing, returned early. The board said Nf3;
    // the archive said the game ended after e5. Results feed
    // brain/playerElo.ts, so that is a game rated on a position that never
    // happened.
    final c = _clock;
    final mover = c == null
        ? null
        : ClockSide.fromChar(position.turn == Side.white ? 'w' : 'b');
    final firstMove = moves.isEmpty;
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
    // NOW the clock, with the move on the board — see the note at the top of
    // this method. First move starts it rather than pressing: there is nothing
    // banked yet.
    //
    // A second consequence, and an improvement rather than a side effect: a
    // move that ENDS THE GAME now ends it, rather than being overwritten by a
    // flag arriving in the same instant. `onFlag` opens with `if (gameOver)
    // return`, and by this point `position.isGameOver` — and `_drawByRule` —
    // are already computed against the new position. Pressed before the move,
    // gameOver was still false and the flag always won.
    //
    // For mate, stalemate and insufficient material this is simply the rule
    // (FIDE 5.2, 6.9): a move completed before the flag falls is a move, and
    // it ends the game. For threefold and the 50-move rule it is arguable —
    // both are CLAIMS under FIDE, and a fallen flag would ordinarily beat an
    // unclaimed one — but this app auto-enforces them by an explicit decision
    // (see _ruleDrawReason), so treating them as ending the game here is
    // consistent with that choice rather than a new one.
    if (c != null && mover != null) {
      if (firstMove) c.start(mover);
      c.press(mover);
    }
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
      ..whenComplete(() {
        _pendingGrades.remove(pipeline);
        // So [canRematch] can go true again: the recap's button is disabled
        // while a grade is in flight, and nothing else notifies when the last
        // one drains.
        notifyListeners();
      });
    _pendingGrades.add(pipeline);
    if (gameOver) {
      // The ticker keeps counting otherwise, and eventually flags — rewriting a
      // decided game (a mate, a draw) as a loss on time on the live board.
      _clock?.stop();
      _saveGame();
    }
  }

  // Event-driven: fires the instant a streamed update crosses depth 10,
  // independently of _computeGrade's own (uncapped, post-commit) await on
  // _analysisFor's future — the latency win the comment at this call site
  // describes. _computeGrade's tail ends up recomputing the same backfill
  // once that future finally resolves, unaware this already ran; record.grade
  // is identical either way, and it was already a redundant JS-bridge call in
  // the pre-_computeGrade code this replaced, not something new here.
  void _earlyBackfill(MoveRecord record, List<EngineMove> lines, int gen) {
    if (gen != _gen || lines.isEmpty || lines.first.depth < 10) return;
    final grade = record.grade;
    if (grade == null || grade.backfilled) return;
    record.grade = _grading.backfillGrade(grade, lines);
    notifyListeners();
  }

  // ---- app lifecycle (#234) ----

  /// The app stopped being the active window — another tab, another app, a
  /// locked phone. Freeze a running clock.
  ///
  /// DECIDED (Ryan, 2026-07-27): pause generously. "This is just a practice
  /// app." There is no opponent to wrong here — the rating is the player's own
  /// estimate of themselves — and losing on time because a phone call arrived
  /// measures the phone call. So this fires on every state that is not
  /// `resumed`, including a mere window blur, rather than only on a hard
  /// suspend. It reverses what chess_clock.dart's header used to argue; that
  /// paragraph has been rewritten rather than left contradicting this.
  ///
  /// Time already spent still counts: [ChessClock.pause] banks the running
  /// side first, and falls the flag if it had already run out before we got
  /// here. Backgrounding cannot rescue a game that was already lost.
  ///
  /// No `gameOver` guard, and that is deliberate rather than an omission. Both
  /// of these had one; a mutation showed neither could ever fire, because
  /// every path that ends a game already stops the clock (`_apply`'s tail,
  /// [resign], and `_fall` for a flag) and [ChessClock] then refuses both calls
  /// on `_running == null`. A guard that cannot be reached is worse than none:
  /// it reads as the thing keeping the invariant when the real keeper is
  /// somewhere else.
  void pauseForBackground() => _clock?.pause();

  /// Back in front of the player: unfreeze.
  ///
  /// Resumes immediately rather than waiting for a move, which is what every
  /// other clock does on return. No UI indication of the paused state is
  /// needed — by definition nobody is looking at it while it holds.
  void resumeFromBackground() => _clock?.resume();

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
    if (_drawByRule != null) return '1/2-1/2';
    if (position.isGameOver) return '1/2-1/2';
    return '*';
  }

  /// Archive the finished game — the web's saveCurrentGame, same StoredGame
  /// shape (JSON-compatible with the IndexedDB store for future import).
  Future<void> _saveGame() async {
    // Every path that ends a game funnels through here — mate, resignation and
    // flag-fall alike — so this is where the rated mode hands the switches
    // back. Before the early returns below: a casual game, or one with nothing
    // to archive, still ended.
    _restoreAfterRated();
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
    final refused = wasBotGame ? _refusedMoves : 0;
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
      // Same convention, separate field: a refusal (issue #167) is not a
      // takeback — nothing was ever committed to take back — so it gets its
      // own count rather than folding into botUndos.
      if (refused > 0) 'refusedMoves': refused,
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
    // Hold the record and announce it: the game-over recap watches this
    // controller, so setting it here is what lights up "Review this game".
    _lastSavedGame = record;
    notifyListeners();
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
        _ensureMaia();
        // Retry before substituting. The one common reason move() returns null
        // is the first call timing out mid-download — 3.5MB of weights plus
        // ~13MB of WebAssembly, which a slow phone can push past the 90s cap.
        // By the time it times out the download has almost always finished, so
        // a second call answers with a real Maia move. Substituting on the
        // first null made a slow connection show a Stockfish stand-in for a
        // game that was actually Maia from move two on — and the badge is
        // sticky per game, so it never cleared. A stand-in should mean the
        // net genuinely will not run here, not that it was still arriving.
        String? uci;
        final startGen = _gen;
        for (var attempt = 0; attempt < 2 && uci == null; attempt++) {
          // Do not retry into a game that moved on under us (a new game, an
          // undo) or a disposed engine.
          if (attempt > 0 && (startGen != _gen || _maia == null)) break;
          uci = await _maia!.move(
            _fenHistory(),
            band: band,
            temperature: p.maiaTemp ?? 0,
          );
        }
        if (maiaProgress != null) {
          maiaProgress = null;
          notifyListeners();
        }
        if (uci != null) {
          return (uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines), standIn: false);
        }
      }
      debugPrint('[bot] maia had no move after a retry; falling back');
    }
    if (p.family == 'chessgpt') {
      // A language model over MOVETEXT. It cannot be handed a FEN — a position
      // with no history is off its distribution and it answers with noise — so
      // this passes the SAN list, which is the one thing this controller has
      // and the arbiter's engines never need.
      final variant = p.chessgptVariant;
      // Only from the standard start. movesToPgn numbers from 1 and takes
      // index 0 to be White, so a game begun at an arbitrary FEN — newGame's
      // fromFen, which the New Game sheet offers for any legal position — is
      // rendered as a fabricated game: a board 21 moves deep with Black to
      // move gets prompted ";1.Nxd4 Bxd4 ", wrong side, wrong number, a game
      // that never happened. The model answers plausibly-looking nonsense,
      // fails legality six times and becomes a Stockfish stand-in with nothing
      // saying why. Falling through here reaches the same stand-in, honestly.
      //
      // This is the boundary chessgpt_engine_io's header warns about at
      // length: the input is MOVETEXT, and a position is not one.
      final fromStart = _startFen == Chess.initial.fen;
      if (ChessGptEngine.supported && variant != null && fromStart) {
        final engine = _chessGpt[variant] ??= ChessGptEngine(variant);
        // Snapshot the position: pickMove awaits a native session build and up
        // to six sampling rounds, and `position` is mutable state that an undo
        // or a new game can move under us. Parsing the answer against the
        // board it was asked about is the difference between a stale move and
        // an illegal one.
        final at = position;
        final pgn = ChessGptEngine.movesToPgn(
          [for (final m in moves) m.san],
          whiteToMove: at.turn == Side.white,
          fullmove: at.fullmoves,
        );
        // Legality is the caller's job: the model emits characters, and
        // nothing in its objective distinguishes a legal move from a
        // plausible-looking illegal one. An illegal sample is retried with
        // temperature inside pickMove, never swapped for a random legal move —
        // a random move is a different player wearing this one's name.
        //
        // parseSan answers both questions at once — null is "not legal here",
        // and a Move is already the thing the rest of this wants.
        final san = await engine.pickMove(pgn,
            isLegalSan: (s) => at.parseSan(s) != null);
        final uci = san == null ? null : at.parseSan(san)?.uci;
        if (uci != null) {
          return (
            uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines),
            standIn: false
          );
        }
      }
      if (!fromStart) {
        debugPrint('[bot] chessgpt needs movetext, and this game began from a '
            'FEN — playing the stand-in instead');
      } else {
        debugPrint('[bot] chessgpt had no move; falling back to the engine');
      }
    }
    if (p.family == 'custom') {
      // A player-added UCI engine, in its own process — never the arbiter's
      // queue, like retro/garbo. Its config (path, movetime, whether to cap its
      // strength) comes from the store; the process is built on first use and
      // reused. Any failure — a binary that will not start, a dead search —
      // falls through to the Stockfish stand-in below, the same safety net
      // every other opponent family has.
      final cfg = _customEngines?.byPersonaId(p.id);
      if (cfg != null && CustomEngineRunner.supported) {
        // Rebuild if the player edited the binary path since we spawned it —
        // otherwise the running process is the old engine.
        var runner = _customRunners[cfg.id];
        if (runner != null && runner.path != cfg.path) {
          runner.dispose();
          runner = null;
        }
        runner ??= _customRunners[cfg.id] = CustomEngineRunner(cfg.path);
        // Clamp the (possibly round-hundred) label back into the engine's real
        // UCI_Elo range — a "1300" the player picked drives an engine whose
        // floor is 1320. A hand-added engine (no catalog entry) is sent as-is.
        final capEntry = catalogEntryById(cfg.id);
        final uci = await runner.move(fen,
            elo: cfg.limitElo ? (capEntry?.clampElo(cfg.elo) ?? cfg.elo) : null,
            movetimeMs: cfg.movetimeMs,
            // The style option, for an engine that has styles (Rodent's
            // PersonalityFile, BrainLearn's MCTS). Null for a plain engine.
            setoption: _customEngines?.styleOptionFor(p.id));
        if (uci != null) {
          return (
            uci: _bot.avoidRepetition(uci, _fenHistory(), currentLines),
            standIn: false
          );
        }
      }
      debugPrint('[bot] custom engine had no move; falling back to the engine');
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

  /// Has the search of the position on the board FINISHED — a different
  /// question from how deep it got, and one depth cannot answer (#95).
  ///
  /// An analysis ends at [kAnalysisDepth] OR [kAnalysisMovetimeMs], whichever
  /// comes first, and is also stopped short when the board moves on
  /// (`cancelAnalyses`, which resolves it with its partials). So a finished
  /// search routinely sits below the target for good, and a bare "depth 19" is
  /// ambiguous between "still climbing" and "this is all it will ever say".
  ///
  /// Only the arbiter's future knows which, so the answer is recorded when it
  /// resolves rather than guessed in the pane. The alternative considered was
  /// leaving it to the UI to notice the depth had stopped changing for a
  /// second or two — which is a timer racing a search whose whole point is
  /// that its pace is unpredictable, and would have shown "finished" every
  /// time a deep ply took a while.
  bool get analysisSettled => _settledFens.contains(position.fen);

  /// The blind SETTING — is the switch on. Not the same question as
  /// [hidingHelp], and the difference is the whole of #148.
  ///
  /// Read this only to render or toggle the switch itself, and in
  /// [_assisted], where the question really is about the setting: whether
  /// help was AVAILABLE while you were playing is what decides if the game
  /// counts for your rating, and that must not become "was it on screen at
  /// this instant".
  bool get blind => _settings.blind;

  /// Is this board withholding forward-looking help right now — engine
  /// arrows, the threat, the win rings, square tinting, the Lines/Tree/Book
  /// panes. THE one predicate; every surface asks this rather than deriving
  /// its own (#148).
  ///
  /// It used to be derived in six places with three different answers: the
  /// Book and Lines panes said `blind && botEnabled && !gameOver`, the tree
  /// pane said `blind && botEnabled`, and the board overlays said `blind`
  /// alone. So turning blind on at the ANALYSIS board blanked the board while
  /// the Lines pane beside it went on listing the engine's moves with evals —
  /// the app hiding and showing the same thing at once, a few hundred pixels
  /// apart.
  ///
  /// `botEnabled` is deliberately NOT part of this, and that was tried first.
  /// Gating on an opponent reads well — there is nobody to keep a secret from
  /// when both sides are you — but blind mode's real use on the analysis
  /// board is not secrecy, it is self-testing: guess the move before letting
  /// the engine tell you. Requiring a bot made the switch INERT there, and
  /// worse, left the toggle and its "no engine help" tooltip in place over a
  /// board covered in engine arrows. The inconsistency is now resolved the
  /// other way: blind hides everything, everywhere it applies.
  ///
  /// `!_review` does the one job `botEnabled` was also quietly doing. `blind`
  /// is a shared SettingsStore flag, so without this a blind game in progress
  /// on the Play tab would strip the arrows and threat glyphs off an entirely
  /// unrelated ARCHIVED game in Review. Nothing there is being played, so
  /// there is nothing to withhold.
  ///
  /// `!gameOver`: the SETTING stays sticky — the New Game sheet relies on
  /// that, and flipping switches mid-recap would be jarring — but the EFFECT
  /// lapses the moment the game ends, because there is nothing left to
  /// protect and reading what just happened is the point of the recap.
  bool get hidingHelp => blind && !_review && !gameOver;

  /// What the panes may show: nothing forward-looking in blind mode during
  /// a live bot game (web: visibleLines).
  List<EngineMove> get visibleLines =>
      hidingHelp ? const [] : currentLines;

  // ---- overlays: opponent threat (null-move probe) + square control ----

  Map<String, dynamic>? _threat; // {fen, uci, san, gain} — fen-gated
  final Map<String, Map<String, ControlCell>> _controlCache = {};

  /// Top engine moves for the board's green arrows (web: top-3, fading).
  List<String> get engineArrowUcis {
    if (!_settings.showArrows || hidingHelp) return const [];
    return [for (final l in currentLines.take(_settings.arrowCount)) l.uci];
  }

  /// The live threat, when it is fresh and wanted — the move the opponent
  /// would play with a free move, and what it nets them.
  Map<String, dynamic>? get threat {
    if (!_settings.showThreats || hidingHelp) return null;
    final t = _threat;
    return t != null && t['fen'] == position.fen ? t : null;
  }

  /// The threat arrow's uci.
  String? get threatUci => threat?['uci'] as String?;

  /// The threat in algebraic notation, e.g. 'Be6'.
  String? get threatSan => threat?['san'] as String?;

  /// The threat in words, e.g. 'Nc6 forks the king and the rook.' — the brain
  /// points the move explainers at the null-move probe and names what the free
  /// move would do. Null for a victimless gain that names no piece, where the
  /// numeric cost is all there is to say.
  String? get threatProse => threat?['prose'] as String?;

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
    if (!_settings.showThreats || hidingHelp) return null;
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
  Map<String, ControlCell>? get controlMap {
    if (!_settings.showControl || hidingHelp) return null;
    final chess = _chess;
    if (chess == null) return null;
    return _controlCache.putIfAbsent(
        position.fen, () => chess.controlSquares(position.fen));
  }

  String? _lastOverlaySig;
  String? _probeInFlightFen; // one probe per position, never a queue of them

  Future<void> _probeThreat() async {
    final chess = _chess;
    if (chess == null || !_settings.showThreats || hidingHelp) return;
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

  // ---- review: an archived game on the analysis board (#194) ----

  /// The game currently on the review board, by stored id — so navigating
  /// within one game does not rebuild it (and does not throw away the
  /// variations played into it).
  String? _reviewId;

  /// The reviewed game as a TREE (#196): the played line, plus whatever has
  /// been tried on top of it. Null until a game is opened.
  ReviewTree? _tree;
  ReviewTree? get tree => _tree;

  /// The cursor has left the played game and is in a variation.
  bool get inVariation => _tree != null && !_tree!.onMainline;

  /// Where the PLAYED game sits, for the win chart and the move list — the
  /// cursor's own ply on the mainline, or the ply a variation departed after.
  int get reviewAnchorPly => _tree?.anchorPly ?? 0;

  /// The archived record for the move the cursor is on: its grade, label and
  /// explanation. Null at the start position and throughout a variation,
  /// where there is no archived move to describe.
  Map<String, dynamic>? get reviewStoredMove => _tree?.current.stored;

  /// Open [stored] and put its position at mainline [ply] on the board.
  ///
  /// The mechanism here is the point of #194, and it is deliberately NOT
  /// [browseTo]. Browsing leaves `position` on the live game and shows the
  /// past one through [browseFen] — which is exactly why BoardPane blanks
  /// every overlay while browsing: the threat probe, the square control and
  /// the engine arrows are all computed for `position`, so drawn over a
  /// browsed fen they would describe a position nobody is looking at.
  ///
  /// Review instead makes the cursor's position BE `position`. Every one of
  /// those overlays then points at what is on the board with no review-
  /// specific copy of any of them — which is what "Review IS the analysis
  /// board" has to mean if it is to be worth doing.
  ///
  /// Called when the archive opens or closes a game. Opening builds the tree
  /// and lands on the start position; re-notifying about the SAME game does
  /// nothing, so a variation being explored survives an unrelated rebuild.
  void showReview(Map<String, dynamic>? stored) {
    if (!_review) return;
    if (stored == null) {
      if (_reviewId == null) return;
      _reviewId = null;
      _tree = null;
      moves.clear();
      // The BOARD too, not just the move list. Closing left the last position
      // of the closed game sitting there with its last-move highlight, which
      // is what the next game briefly renders over.
      _startFen = Chess.initial.fen;
      position = Chess.initial;
      lastMove = null;
      _threat = null;
      notifyListeners();
      return;
    }
    final id = stored['id'] as String?;
    if (id == _reviewId) return;
    _reviewId = id;
    _loadReview(stored);
    // Open at the START. Reviewing runs forwards — the whole UI is built
    // around stepping into the next move's verdict — and landing on the final
    // position means every review begins by scrubbing all the way back. Same
    // rule lichess and chess.com open a game with.
    _tree!.gotoMainlinePly(0);
    _syncToTree();
  }

  /// Go to a ply of the PLAYED line, leaving any variation — what the chart,
  /// the move list and the jump-to-start button all mean. Naming a move of the
  /// game is how you say "take me back to what actually happened".
  void gotoMainlinePly(int ply) {
    final t = _tree;
    if (t == null) return;
    final before = t.current;
    t.gotoMainlinePly(ply);
    // Only if the board actually moved. _syncToTree cancels position-scoped
    // work on the arbiter SHARED with the live game, so tapping the move you
    // are already on, or pressing "last move" at the last move, threw away the
    // Play board's analysis for nothing.
    if (!identical(t.current, before)) _syncToTree();
  }

  /// Rebuild the tree and the move list from a stored game.
  ///
  /// [moves] is kept in step with the MAINLINE because the played line is
  /// what the move list, the chart and the engine-lines tree's played path
  /// all speak about — a variation is explored on the board, not written into
  /// the record of the game.
  void _loadReview(Map<String, dynamic> stored) {
    _redoStack.clear();
    _analysis.clear();
    _settledFens.clear();
    _partials.clear();
    _controlCache.clear();
    _threat = null;
    _browsePly = null;
    // `whereType`, not a cast: `stored['moves']` being something other than a
    // list of maps is the one shape the field-by-field guard below cannot see,
    // because the cast that reaches it throws first — and that throw lands
    // inside a ChangeNotifier notification, which swallows it and leaves
    // _reviewId on the failed game while the board still shows the previous
    // one. Re-opening the failed game is then a no-op forever.
    final movesField = stored['moves'];
    final raw = [
      if (movesField is List)
        for (final e in movesField.whereType<Map>()) e.cast<String, dynamic>()
    ];
    // Checked BEFORE anything is read out, not after — the guard used to sit
    // below the casts it was there to protect, so a record missing a field
    // threw a _TypeError on the way to it. That throw lands inside a
    // ChangeNotifier notification, which swallows it, leaving _reviewId set to
    // the game that failed and _tree still on the PREVIOUS one: game B's move
    // list and chart over game A's board, with re-opening B a no-op. The
    // archive is the one input here we do not control — BackupService.importJson
    // validates only id and endedAt and writes the rest verbatim, and sync pulls
    // funnel through it.
    final usable = raw.isNotEmpty &&
        raw.every((m) =>
            m['san'] is String &&
            m['uci'] is String &&
            m['color'] is String &&
            m['ply'] is num &&
            _parses(m['fenBefore']) &&
            _parses(m['fenAfter']));
    if (!usable) {
      moves.clear();
      _startFen = Chess.initial.fen;
      _tree = ReviewTree(_startFen);
      _reviewColor = 'w';
      return;
    }
    moves
      ..clear()
      ..addAll([
        for (final m in raw)
          MoveRecord(
            ply: (m['ply'] as num).toInt(),
            san: m['san'] as String,
            uci: m['uci'] as String,
            color: m['color'] as String,
            fenBefore: m['fenBefore'] as String,
            fenAfter: m['fenAfter'] as String,
          )
      ]);
    _startFen = moves.first.fenBefore;
    // Castling reaches the archive as two different strings. dartchess
    // normalises it to king-takes-rook (parseSan gives e1h1), which is what a
    // PGN import stores; the lichess and chess.com importers write from+to
    // (e1g1); an in-app game stores whatever squares the player dragged. The
    // tree matches a played move against the archived one by UCI STRING, so
    // without this, castling on an imported game forks a phantom variation off
    // itself — "you have left the game", the archived grade for the move
    // dropped, and a move list reading O-O branching into O-O.
    _tree = ReviewTree.fromStored(_startFen, [
      for (final m in raw) {...m, 'uci': _normalisedUci(m)}
    ]);
    // Orientation only. A game with no bot in it — an import, or an analysis
    // game — has no "you" to take a side, so it is read from White's. That is
    // the same rule ReviewBody applied for imports; for an ANALYSIS game the
    // old rule happened to pick Black, which was arbitrary rather than
    // intended, so this is a deliberate change and not a port.
    final botColor = stored['botColor'] as String?;
    _reviewColor = botColor == null ? 'w' : (botColor == 'w' ? 'b' : 'w');
  }

  static bool _parses(Object? fen) {
    if (fen is! String) return false;
    try {
      Chess.fromSetup(Setup.parseFen(fen));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A stored move's uci in dartchess's own spelling, so it can be compared
  /// with one the board produces. See the call site for why the archive holds
  /// more than one spelling of the same castling move. Falls back to the
  /// stored string if anything about the record will not parse — by this point
  /// it has been validated, but a normaliser is not worth a crash.
  static String _normalisedUci(Map<String, dynamic> m) {
    final uci = m['uci'] as String;
    try {
      final pos = Chess.fromSetup(Setup.parseFen(m['fenBefore'] as String));
      final move = Move.parse(uci);
      if (move is! NormalMove) return uci;
      return pos.normalizeMove(move).uci;
    } catch (_) {
      return uci;
    }
  }

  /// Put the board on whatever node the tree's cursor is now at.
  ///
  /// The tail is the same sequence [undo] runs, for the same reason: the board
  /// moved, so the stale threat goes, the new position gets an analysis, and
  /// the engine-lines tree and the threat probe follow it.
  void _syncToTree() {
    final node = _tree!.current;
    _gen++;
    // cancelAnalyses, NOT bumpGeneration — the arbiter is SHARED with the live
    // game. bumpGeneration voids every queued and running search of every
    // priority, so scrubbing a review would have resolved the live game's
    // bot-move search as null and left its bot silently declining to move.
    // This drops position-scoped work, which is the same thing [_apply] does
    // when the board moves under it. Note that _positionScoped covers the
    // refusal check too (#167), so a scrub here can cancel an in-flight
    // pre-commit check on the Play board — which fails OPEN, letting a blunder
    // through ungraded. No user-reachable simultaneity today (the arrow keys
    // are gated to the Review tab), but it is a real hazard rather than the
    // "analysis and threat probe only" this comment used to claim.
    //
    // It does also drop the live position's own background analysis, since
    // that fen is not this one — an accepted cost of one engine behind two
    // boards, and self-healing: the Play board keeps the partials it had and
    // asks again on its next move.
    _arbiter.cancelAnalyses(exceptFen: node.fen);
    position = Chess.fromSetup(Setup.parseFen(node.fen));
    lastMove = node.uci == null ? null : NormalMove.fromUci(node.uci!);
    _threat = null;
    _analysisFor(position.fen);
    _syncTree();
    _probeThreat();
    notifyListeners();
  }

  /// Play a move on the review board (#196).
  ///
  /// Off the played line this starts — or continues — a variation; ON it, a
  /// move that matches what was actually played just walks forward into the
  /// game rather than cloning it. Either way the archive is untouched: the
  /// tree keeps the played game as the first child of every node on it, so
  /// there is always a way back.
  void reviewPlay(NormalMove move, String san) {
    final t = _tree;
    if (t == null || !position.isLegal(move)) return;
    // Normalised for the same reason the archive is (see _normalisedUci):
    // dragging a king two squares and dragging it onto its rook are the same
    // castling move, and only one of those spellings is in the record.
    final norm = position.normalizeMove(move) as NormalMove;
    t.play(
      uci: norm.uci,
      san: san,
      color: position.turn == Side.white ? 'w' : 'b',
      fen: position.playUnchecked(move).fen,
    );
    _syncToTree();
  }

  /// Jump to any node of the tree — a move list tapping a variation move.
  void gotoNode(ReviewNode node) {
    final t = _tree;
    if (t == null || identical(t.current, node)) return;
    t.goto(node);
    _syncToTree();
  }

  /// The start position, and the end of the line the cursor is on (a
  /// variation's own end when in one, the game's otherwise).
  void gotoStart() => gotoMainlinePly(0);

  /// The end of the PLAYED game — not the end of an exploration hanging off
  /// it, which is where "forward until it stops" would land.
  void gotoEnd() {
    final t = _tree;
    if (t == null) return;
    if (t.onMainline) {
      gotoMainlinePly(t.mainlineLength);
      return;
    }
    final before = t.current;
    while (t.forward()) {}
    if (!identical(t.current, before)) _syncToTree();
  }

  bool get canStepBack => _tree?.canBack ?? false;
  bool get canStepForward => _tree?.canForward ?? false;

  /// One ply back along the line the cursor is on — inside a variation that is
  /// the variation's own, not the game's.
  void stepBack() {
    if (_tree?.back() ?? false) _syncToTree();
  }

  void stepForward() {
    if (_tree?.forward() ?? false) _syncToTree();
  }

  /// Abandon the current variation and return to the move it departed after.
  void discardVariation() {
    if (_tree?.discardVariation() != null) _syncToTree();
  }

  void toggleFlip() {
    _flipped = !_flipped;
    notifyListeners();
  }

  /// Steps the cursor; stepping past the last move returns to live.
  void browseBy(int delta) {
    if (moves.isEmpty) return;
    final next = (browsePly + delta).clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    // A refusal message is about the live position's just-attempted move;
    // browsing elsewhere and back should not leave it showing stale next to
    // whatever the card ends up displaying (review follow-up, #167/#224).
    _clearRefusalUi();
    notifyListeners();
  }

  void browseTo(int ply) {
    if (moves.isEmpty) return;
    final next = ply.clamp(0, moves.length);
    _browsePly = next == moves.length ? null : next;
    _clearRefusalUi(); // see browseBy
    notifyListeners();
  }

  /// Back to the live position — also the escape hatch from a preview.
  void browseLive() {
    if (previewing) stopPreview();
    if (_browsePly == null) return;
    _browsePly = null;
    notifyListeners();
  }

  /// True while [_apply] is running, so a flag falling INSIDE it can tell that
  /// a move is mid-flight.
  ///
  /// Only [onFlag] reads it, and only to skip its own `_saveGame()`. See the
  /// call site: saving from there archives the game before [_apply] has
  /// registered the flagging move's grade pipeline, so the move that ended the
  /// game is the one move in the archive with no label.
  bool _applying = false;

  /// The game-long exploration map (null until wired with a ChessApi).
  LinesTreeModel? linesTree;

  void _syncTree() {
    linesTree?.ingest(
      lines: currentLines,
      fen: position.fen,
      // In review this is the path to the CURSOR — including a variation's own
      // moves — not the whole archived game, whose later moves have nothing to
      // do with the position beside them. Live, _tree is null and this is the
      // played list as before.
      playedSans: [
        for (final m in _review && _tree != null ? _tree!.current.pathFromRoot : moves)
          (m is MoveRecord ? m.san : (m as ReviewNode).san!)
      ],
      height: 300,
      // Blind must be baked into the LAYOUT, not just the paint: a hidden
      // node's score-derived y would otherwise displace a visible one and leak
      // the eval through its position (#147). Same predicate the pane paints
      // with — blind only bites in a real bot game.
      blind: hidingHelp,
    );
  }

  Future<List<EngineMove>?> _analysisFor(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    return _analysis.putIfAbsent(fen, () {
      late final Future<List<EngineMove>?> mine;
      mine = _arbiter.analysis(fen, onUpdate: (lines) {
        _partials[fen] = lines;
        if (fen == position.fen) {
          _syncTree();
          notifyListeners();
        }
        onUpdate?.call(lines);
      }).then((lines) {
        // A QUEUED analysis that gets cancelled resolves null having streamed
        // nothing, and this map is only cleared on load. Memoising that null
        // means the position is never analysed again for as long as the game
        // is open — no engine arrows, no lines, no win rings, permanently.
        //
        // Live that barely showed: you rarely stand on the same fen twice.
        // Review is nothing BUT revisiting fens, and every cursor step cancels
        // (see _syncToTree), so scrubbing forward and back left a trail of
        // dead positions behind the cursor — while the threat arrow, which is
        // not memoised, kept coming back. That read as a rendering bug.
        //
        // Identity-guarded: only evict the entry if it is still THIS future,
        // never a newer one someone started for the same fen in the meantime.
        // Null only, not empty — an empty answer from a search that actually
        // ran is a real answer (a mated position has no moves), and evicting
        // it would re-search a terminal position forever.
        if (lines == null && identical(_analysis[fen], mine)) {
          _analysis.remove(fen);
        } else if (lines != null) {
          // The search is over — at the target, at the movetime backstop, or
          // stopped early by the board moving on, all three of which end it
          // for good because the memo above means this fen is never searched
          // again. A NULL resolution is the one case that is not settled: the
          // entry is evicted a line above precisely so the position gets
          // analysed afresh, and marking it final would park the pane's
          // progress bar on a search that has not run.
          _settledFens.add(fen);
          // The last streamed partial notified; this resolution is a separate
          // event after it, and without its own notify the pane keeps drawing
          // a search that is still going.
          if (fen == position.fen) notifyListeners();
        }
        return lines;
      });
      return mine;
    });
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

  /// Grades a move WITHOUT touching any [MoveRecord]: pre-lines →
  /// `gradeMove`, then — once the child search (the position [fenAfter]
  /// results in) crosses depth 10, or [cap] expires — `backfillGrade`.
  /// Shared by [_gradePipeline] (uncapped, after the move has already
  /// committed) and [_maybeRefuse] (capped, before it commits), so the two
  /// never grade the same move two different ways.
  ///
  /// [onGraded] fires once, right after the plain `gradeMove` step, before
  /// the wait for backfill — [_gradePipeline] uses it to give the UI the
  /// same early partial-grade update it always has, ply by ply. Returns null
  /// only when there are no usable pre-lines at all (nothing to grade) or
  /// [gen] was superseded while waiting on them; a grade that COULD not be
  /// backfilled (child search too slow, or [cap] hit) still returns — with
  /// `backfilled == false` — rather than null, so a caller that only cares
  /// about "did we get a grade at all" is not forced to treat an unbackfilled
  /// one as failure.
  /// Pre-lines for a caller a human is WAITING on (refusal mode), as opposed
  /// to the post-commit pipeline that can take all the time it likes.
  ///
  /// [fen] is the live position, so its analysis has been running since the
  /// position appeared and its streamed partials are normally already far
  /// deeper than this decision needs. Awaiting the future instead means
  /// waiting out the whole depth-22 / [kAnalysisMovetimeMs] budget of a search
  /// the player has just made irrelevant — which, together with the queue wait
  /// it caused for the candidate search, is what made refusal mode feel like
  /// the board had stopped responding.
  ///
  /// The await is kept as the fallback for the genuinely cold case (a move
  /// played before anything streamed) and capped, so that case fails open
  /// rather than hanging. It is also the path the test harness takes, since a
  /// fake arbiter resolves instantly and may never stream partials at all.
  Future<List<EngineMove>?> _preLinesFor(String fen, Duration cap) async {
    final partial = _partials[fen];
    if (partial != null &&
        partial.isNotEmpty &&
        partial.first.depth >= kMinUsefulDepth) {
      return partial;
    }
    final lines = await _analysisFor(fen).timeout(cap, onTimeout: () => null);
    if (lines != null && lines.isNotEmpty) return lines;
    return _partials[fen];
  }

  Future<MoveGrade?> _computeGrade({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required String fenAfter,
    required int gen,
    void Function(MoveGrade partial)? onGraded,
    /// The analysis of [fenAfter] — i.e. what the OPPONENT gets to do next.
    /// Its first pv is the refutation, which is the one thing a refused move
    /// can be explained with that does not give away the best move.
    void Function(List<EngineMove> child)? onChild,
    Duration? cap,
  }) async {
    // pre-lines: the completed (or cancelled-with-partials) analysis of the
    // position the move was played from, falling back to streamed partials
    List<EngineMove>? pre;
    if (cap == null) {
      pre = await _analysisFor(fenBefore);
      if (pre == null || pre.isEmpty) pre = _partials[fenBefore];
    } else {
      pre = await _preLinesFor(fenBefore, cap);
    }
    if (gen != _gen || pre == null || pre.isEmpty) return null;

    final grade = _grading.gradeMove(
      ply: ply,
      fenBefore: fenBefore,
      san: san,
      uci: uci,
      color: color,
      preLines: pre,
    );
    onGraded?.call(grade);

    List<EngineMove>? child;
    if (cap == null) {
      // Post-commit path (_gradePipeline): unchanged from before this method
      // existed — just await the search to completion, falling back to
      // whatever streamed in if the future itself resolves empty (a
      // cancelled search). This can take the full multi-second budget in
      // production, and that is fine here: nobody is blocked on it. The FAST
      // answer for the UI is _earlyBackfill (see _apply), an entirely
      // separate event-driven path wired straight to record.grade — this is
      // only the eventual, unhurried confirmation the collect decision uses.
      child = await _analysisFor(fenAfter);
      if (child == null || child.isEmpty) child = _partials[fenAfter];
    } else {
      // Pre-commit refusal check (_maybeRefuse): a human is waiting, so this
      // is a search of its own rather than an [_analysisFor] — three reasons,
      // all of which were latency the player felt on every single move:
      //
      //  * PRIORITY. An `analysis` request queues behind the position's own
      //    still-running depth-22 analysis, because equal priority never
      //    preempts. [SearchPriority.refusalCheck] takes the engine now.
      //  * IT ENDS. `go depth 10, MultiPV 1` is everything backfillGrade
      //    reads. The old full-budget analysis kept running long after it had
      //    answered, so a REFUSED move left the engine busy for seconds and
      //    the retry queued behind it — each attempt slower than the last.
      //  * NOT CACHED. A depth-10 MultiPV-1 result must not become
      //    `_analysis[fenAfter]`; if the move is allowed, [_apply] asks for
      //    that fen's analysis and must get the real full-depth one, not this.
      //
      // [cap] is the backstop, not the plan: it should never be reached now,
      // and reaching it fails open (see [_maybeRefuse]).
      child = await _arbiter
          .search(
            fen: fenAfter,
            depth: kRefusalCheckDepth,
            multiPv: 1,
            movetimeMs: cap.inMilliseconds,
            priority: SearchPriority.refusalCheck,
          )
          .timeout(cap, onTimeout: () => null);
      if (child == null || child.isEmpty) child = _partials[fenAfter];
    }
    // AFTER both branches, deliberately. Hanging this off the post-commit one
    // alone meant the refusal path — the only caller that wants it — never
    // fired it, and the feature was silently absent rather than broken.
    if (child != null && child.isNotEmpty) onChild?.call(child);
    if (gen != _gen ||
        child == null ||
        child.isEmpty ||
        child.first.depth < 10) {
      return grade; // not backfilled — caller checks MoveGrade.backfilled
    }
    return _grading.backfillGrade(grade, child);
  }

  Future<void> _gradePipeline(MoveRecord record, int gen) async {
    try {
      await _gradePipelineInner(record, gen);
    } catch (e, st) {
      // Contained for the same reason [_maybeBotTurn] and [_maybeRefuse]
      // contain theirs: this is fire-and-forget from [_apply] and the app
      // installs no zone guard, so a bridge StateError here became an
      // unhandled async error. The move itself is already committed by this
      // point, so the honest cost of a dead grading bridge is the GRADE, not
      // the move — which is precisely the difference the refusal path's own
      // catch exists to restore, and it would have led straight back into
      // this one.
      debugPrint('[grade] pipeline failed for ${record.san}: $e\n$st');
    }
  }

  Future<void> _gradePipelineInner(MoveRecord record, int gen) async {
    final grade = await _computeGrade(
      ply: record.ply,
      fenBefore: record.fenBefore,
      san: record.san,
      uci: record.uci,
      color: record.color,
      fenAfter: record.fenAfter,
      gen: gen,
      onGraded: (g) {
        record.grade = g;
        notifyListeners();
      },
    );
    if (gen != _gen || grade == null) return; // no pre-lines, or superseded
    record.grade = grade;
    notifyListeners();

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
      final outcome = await practice.maybeCollect(_storedMoveOf(record),
          setupUci: prevUci);
      // Keyed by ply so the card reports the verdict against the RIGHT move:
      // [lastGradeCollectOutcome] hands it back only while the grade on screen
      // is this one. A takeback leaves it set — you did add that blunder — and
      // the ply match makes it reappear if the position ever returns.
      _lastCollect = (ply: record.ply, outcome: outcome);
      notifyListeners();
    }
  }

  ({int ply, CollectOutcome outcome})? _lastCollect;

  /// Whether the move whose grade the card is showing was just added to
  /// practice — null unless the latest player grade is the one collection last
  /// ran on. Only a real game against a bot collects (see the guard above), so
  /// this is null on the analysis board and in bot-vs-bot, exactly where the
  /// card should say nothing about practice.
  CollectOutcome? get lastGradeCollectOutcome {
    final g = lastPlayerGrade;
    final c = _lastCollect;
    if (g == null || c == null) return null;
    return c.ply == g.ply ? c.outcome : null;
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

  /// A draw the RULES force but a stateless [Position] cannot see (#186):
  /// threefold repetition or the 50-move rule. Null when neither holds.
  ///
  /// Auto-enforced rather than offered as a claim: nobody claims a draw in a
  /// bot game, so a repeating line has to end itself — which is the bug this
  /// fixes, two bots shuffling forever.
  String? _ruleDrawReason() {
    // 50-move rule: 100 half-moves since the last pawn move or capture, read
    // from the FEN's halfmove clock (dartchess maintains it).
    final fields = position.fen.split(' ');
    final halfmoves = fields.length >= 5 ? int.tryParse(fields[4]) ?? 0 : 0;
    if (halfmoves >= 100) return 'Draw — 50-move rule';
    // Threefold repetition over the line actually played (the current position
    // is the last entry of the history, so three occurrences includes it).
    final key = _repetitionKey(position.fen);
    var seen = 0;
    for (final fen in _fenHistory()) {
      if (_repetitionKey(fen) == key && ++seen >= 3) return 'Draw by repetition';
    }
    return null;
  }

  /// A FEN reduced to what makes two positions "the same" for repetition: the
  /// board, side to move, castling rights and en-passant square — the move
  /// counters dropped.
  static String _repetitionKey(String fen) {
    final f = fen.split(' ');
    return f.length >= 4 ? '${f[0]} ${f[1]} ${f[2]} ${f[3]}' : fen;
  }

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
    for (final e in _chessGpt.values) {
      e.dispose();
    }
    for (final r in _customRunners.values) {
      r.dispose();
    }
    maiaStatus.dispose();
    // Its ticker is a live Timer: left running it outlives the tree, which
    // flutter_test reports as a pending timer and a device reports as a clock
    // still counting down a game nobody is playing.
    _clock?.dispose();
    _disposed = true;
    super.dispose();
  }

  /// The overlay switches as they were BEFORE a rated game turned them off,
  /// or null when no rated game owns them.
  ///
  /// Rated mode suppresses blind/arrows/threats/control by writing the real
  /// settings, because those are what the board reads. Nothing used to put
  /// them back, so one rated game silently disabled the engine arrows, the
  /// threat glyphs and the square tint EVERYWHERE — Review and the analysis
  /// board included — until the player found four separate switches. And with
  /// blind left on, the next CASUAL game was blind too.
  ///
  /// Applied and restored by [newGame] and by the end of the game, so the
  /// suppression lasts exactly as long as the game that asked for it.
  /// The snapshot lives in [SettingsStore.ratedSnapshot] — on DISK, not in a
  /// field here. A field was the first version, and it loses the switches to
  /// the one teardown it cannot see: kill the app mid-rated game and blind
  /// stays on with three overlays off forever, the original bug via a
  /// different door. Persisted, the next casual game hands them back.
  void _applyRatedPreset() {
    // Only if nothing is held already: a rematch of a rated game re-applies
    // the preset, and overwriting here would snapshot the SUPPRESSED values
    // and hand those back as if they were the player's own.
    _settings.ratedSnapshot ??= jsonEncode({
      'blind': _settings.blind,
      'arrows': _settings.showArrows,
      'threats': _settings.showThreats,
      'control': _settings.showControl,
    });
    _settings.blind = true;
    _settings.showArrows = false;
    _settings.showThreats = false;
    _settings.showControl = false;
  }

  /// Give the player their switches back. Safe to call at any time; a no-op
  /// when no rated game took them.
  void _restoreAfterRated() {
    final raw = _settings.ratedSnapshot;
    if (raw == null) return;
    _settings.ratedSnapshot = null;
    final Map<String, dynamic> p;
    try {
      p = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Unreadable note about the settings. Dropping it is the only safe
      // move: guessing would write four switches the player never chose.
      return;
    }
    // Defaults matching SettingsStore's own: a snapshot written by an older
    // build without one of these keys restores the out-of-the-box answer
    // rather than throwing on a null.
    _settings.blind = p['blind'] as bool? ?? false;
    _settings.showArrows = p['arrows'] as bool? ?? true;
    _settings.showThreats = p['threats'] as bool? ?? true;
    _settings.showControl = p['control'] as bool? ?? true;
  }

  /// Set by [dispose], read by [notifyListeners].
  bool _disposed = false;

  /// Nearly everything that ends in a `notifyListeners()` here is a
  /// fire-and-forget async tail — a grade pipeline, a bot turn's 1.5s opening
  /// wait, a refusal check — and any of them can still be in flight when the
  /// controller is torn down. There is nothing for them to do about that:
  /// [ChangeNotifier] throws if they notify, so the alternative is a
  /// `_disposed` check bolted onto every one of those tails, and the one that
  /// gets forgotten becomes a crash in a `finally` nobody is watching.
  /// Dropping the notification is the whole correct response — the listeners
  /// are gone.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}

/// The Review tab's board (#194): a second [GameController], in review mode,
/// over an archived game.
///
/// A subclass purely so the two can be told apart by TYPE in the provider
/// tree — the live game and the review board are both GameControllers, and
/// `context.read<GameController>()` has to keep meaning the live one
/// everywhere outside Review. Inside Review the body republishes this one
/// AS a GameController, so BoardPane and every overlay widget resolve to it
/// without knowing review exists.
///
/// Constructed with no db and no practice controller, which is what actually
/// makes it inert: `_saveGame` returns on a null db, so an archived game
/// cannot be re-archived, re-rated or collected from by being looked at.
///
/// It follows [ReviewController] by SUBSCRIPTION rather than being pushed at
/// from a widget: which game is open and where the cursor sits is that
/// controller's state, and writing it across during a build is the classic
/// notify-during-build crash. Owning the subscription here also means owning
/// its removal, which a listener wired up in a provider's `create` cannot do.
class ReviewBoardController extends GameController {
  final ReviewController _reviewController;

  ReviewBoardController(
    SearchArbiter arbiter,
    BotApi bot,
    GradingApi grading,
    SettingsStore settings,
    this._reviewController, {
    ChessApi? chessApi,
  }) : super(arbiter, bot, grading, settings, null, null, chessApi, null, true) {
    _reviewController.addListener(_follow);
    _follow();
  }

  void _follow() => showReview(_reviewController.current);

  @override
  void dispose() {
    _reviewController.removeListener(_follow);
    super.dispose();
  }
}
