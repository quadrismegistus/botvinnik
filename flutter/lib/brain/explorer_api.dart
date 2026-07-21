// The unified move table: the engine's lines merged with the opening book's
// counts, ranked by how often each move is actually played. The merge itself
// is brain/explorer.ts — Dart loads the baked book (stores/book_store.dart)
// and hands the node over, so the arithmetic has exactly one implementation.

import 'js_bridge.dart';
import 'types.dart';

/// One book's statistics for one move, as shares — never raw counts except
/// [games] itself.
class BookStats {
  final Map<String, dynamic> raw;
  const BookStats(this.raw);

  int get games => (raw['games'] as num).toInt();

  /// This move's share of the games reaching the position, 0-100.
  double get pct => (raw['pct'] as num).toDouble();

  /// How this move's own games ended, 0-100 each.
  double get white => (raw['white'] as num).toDouble();
  double get draws => (raw['draws'] as num).toDouble();
  double get black => (raw['black'] as num).toDouble();
}

/// A merged row: a move the engine found, the book has seen, or both. A typed
/// VIEW over the raw JSON, for the reason types.dart gives — new brain fields
/// flow through instead of being silently dropped.
class UnifiedMove {
  final Map<String, dynamic> raw;
  const UnifiedMove(this.raw);

  String get uci => raw['uci'] as String;
  String get san => raw['san'] as String;

  Map<String, dynamic>? get _engine =>
      (raw['engine'] as Map?)?.cast<String, dynamic>();

  /// Whether the engine has this move among its lines at all.
  bool get hasEngine => raw['engine'] != null;

  /// Evaluation in pawns, MOVER perspective (as the engine reports it).
  double? get score => (_engine?['score'] as num?)?.toDouble();

  /// Mate in n, mover perspective; negative means the mover is being mated.
  int? get mate => (_engine?['mate'] as num?)?.toInt();

  /// Softmax over the engine's lines, 0-100: how sure the engine is that this
  /// is THE move — not how good the move is.
  double? get confidence => (_engine?['confidence'] as num?)?.toDouble();

  BookStats? get lichess {
    final b = raw['lichess'];
    return b == null ? null : BookStats((b as Map).cast<String, dynamic>());
  }

  BookStats? get masters {
    final b = raw['masters'];
    return b == null ? null : BookStats((b as Map).cast<String, dynamic>());
  }
}

class ExplorerApi {
  final JsBridge _bridge;
  const ExplorerApi(this._bridge);

  /// A book node in the shape brain/explorer.ts wants: the games reaching the
  /// position, and the moves played from it. [node] is book.json's node as
  /// BookStore stores it (`{white, draws, black, moves: [...]}`).
  static Map<String, dynamic> position(Map<String, dynamic> node) => {
        'total': (node['white'] as num).toInt() +
            (node['draws'] as num).toInt() +
            (node['black'] as num).toInt(),
        'moves': node['moves'],
      };

  /// Engine lines and book stats as one ranked list. [masters] is null until
  /// an OTB collection is baked — the brain already handles a second book.
  List<UnifiedMove> unifyMoves({
    required String fen,
    required List<EngineMove> lines,
    Map<String, dynamic>? lichess,
    Map<String, dynamic>? masters,
  }) =>
      (_bridge.call('unifyMoves', args: [
        fen,
        lines.map((l) => l.toJson()).toList(),
        lichess,
        masters,
      ]) as List)
          .map((r) => UnifiedMove((r as Map).cast<String, dynamic>()))
          .toList();
}
