// A player-added UCI engine on native desktop: its own child process, kept
// alive across the game's moves and reused, exactly the shape retro/garbo use —
// never the arbiter's queue, because it is an opponent, not an analysis.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'process_engine.dart';

class CustomEngineRunner {
  /// Desktop only. A browser cannot spawn a process (that is Phase 2's server
  /// transport), and iOS/Android forbid launching arbitrary executables.
  static bool get supported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  final String path;
  ProcessEngine? _engine;

  CustomEngineRunner(this.path);

  /// We hand the engine a bare `position fen` with no `moves` list, so it has
  /// no position history for this search. The FEN's halfmove clock, though,
  /// asserts a reversible-move run the engine cannot see — and an engine that
  /// reconstructs repetition history from that clock can index an empty history
  /// and crash: Velvet's `pos_history.rs` does `positions.last().unwrap()` once
  /// the clock reaches 3, which panics on the empty vector and takes the whole
  /// engine process down mid-game. Resetting the clock to 0 keeps the position
  /// command self-consistent and costs an opponent nothing — botvinnik arbitrates
  /// the 50-move and repetition draws itself. A malformed FEN is left untouched.
  static String historylessFen(String fen) {
    final fields = fen.split(' ');
    if (fields.length < 6) return fen;
    fields[4] = '0';
    return fields.join(' ');
  }

  /// The engine's move for [fen], or null on any failure — a binary that will
  /// not start, a search that dies, or a position with no move — which the
  /// caller turns into a Stockfish stand-in.
  ///
  /// [elo], when set, dials the engine down via `UCI_LimitStrength` + `UCI_Elo`
  /// (ignored by an engine that does not advertise them). [movetimeMs] is the
  /// thinking budget.
  Future<String?> move(String fen, {int? elo, int movetimeMs = 1000}) async {
    try {
      _engine ??= await ProcessEngine.spawn(path);
      final extra = elo != null
          ? [
              ['UCI_LimitStrength', 'true'],
              ['UCI_Elo', '$elo'],
            ]
          : const <List<String>>[];
      final lines = await _engine!.search(
        historylessFen(fen),
        go: 'movetime $movetimeMs',
        multiPv: 1,
        extraOptions: extra,
      );
      return lines.isEmpty ? null : lines.first.uci;
    } catch (e) {
      debugPrint('[custom-engine] $path failed: $e');
      // A crashed engine is gone; drop it so the next move re-spawns rather
      // than reusing a dead process.
      _engine?.dispose();
      _engine = null;
      return null;
    }
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
  }
}
