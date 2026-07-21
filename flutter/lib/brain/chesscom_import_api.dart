// Pulling a player's games off chess.com by username (#166) — the other half
// of the lichess import (#134).
//
// The seam is the same one #134 built: Dart owns the HTTP, the brain owns the
// mapping (lib/brain/lichess_import_api.dart has the long version of why —
// JavaScriptCore has no `fetch`, and every bridge call is synchronous, so an
// async brain export would marshal its Promise as `{}`). Two things make this a
// second piece of work rather than a copy:
//
//   1. chess.com is ARCHIVE-PER-MONTH. There is no one streamed request: you
//      fetch the archive index, then one request per month, newest first, until
//      the cap is hit. A real history is dozens of requests, so this walk
//      reports progress and can be cancelled between them.
//
//   2. chess.com ships NO per-move evals. `ccGameToStored` cannot grade what
//      lichess handed over already graded, so an import here arrives UNGRADED —
//      an archive with real names and a `source` of 'chesscom', and an empty
//      practice queue. A background job grades those games and seeds practice
//      from them afterwards (#170); on its own this import does neither, and
//      that is expected, not a bug.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'js_bridge.dart';

/// chess.com usernames are 3–25 of `[A-Za-z0-9_-]`. Checked before the URL is
/// built rather than after: the name goes into the PATH (lower-cased, as the
/// API wants), so anything else is a 404 with a confusing message or a request
/// for a different resource entirely.
final RegExp _kUsername = RegExp(r'^[A-Za-z0-9_-]{3,25}$');

/// How many games to ask for by default.
const int kDefaultMaxGames = 50;

/// The ceiling the dialog offers. The limit is memory, not the API:
/// `ReviewController` holds every stored game decoded with all its moves, and
/// the archive is re-read on every Review-tab visit. #134 settled on the same
/// number for the same reason.
const int kMaxGames = 300;

/// Anything the user should be told about rather than a bug.
class ChesscomImportException implements Exception {
  final String message;
  const ChesscomImportException(this.message);
  @override
  String toString() => message;
}

/// Where the month-walk has got to, so the dialog can show a live line and a
/// rate rather than an opaque spinner over dozens of requests.
class CcImportProgress {
  final int monthsDone;
  final int monthsTotal;

  /// Games looked at so far (across the months fetched), before dedupe.
  final int gamesSeen;

  /// Games that will be archived — new, standard, readable.
  final int gamesAdded;

  /// The month currently being walked, `yyyy/mm`, or '' before the first.
  final String currentMonth;

  /// Games per minute over the whole walk so far. 0 until a little time has
  /// passed, so a caller should hide it while it reads 0.
  final double gamesPerMin;

  const CcImportProgress({
    required this.monthsDone,
    required this.monthsTotal,
    required this.gamesSeen,
    required this.gamesAdded,
    required this.currentMonth,
    required this.gamesPerMin,
  });
}

typedef CcProgress = void Function(CcImportProgress p);

/// What one import produced. [games] are ready to save verbatim and carry NO
/// grades — nothing here touched the database or the engine.
class ChesscomImport {
  final List<Map<String, dynamic>> games;

  /// Games a month carried that produced nothing: already archived, a
  /// non-standard variant, or unreadable movetext. The user is owed this count.
  final int skipped;

  /// As typed (trimmed); the API path is lower-cased separately.
  final String username;

  /// True when the walk stopped because the user cancelled it, so a caller can
  /// tell "finished a partial import" from "finished the lot".
  final bool cancelled;

  const ChesscomImport({
    required this.games,
    required this.skipped,
    required this.username,
    required this.cancelled,
  });
}

class ChesscomImportApi {
  final JsBridge _bridge;
  final http.Client _client;

  /// [client] is injected so tests can answer at the HTTP boundary — a test
  /// that actually walked chess.com would be flaky, rude, and pinned to one
  /// person's game history.
  ChesscomImportApi(this._bridge, {http.Client? client})
      : _client = client ?? http.Client();

  /// Walk [username]'s monthly archives, newest first, mapping each game to an
  /// UNGRADED stored document until [max] games are collected or the archives
  /// run out.
  ///
  /// [existingIds] is the archive's ids (`chesscom-<uuid>`); a re-import of the
  /// same period must add nothing, and the id dedupe is the only thing that
  /// guarantees it — a StoredGame saved twice would upsert under the same key
  /// while a later grade re-collected its practice items all over again. The
  /// set is not mutated.
  ///
  /// [isCancelled] is polled between requests and between games, so cancelling
  /// stops the walk after at most the request in flight rather than mid-parse.
  Future<ChesscomImport> importGames({
    required String username,
    required Set<String> existingIds,
    int max = kDefaultMaxGames,
    CcProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final name = username.trim();
    if (!_kUsername.hasMatch(name)) {
      throw const ChesscomImportException(
          'That is not a chess.com username — 3–25 letters, digits, - and _.');
    }
    final cap = max.clamp(1, kMaxGames);
    final lower = name.toLowerCase();

    final months = await _fetchArchives(lower); // newest first

    final games = <Map<String, dynamic>>[];
    // ids added in THIS walk, so a partial dedupe never leans on mutating the
    // caller's set; combined with existingIds it is the full "already have it".
    final added = <String>{};
    var skipped = 0;
    var seen = 0;
    var monthsDone = 0;
    var cancelled = false;
    final start = DateTime.now();

    double rate() {
      final mins = DateTime.now().difference(start).inMilliseconds / 60000.0;
      return mins > 0 ? seen / mins : 0;
    }

    void report(String month) => onProgress?.call(CcImportProgress(
          monthsDone: monthsDone,
          monthsTotal: months.length,
          gamesSeen: seen,
          gamesAdded: games.length,
          currentMonth: month,
          gamesPerMin: rate(),
        ));

    report('');
    for (final monthUrl in months) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      if (games.length >= cap) break;
      final month = _monthLabel(monthUrl);
      final ccGames = await _fetchMonth(monthUrl); // newest first

      for (final cc in ccGames) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        if (games.length >= cap) break;
        seen++;
        final uuid = cc['uuid'] as String?;
        final id = uuid == null ? null : 'chesscom-$uuid';
        // Dedupe BEFORE the bridge: on native the mapper is a JavaScriptCore
        // eval, so skipping an already-archived game here saves that per-game
        // cost across a re-import of a whole history.
        if (id != null && (existingIds.contains(id) || added.contains(id))) {
          skipped++;
          continue;
        }
        // The brain returns null for a game it declines — non-standard variant,
        // corrupt movetext, a moveless game, or a record whose shape drifted —
        // and this side only counts it. The try/catch is the backstop for the
        // shape it did NOT anticipate: a single malformed game must be skipped,
        // never allowed to throw across the bridge and abort the whole import.
        Object? mapped;
        try {
          mapped = _bridge.call('ccGameToStored', args: [cc, name]);
        } catch (_) {
          mapped = null;
        }
        if (mapped == null) {
          skipped++;
          continue;
        }
        final stored = ((mapped as Map)['stored'] as Map).cast<String, dynamic>();
        final storedId = stored['id'] as String;
        if (existingIds.contains(storedId) || added.contains(storedId)) {
          skipped++;
          continue;
        }
        added.add(storedId);
        games.add(stored);
        report(month);
      }

      monthsDone++;
      report(month);
      if (cancelled) break;
    }

    return ChesscomImport(
      games: games,
      skipped: skipped,
      username: name,
      cancelled: cancelled,
    );
  }

  /// The archive index: the list of month URLs for this player, newest first.
  Future<List<String>> _fetchArchives(String lower) async {
    final uri =
        Uri.https('api.chess.com', '/pub/player/$lower/games/archives');
    final http.Response res;
    try {
      res = await _client.get(uri);
    } catch (e) {
      throw ChesscomImportException('Could not reach chess.com — $e');
    }
    switch (res.statusCode) {
      case 200:
        break;
      case 404:
        throw ChesscomImportException('No chess.com user "$lower".');
      case 429:
        throw const ChesscomImportException(
            'chess.com is rate-limiting this device. Wait a minute and try again.');
      default:
        throw ChesscomImportException('chess.com API error ${res.statusCode}.');
    }
    final data = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    final archives = (data['archives'] as List?)?.cast<String>() ?? const [];
    return archives.reversed.toList();
  }

  /// One month's games, newest first within the month.
  Future<List<Map<String, dynamic>>> _fetchMonth(String url) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse(url));
    } catch (e) {
      throw ChesscomImportException('Could not reach chess.com — $e');
    }
    if (res.statusCode == 429) {
      throw const ChesscomImportException(
          'chess.com is rate-limiting this device. Wait a minute and try again.');
    }
    if (res.statusCode != 200) {
      throw ChesscomImportException('chess.com API error ${res.statusCode}.');
    }
    final data = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    final raw = (data['games'] as List?) ?? const [];
    final games = [
      for (final g in raw) (g as Map).cast<String, dynamic>(),
    ]..sort((a, b) => ((b['end_time'] as num?)?.toInt() ?? 0)
        .compareTo((a['end_time'] as num?)?.toInt() ?? 0));
    return games;
  }

  /// `.../games/2024/03` -> `2024/03`, for the progress line.
  String _monthLabel(String url) {
    final parts = url.split('/games/');
    return parts.length > 1 ? parts[1] : '';
  }
}
