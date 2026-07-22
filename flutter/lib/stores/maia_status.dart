// The Maia load lifecycle, per band, so the selection UI can SHOW it.
//
// The Insights card already narrates a Maia move's download, but only during a
// game and only when that card is on screen — not in rated mode, and not in the
// roster picker or New Game sheet where a person is choosing the opponent. And
// it never shows the one thing that matters when a Maia quietly becomes a
// Stockfish stand-in: WHY. On a phone there is no console to read the reason
// from, so an unexplained stand-in is all the player gets. This holds the
// reason so the picker can put it in front of them.

import 'package:flutter/foundation.dart';

import '../engine/maia_progress.dart';

enum MaiaPhase { idle, downloading, starting, ready, failed }

@immutable
class MaiaBandState {
  final MaiaPhase phase;

  /// Non-null while [MaiaPhase.downloading] or [MaiaPhase.starting] — the live
  /// bytes/phase for a bar.
  final MaiaProgress? progress;

  /// Non-null on [MaiaPhase.failed] — the worker's own error string, verbatim,
  /// so a stand-in stops being a mystery (`fetch failed: 403`, `ort init …`).
  final String? error;

  const MaiaBandState._(this.phase, {this.progress, this.error});

  const MaiaBandState.idle() : this._(MaiaPhase.idle);
  const MaiaBandState.ready() : this._(MaiaPhase.ready);

  factory MaiaBandState.loading(MaiaProgress p) => MaiaBandState._(
        p.phase == 'fetching' ? MaiaPhase.downloading : MaiaPhase.starting,
        progress: p,
      );

  factory MaiaBandState.failed(String error) =>
      MaiaBandState._(MaiaPhase.failed, error: error);
}

/// Per-band Maia load state, updated by [MaiaEngine] and watched by the roster
/// picker and the New Game sheet. Keyed by band (1100/1500/1900/…), because the
/// worker holds one session per band and a band, once loaded, serves every
/// persona that shares it.
class MaiaStatus extends ChangeNotifier {
  final Map<int, MaiaBandState> _byBand = {};

  MaiaBandState of(int? band) => band == null
      ? const MaiaBandState.idle()
      : (_byBand[band] ?? const MaiaBandState.idle());

  void update(int band, MaiaBandState state) {
    _byBand[band] = state;
    notifyListeners();
  }
}
