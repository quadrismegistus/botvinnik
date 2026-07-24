// Maia-3 (issue #221): the typed Dart end of brain/maia3/.
//
// The transports (maia3_engine_*.dart) return RAW per-rung logits; every bit
// of chess math — legal-move masking, softmax, SAN keying, WDL — happens in
// brain/maia3/decoding.ts via [computeMoveCurves]. Keeping the math in the
// brain and not re-deriving it here is deliberate: see the wire-gap memory,
// and the worker comment that names this file as the single caller.

import 'js_bridge.dart';

/// Raw batched-ladder output, exactly as the model produced it: one policy
/// vector (4352 logits) and one WDL vector (3 logits, L/D/W order) per rung.
/// Meaningless without the decode; nothing should read these but [Maia3Api].
class Maia3Raw {
  const Maia3Raw({
    required this.elos,
    required this.policyByElo,
    required this.wdlByElo,
  });

  final List<int> elos;
  final List<List<double>> policyByElo;
  final List<List<double>> wdlByElo;
}

/// One rung of the chart: how likely players at [elo] are to pick each legal
/// move (keyed by SAN, probabilities summing to 1).
class Maia3RungCurve {
  const Maia3RungCurve(this.elo, this.moveProbabilities);
  final int elo;
  final Map<String, double> moveProbabilities;
}

/// One rung's outcome prediction: W/D/L for the side to move, given human
/// play at [elo] on BOTH sides. Not an engine eval — see the issue.
class Maia3RungWdl {
  const Maia3RungWdl(this.elo, {
    required this.win,
    required this.draw,
    required this.loss,
  });
  final int elo;
  final double win;
  final double draw;
  final double loss;

  double get expectedScore => win + 0.5 * draw;
}

/// Chart-ready result for one position across the whole ELO ladder.
class Maia3MoveCurves {
  const Maia3MoveCurves({required this.perElo, required this.wdlByElo});
  final List<Maia3RungCurve> perElo;
  final List<Maia3RungWdl> wdlByElo;
}

class Maia3Api {
  final JsBridge _bridge;
  const Maia3Api(this._bridge);

  /// The 21-rung batch dimension (600..2600 step 100). The brain owns the
  /// ladder so the chart's x-axis and the batch the transports run are the
  /// same list by construction.
  List<int> eloLadder() =>
      (_bridge.call('MAIA_ELO_LADDER', isProperty: true) as List)
          .cast<num>()
          .map((n) => n.toInt())
          .toList();

  /// Masks each rung's policy to [fen]'s legal moves, softmaxes, and keys by
  /// SAN; softmaxes each rung's WDL. Pure math in the brain — the heavy JSON
  /// crossing (~91k floats) is fine at chart cadence (one call per shown
  /// position, debounced by the store).
  Maia3MoveCurves computeMoveCurves(String fen, Maia3Raw raw) {
    final result = _bridge.call('computeMoveCurves', args: [
      fen,
      [
        for (var i = 0; i < raw.elos.length; i++)
          {'elo': raw.elos[i], 'policy': raw.policyByElo[i]},
      ],
      [
        for (var i = 0; i < raw.elos.length; i++)
          {'elo': raw.elos[i], 'wdl': raw.wdlByElo[i]},
      ],
    ]) as Map;

    final perElo = (result['perElo'] as List).map((p) {
      final point = (p as Map).cast<String, dynamic>();
      return Maia3RungCurve(
        (point['elo'] as num).toInt(),
        (point['moveProbabilities'] as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
    }).toList();

    final wdlByElo = (result['wdlByElo'] as List).map((p) {
      final point = (p as Map).cast<String, dynamic>();
      final wdl = (point['wdl'] as Map).cast<String, dynamic>();
      return Maia3RungWdl(
        (point['elo'] as num).toInt(),
        win: (wdl['win'] as num).toDouble(),
        draw: (wdl['draw'] as num).toDouble(),
        loss: (wdl['loss'] as num).toDouble(),
      );
    }).toList();

    return Maia3MoveCurves(perElo: perElo, wdlByElo: wdlByElo);
  }
}
