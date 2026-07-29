// Retro bots on the web: the historical engines compiled to WebAssembly and
// driven in their own Web Worker (web/retro/, staged from static/retro/ by
// stage-web-assets.sh). This is the Dart translation of the Svelte client,
// svelte/src/lib/engine/retro.ts, and speaks the same worker protocol:
// one `{engine, ply}` object to boot, then plain UCI strings both ways.
//
// Deliberately NOT a UciSearcher, and deliberately not behind the arbiter.
// Both halves of that are load-bearing:
//
//   * A retro bot must never touch the analysis engine or its cache. The
//     arbiter exists to serialise the one Stockfish every position's grade
//     depends on; a second engine answering "what would 1948 play here" has
//     no business in that queue, and would evict analysis to say it.
//   * UciProtocol resolves a search from the `info … pv …` lines it collected,
//     so a bestmove with no parsed info line resolves to an EMPTY list. These
//     engines are under no obligation to emit MultiPV info at all — the
//     bestmove line is the only thing worth reading, which is exactly what
//     the Svelte client reads.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'js_worker.dart';

/// The boot message. retro-worker.js tells it from a UCI line by
/// `typeof e.data === 'object'`, so this must cross as an object literal.
extension type _InitMessage._(JSObject _) implements JSObject {
  external factory _InitMessage({String engine, int ply});
}

class RetroEngine {
  static const _scriptUrl = 'retro/retro-worker.js';

  /// The wasm build runs anywhere a Worker does, so on the web: always.
  static bool get supported => true;

  final String engine;
  final int ply;

  final JsWorker _worker;
  /// Resolves true when the engine answered `uci`, false if it never will.
  ///
  /// A bool rather than an error: [preload] constructs the engine and awaits
  /// nothing, so completing this with an error would surface a failed boot as
  /// an unhandled async error — a red screen for a condition every caller
  /// already handles by falling back to Stockfish.
  final Completer<bool> _booted = Completer<bool>();
  Completer<String?>? _move;
  bool _alive = true;

  /// False once this worker's Go program has ended — see the `__exited__`
  /// branch. The engine cannot be revived; the owner builds a new one.
  bool get alive => _alive;

  /// How long ONE turn will wait for the boot before playing a stand-in.
  static const _turnPatience = Duration(seconds: 30);

  /// When the boot stops being worth waiting for AT ALL.
  ///
  /// Two clocks, and collapsing them into one was the bug: a turn that ran out
  /// of patience used to call [_die], which latches `_alive = false` — so a
  /// 4.4MB wasm that took 31 seconds to arrive on a phone cost not one move
  /// but the whole game. Every later turn returned null the instant it was
  /// asked, and the stand-in badge is sticky, so a game that was TUROCHAMP
  /// from move two onward never got to be.
  ///
  /// What a single move will wait for and what the engine should give up on
  /// are different questions. This one only has to be short enough that a
  /// genuinely unreachable worker stops costing every turn 30 seconds.
  static const _bootDeadline = Duration(minutes: 3);
  final Stopwatch _age = Stopwatch()..start();

  RetroEngine(this.engine, this.ply) : _worker = JsWorker(_scriptUrl) {
    _worker.onmessage = ((WorkerMessage e) {
      final data = e.data?.dartify();
      if (data is! String) return; // '__ready__' aside, everything is UCI
      if (data == 'uciok') {
        if (!_booted.isCompleted) _booted.complete(true);
        return;
      }
      // The wasm will never arrive — a 404, a bad MIME type, an instantiate
      // that threw. Distinct from slowness on purpose: this one is worth dying
      // for immediately, and waiting the full deadline for it would stall
      // three minutes of turns to reach the same answer.
      if (data.startsWith('__boot_failed__')) {
        _die('the worker could not load retro.wasm — '
            '${data.substring('__boot_failed__'.length).trim()}');
        return;
      }
      // The Go program has ended, and the client cannot revive it: the worker
      // hosts one instance and `go.run` is a one-shot. It ends when
      // scripts/retro-wasm/main.go returns from `<-driver.Closed()`, which
      // morlock does on `quit` and — see the `ucinewgame` note in [move] — on
      // any command its driver fails to parse.
      //
      // Before the worker announced this, the client found out by posting into
      // a dead worker: the throw landed as an unhandled rejection inside the
      // worker's async handler, nothing came back, and this engine waited out
      // `movetimeMs + 10s` before giving the turn away to a Stockfish stand-in
      // — for the rest of the game, since the badge is sticky.
      //
      // Dying here rather than there is what makes it recoverable:
      // [GameController] checks [alive] when it syncs, so the next turn builds
      // a fresh worker instead of inheriting a corpse. With the `ucinewgame`
      // fix this should now be rare; it is the net under it, not the fix.
      if (data.startsWith('__exited__')) {
        _die('the engine process ended; a fresh worker will be built for the '
            'next turn');
        return;
      }
      if (data.startsWith('bestmove')) {
        final uci = data.split(RegExp(r'\s+')).elementAtOrNull(1);
        _finish(uci == null || uci == '(none)' || uci == '0000' ? null : uci);
      }
    }).toJS;
    _worker.onerror = ((JSAny? event) {
      final detail = (event as WorkerError?)?.message ?? 'unknown error';
      _die('retro worker failed ($_scriptUrl): $detail');
    }).toJS;
    _worker.postMessage(_InitMessage(engine: engine, ply: ply));
    // queued worker-side until the wasm is up — see retro-worker.js
    _worker.postMessage('uci'.toJS);
  }

  /// The engine is gone. Every waiter gets null, which is the contract:
  /// the caller falls back to Stockfish at the persona's rating.
  void _die(String reason) {
    if (!_alive) return;
    _alive = false;
    debugPrint('[retro] $reason');
    if (!_booted.isCompleted) _booted.complete(false);
    _finish(null);
  }

  void _finish(String? uci) {
    final pending = _move;
    _move = null;
    if (pending != null && !pending.isCompleted) pending.complete(uci);
  }

  /// This engine's move for [fen], or null on any failure — a dead worker, a
  /// boot that never finished, a search that never answered.
  Future<String?> move(String fen, {int movetimeMs = 500}) async {
    if (!_alive) return null;
    // Generous: 4.4MB of wasm to fetch and compile, and on a cold cache that
    // is a real download. Running out of it stands in for THIS move; the
    // engine keeps booting, and the next turn asks again — see [_bootDeadline].
    final ok = await _booted.future.timeout(
      _turnPatience,
      onTimeout: () {
        if (_age.elapsed >= _bootDeadline) {
          _die('engine did not boot in ${_bootDeadline.inMinutes} minutes — '
              'is $_scriptUrl served? (stage-web-assets.sh stages it)');
        } else {
          debugPrint('[retro] still booting after ${_age.elapsed.inSeconds}s '
              '— standing in for this move only');
        }
        return false;
      },
    );
    if (!ok || !_alive) return null;
    // One search at a time. The bot has one turn at a time, but a new game or
    // an undo can arrive mid-think: whoever was waiting gets null and falls
    // back, rather than being handed a bestmove for a position that is gone.
    _finish(null);
    final pending = _move = Completer<String?>();
    // `ucinewgame` FIRST, every time, and it is load-bearing rather than
    // tidy. morlock's UCI driver treats a `position` line that PREFIXES the
    // last one as a continuation of the game and parses the remainder as
    // moves (pkg/engine/uci/uci.go, "Continuation of game") — so an IDENTICAL
    // line leaves an empty remainder, `Move(ctx, "")` fails, and the driver
    // RETURNS. That ends the driver, which ends `<-driver.Closed()` in
    // scripts/retro-wasm/main.go, which ends the Go program. In a worker that
    // is a silent death; the client then waits out its whole move timeout and
    // hands the turn to a Stockfish stand-in, for the rest of the game.
    //
    // Honest split of the blame, because it decides where the fix belongs.
    // UCI says a GUI SHOULD send `ucinewgame` when the new position is from a
    // different game than the last one — morlock quotes that line in the
    // source directly above the branch that bites. This client never sent it,
    // so the new-game half of this is our omission, and the line below is us
    // complying rather than working around anybody.
    //
    // The engine's half is that an identical line is a degenerate case its
    // parser does not handle (`strings.Split("", " ")` yields one EMPTY
    // element), and that it answers unparseable input by ending the session
    // rather than ignoring it, which UCI asks engines to do. That half is
    // reachable with no protocol sin at all: take a move back and play the
    // same move again, and the engine is legitimately asked to move from a
    // position it has already been sent, FEN counters and all. Reported
    // upstream; the one-line guard is theirs to take.
    //
    // The report that found it: play a game where the retro bot moves first,
    // start another, and its opening `position fen <start>` is
    // character-identical to the last line the engine saw.
    //
    // This costs nothing: we always send a whole FEN and never a `moves` list,
    // so the continuation branch could never fire usefully for us — a
    // different FEN always takes the engine's "New position" reset path, which
    // is exactly what `ucinewgame` forces. Same work, minus the cliff.
    _worker.postMessage('ucinewgame'.toJS);
    _worker.postMessage('position fen $fen'.toJS);
    _worker.postMessage('go movetime $movetimeMs'.toJS);
    return pending.future.timeout(
      Duration(milliseconds: movetimeMs + 10000),
      onTimeout: () {
        _finish(null);
        return null;
      },
    );
  }

  void dispose() {
    _alive = false;
    _worker.terminate();
    // terminate() fires no event, so nothing else would resolve a search in
    // flight or a boot that never landed
    if (!_booted.isCompleted) _booted.complete(false);
    _finish(null);
  }
}
