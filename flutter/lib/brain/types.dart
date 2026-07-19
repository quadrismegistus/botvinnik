// Dart mirrors of the brain's data shapes. EngineMove is a full mirror (Dart
// constructs it from native engine output). MoveGrade and Explanation are
// typed VIEWS over the raw JSON map: the map round-trips through the bridge
// (gradeMove → Dart holds it → backfillGrade) and later into sqflite, so the
// raw form IS the storage form — wrapping instead of mirroring means new brain
// fields flow through untouched instead of being silently dropped.

/// One MultiPV line — the shape src/lib/engine/stockfish.ts calls EngineMove.
class EngineMove {
  final List<String> pv;
  final double score; // pawns, side-to-move perspective
  final int? mate;
  final int depth;
  final int multipv;

  const EngineMove({
    required this.pv,
    required this.score,
    required this.mate,
    required this.depth,
    required this.multipv,
  });

  Map<String, dynamic> toJson() =>
      {'pv': pv, 'score': score, 'mate': mate, 'depth': depth, 'multipv': multipv};

  String get uci => pv.first;
}

/// Move labels, chess.com-style bands (see insights.ts MoveLabel).
const List<String> kLabelOrder = [
  'brilliant', 'great', 'best', 'excellent', 'good',
  'inaccuracy', 'miss', 'mistake', 'blunder',
];

class Explanation {
  final Map<String, dynamic> raw;
  const Explanation(this.raw);

  String? get playedIssue => raw['playedIssue'] as String?;
  String? get bestPoint => raw['bestPoint'] as String?;
  String? get playedPoint => raw['playedPoint'] as String?;
  String? get lineStory => raw['lineStory'] as String?;
  Map<String, dynamic>? get evidence => raw['evidence'] as Map<String, dynamic>?;
}

class MoveGrade {
  final Map<String, dynamic> raw;
  const MoveGrade(this.raw);

  int get ply => raw['ply'] as int;
  String get fenBefore => raw['fenBefore'] as String;
  String get san => raw['san'] as String;
  String get uci => raw['uci'] as String;
  String get color => raw['color'] as String;
  int get depth => raw['depth'] as int;
  int? get rank => raw['rank'] as int?;
  double? get evalPawns => (raw['evalPawns'] as num?)?.toDouble();
  int? get mate => raw['mate'] as int?;
  double? get pctBest => (raw['pctBest'] as num?)?.toDouble();
  bool get isBest => raw['isBest'] as bool;
  String get bestSan => raw['bestSan'] as String;
  String get bestUci => raw['bestUci'] as String;
  double get bestEval => (raw['bestEval'] as num).toDouble();
  int? get bestMate => raw['bestMate'] as int?;
  bool get backfilled => raw['backfilled'] as bool;
  List<String> get bestPv => (raw['bestPv'] as List).cast<String>();
  String? get label => raw['label'] as String?;
  Explanation? get explanation {
    final e = raw['explanation'];
    return e == null ? null : Explanation(e as Map<String, dynamic>);
  }
}

/// Roster persona (bots.ts BotPersona) — typed view, same rationale.
class Persona {
  final Map<String, dynamic> raw;
  const Persona(this.raw);

  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  int get elo => raw['elo'] as int;
  String get family => raw['family'] as String;
  String get blurb => raw['blurb'] as String;
  int? get shapedLabel => raw['shapedLabel'] as int?;
  int? get numericElo => raw['numericElo'] as int?;
  /// horizon: js-chess-engine difficulty level (1 or 2)
  int? get jsceLevel => raw['jsceLevel'] as int?;
  /// retro: `{engine, ply}` — which historical engine, and how deep it looks
  Map<String, dynamic>? get retro => raw['retro'] as Map<String, dynamic>?;
  /// garbo: Garbochess-JS movetime in ms
  int? get garboMs => raw['garboMs'] as int?;
}
