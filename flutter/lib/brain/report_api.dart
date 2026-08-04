// The skill report (#268): the user's own axes over the archive, and the
// peer cell they sit beside. Both calls are pure — brain/report.ts does all
// the arithmetic; this file only marshals games in and decodes numbers out.
//
// skillReportUser walks EVERY move of EVERY game handed to it, so the caller
// projects first (see [reportGameProjection]) rather than marshalling the
// archive's stored shape, which carries an explanation, a label, a full
// best-line pv and more per move that report.ts never reads.

import 'js_bridge.dart';

class ReportApi {
  final JsBridge _bridge;
  const ReportApi(this._bridge);

  /// The user's own axis numbers, restricted to [timeClass]. [games] must
  /// already be projected ([reportGameProjection]) — this does not slim them.
  Map<String, dynamic> skillReportUser(
      List<Map<String, dynamic>> games, String timeClass) {
    final r = _bridge.call('skillReportUser', args: [games, timeClass]);
    return (r as Map).cast<String, dynamic>();
  }

  /// The peer cell for [band]×[timeClass], reshaped to sit beside
  /// [skillReportUser]'s output. Null when [tables] holds no such cell — the
  /// screen says "no baseline", it does not invent one.
  Map<String, dynamic>? skillReportPeer(
      Map<String, dynamic> tables, int band, String timeClass) {
    final r =
        _bridge.call('skillReportPeer', args: [tables, band, timeClass]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }
}

/// Slims a stored game down to exactly the fields brain/report.ts's
/// `ReportGame`/`ReportMove` read (#268): `botColor`, `botBothSides`, `pgn`,
/// and per move `color`/`evalPawns`/`mate`/`fenBefore`/`san`.
///
/// PROJECTED, not marshalled whole: a stored move also carries `explanation`,
/// `label`, `bestPv`, `bestUci`, `wcDrop`, `depth` and more — none of it read
/// by the walk, all of it bytes a 500-game bridge call would otherwise pay
/// for (see PracticeApi.addItems' 986MB-of-expression-text note for what an
/// unprojected bulk call costs).
///
/// `evalPawns` and `mate` are DECLARED on every move, even when the source
/// has no value for them — `'evalPawns': null`, never an omitted key. This is
/// the null-vs-undefined line JsBridge.omit documents at the call-argument
/// level (js_bridge_shared.dart): a Dart map is JSON-encoded whole, so a
/// missing key marshals to JS `undefined`, not `null`. report.ts's walk reads
/// `afterPawns !== null || afterMate !== null` to decide whether a ply has a
/// graded eval at all — `undefined !== null` is `true`, so an omitted key
/// would be read as "this move has a value" and corrupt the walk on exactly
/// the ungraded moves the check exists to catch. `fenBefore` and `san` are
/// genuinely optional in the contract (`ReportMove` marks them `?`), so those
/// keys are left off when the source has none, matching how the TS side
/// already treats an absent optional field.
Map<String, dynamic> reportGameProjection(Map<String, dynamic> storedGame) {
  final rawMoves = storedGame['moves'];
  return {
    'botColor': storedGame['botColor'],
    'botBothSides': storedGame['botBothSides'],
    'pgn': storedGame['pgn'],
    'moves': [
      if (rawMoves is List)
        for (final m in rawMoves.whereType<Map>())
          _projectMove(m.cast<String, dynamic>()),
    ],
  };
}

Map<String, dynamic> _projectMove(Map<String, dynamic> m) => {
      'color': m['color'],
      'evalPawns': m['evalPawns'],
      'mate': m['mate'],
      if (m['fenBefore'] != null) 'fenBefore': m['fenBefore'],
      if (m['san'] != null) 'san': m['san'],
    };
