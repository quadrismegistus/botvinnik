// Pulling a player's ANALYSED games off lichess by username (#134).
//
// The seam between Dart and the brain is not arbitrary. The brain owns the
// MAPPING — `lichessGameToStored` walks the movetext with chess.js, grades
// every half-move from lichess's own stored evals, and mines the importing
// player's mistakes into practice candidates — and that is the code the web
// shipped, so it must stay one implementation. Dart owns the HTTP for two
// hard reasons:
//
//   1. brain.js runs inside JavaScriptCore on native, which has no `fetch`.
//      `fetchLichessGames` and `importLichessGames` exist in the same brain
//      module and are deliberately NOT exported for exactly that reason: a
//      native call would throw "fetch is not defined", not fail a request.
//   2. Every call over the bridge is synchronous (`JSON.stringify(brain.f(…))`),
//      so an async export would marshal its Promise as `{}` regardless.
//
// So this streams the ndjson, hands the brain one game at a time, and does
// the dedupe and the threshold filter — the five lines `importLichessGames`
// wraps around the mapper — on this side.
//
// Why this beats pasting a PGN: a paste carries no grades at all (see
// stores/pgn_import.dart), while an import arrives with labels, accuracies,
// best moves AND a list of the player's real blunders ready for the practice
// queue, all from numbers lichess already computed. No engine time.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'js_bridge.dart';

/// Lichess usernames are 2–30 of `[A-Za-z0-9_-]`. Checked before the URL is
/// built rather than after: the name goes into the PATH, so anything else is
/// either a 404 with a confusing message or a request for a different
/// resource entirely.
final RegExp _kUsername = RegExp(r'^[A-Za-z0-9_-]{2,30}$');

/// How many games to ask for by default.
///
/// Not a technical limit — the endpoint streams and would happily send
/// thousands. It is a limit because the whole archive is decoded into memory
/// on every Review-tab visit (`AppDb.listGames`), and because each game costs
/// one synchronous bridge call carrying its own JSON. See the class doc.
const int kDefaultMaxGames = 50;

/// The ceiling the dialog offers. 300 analysed games is already ~3 MB of
/// stored movetext in the archive.
const int kMaxGames = 300;

/// Anything the user should be told about rather than a bug.
class LichessImportException implements Exception {
  final String message;
  const LichessImportException(this.message);
  @override
  String toString() => message;
}

/// One collected mistake, in the shape [PracticeController.maybeCollect]
/// takes: the graded StoredMove itself, plus the opponent's move into the
/// position so the drill can replay it for context.
class PracticeSeed {
  /// The StoredMove from the imported game, with `depth` filled in from the
  /// candidate — the archived record is left alone. maybeCollect refuses
  /// anything under `minDepth` and the mapper writes no depth on its moves,
  /// so without this every seed would be silently dropped.
  final Map<String, dynamic> move;
  final String? setupUci;
  final double drop;
  const PracticeSeed({
    required this.move,
    required this.setupUci,
    required this.drop,
  });
}

/// What one import produced. [games] are ready to save verbatim; nothing here
/// has touched the database.
class LichessImport {
  final List<Map<String, dynamic>> games;
  final List<PracticeSeed> practice;

  /// Games the response carried that produced nothing: already in the archive,
  /// non-standard, or unreadable. The user is owed this number — "14 imported"
  /// out of a response of 20 otherwise looks like data loss.
  final int skipped;

  /// As lichess spells it back to us, which is not necessarily how it was
  /// typed (the API is case-insensitive; the mapper compares lowercased).
  final String username;

  const LichessImport({
    required this.games,
    required this.practice,
    required this.skipped,
    required this.username,
  });
}

/// Called with the number of games read so far, as they stream in.
typedef ImportProgress = void Function(int gamesSeen);

class LichessImportApi {
  final JsBridge _bridge;
  final http.Client _client;

  /// [client] is injected so tests can answer at the HTTP boundary. A test
  /// that actually calls lichess is flaky and rude, and would make the suite
  /// depend on one person's game history.
  LichessImportApi(this._bridge, {http.Client? client})
      : _client = client ?? http.Client();

  /// Fetch, grade and dedupe [username]'s analysed games.
  ///
  /// [existingIds] is the archive's ids (`lichess-<gameId>` for anything this
  /// path saved before) — a re-import of the same period must add nothing, and
  /// dedupe by id is the only thing that guarantees it, since a StoredGame
  /// saved twice would otherwise upsert under the same primary key while its
  /// practice items were collected all over again.
  ///
  /// Candidates below [collectThreshold] win-chance points are dropped here
  /// rather than collected and filtered later: unlike a game you played, an
  /// import can arrive with hundreds of them at once.
  Future<LichessImport> importGames({
    required String username,
    required Set<String> existingIds,
    required double collectThreshold,
    int max = kDefaultMaxGames,
    ImportProgress? onProgress,
  }) async {
    final name = username.trim();
    if (!_kUsername.hasMatch(name)) {
      throw const LichessImportException(
          'That is not a lichess username — letters, digits, - and _ only.');
    }

    // The same query the web sent. `analysed=true` is what makes this worth
    // doing: unanalysed games carry no evals, so they would import as
    // ungraded as a pasted PGN.
    final uri = Uri.https('lichess.org', '/api/games/user/$name', {
      'max': '${max.clamp(1, kMaxGames)}',
      'analysed': 'true',
      'evals': 'true',
      'pgnInJson': 'true',
      'moves': 'true',
      'sort': 'dateDesc',
    });

    final http.StreamedResponse response;
    try {
      response = await _client.send(http.Request('GET', uri)
        ..headers['Accept'] = 'application/x-ndjson');
    } catch (e) {
      // The web build reaches lichess through the browser, which reports a
      // blocked or offline request as an opaque failure; there is nothing
      // more specific to say than that it did not happen.
      throw LichessImportException('Could not reach lichess — $e');
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 404:
        throw LichessImportException('No lichess user "$name".');
      case 429:
        throw const LichessImportException(
            'Lichess is rate-limiting this device. Wait a minute and try again.');
      default:
        throw LichessImportException('Lichess API error ${response.statusCode}.');
    }

    final games = <Map<String, dynamic>>[];
    final practice = <PracticeSeed>[];
    var skipped = 0;
    var seen = 0;

    // Streamed, not buffered: one game per line, so the count can move while
    // the response is still arriving, and — because each bridge call is
    // synchronous and blocks the isolate — the awaits between lines are what
    // let the progress text actually paint.
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      seen++;
      onProgress?.call(seen);
      final Map<String, dynamic> raw;
      try {
        raw = (jsonDecode(line) as Map).cast<String, dynamic>();
      } catch (_) {
        skipped++; // a truncated last line beats losing the whole import
        continue;
      }
      final mapped = _bridge.call('lichessGameToStored', args: [raw, name]);
      // null = variant, or no analysis, or corrupt movetext. The brain decides.
      if (mapped == null) {
        skipped++;
        continue;
      }
      final result = (mapped as Map).cast<String, dynamic>();
      final stored = (result['stored'] as Map).cast<String, dynamic>();
      if (existingIds.contains(stored['id'])) {
        skipped++;
        continue;
      }
      games.add(stored);
      practice.addAll(_seeds(stored, result['practice'], collectThreshold));
    }

    return LichessImport(
      games: games,
      practice: practice,
      skipped: skipped,
      username: name,
    );
  }

  /// Pair each candidate back to the graded move it came from.
  ///
  /// The candidate carries the position and the depth; the StoredMove carries
  /// the eval and the drop that [PracticeController.maybeCollect] re-derives
  /// `wcBest` from. Both come out of the same brain call, so the fen is an
  /// exact key. A position repeated inside one game collapses to one entry,
  /// which is what the practice list would have done anyway — it dedupes on
  /// fen too.
  List<PracticeSeed> _seeds(
      Map<String, dynamic> stored, dynamic candidates, double threshold) {
    if (candidates is! List || candidates.isEmpty) return const [];
    final byFen = <String, Map<String, dynamic>>{};
    for (final m in (stored['moves'] as List)) {
      final move = (m as Map).cast<String, dynamic>();
      byFen.putIfAbsent(move['fenBefore'] as String, () => move);
    }
    final out = <PracticeSeed>[];
    for (final c in candidates) {
      final candidate = (c as Map).cast<String, dynamic>();
      final drop = (candidate['drop'] as num).toDouble();
      if (drop < threshold) continue;
      final move = byFen[candidate['fen'] as String];
      if (move == null) continue;
      out.add(PracticeSeed(
        move: {...move, 'depth': candidate['depth']},
        setupUci: candidate['setupUci'] as String?,
        drop: drop,
      ));
    }
    return out;
  }
}
