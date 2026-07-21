// Importing a player's analysed games from lichess (#134).
//
// Two halves are faked and one is real, deliberately:
//
//   the NETWORK is faked, at http.Client. A test that actually called lichess
//     would be flaky, rude, and pinned to one person's game history. What it
//     answers with is a REAL response, captured by hand (support/
//     lichess_fixture.dart) — the auth and CORS questions #134 raised were
//     settled the same way, by making the request once.
//
//   the BRAIN is real, through node, because the mapping is the whole feature.
//     A stub bridge returning a canned StoredGame would prove that Dart can
//     read a map, not that lichess's evals become grades and blunders.
//
//   cd flutter && flutter test test/lichess_import_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:botvinnik_mobile/brain/lichess_import_api.dart';

import 'support/lichess_fixture.dart';
import 'support/node_brain.dart';

/// A client that answers every request with [body] and records what it was
/// asked for.
({http.Client client, List<http.BaseRequest> requests}) respondWith(String body,
    {int status = 200}) {
  final requests = <http.BaseRequest>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response(body, status,
        headers: {'content-type': 'application/x-ndjson'});
  });
  return (client: client, requests: requests);
}

Future<LichessImport> runImport({
  String body = kLichessNdjson,
  int status = 200,
  String username = 'DrNykterstein',
  Set<String>? existing,
  double threshold = 5,
  int max = kDefaultMaxGames,
  List<http.BaseRequest>? capture,
}) async {
  final mock = respondWith(body, status: status);
  final api = LichessImportApi(NodeBrainBridge(), client: mock.client);
  final result = await api.importGames(
    username: username,
    existingIds: existing ?? <String>{},
    collectThreshold: threshold,
    max: max,
  );
  capture?.addAll(mock.requests);
  return result;
}

void main() {
  test('the pinned fixture is a real response, not an invention', () {
    final games = const LineSplitter()
        .convert(kLichessNdjson.trim())
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    expect(games, hasLength(2));
    for (final g in games) {
      // one eval entry per half-move is the shape the mapper walks; a fixture
      // that drifted from it would test nothing the app will ever meet
      expect((g['analysis'] as List).length,
          (g['moves'] as String).split(' ').length);
      expect(g['variant'], 'standard');
      expect(g['pgn'], contains('[Site "https://lichess.org/'));
    }
  });

  test('the request is the anonymous analysed-games query', () async {
    final sent = <http.BaseRequest>[];
    await runImport(capture: sent, max: 10);

    expect(sent, hasLength(1));
    final url = sent.single.url;
    expect(url.scheme, 'https');
    expect(url.host, 'lichess.org');
    expect(url.path, '/api/games/user/DrNykterstein');
    // evals=true is what makes the import worth doing; analysed=true is what
    // keeps ungraded games (which would import as bare as a pasted PGN) out
    expect(url.queryParameters['evals'], 'true');
    expect(url.queryParameters['analysed'], 'true');
    expect(url.queryParameters['max'], '10');
    // No token, and none needed — verified against the live endpoint on
    // 2026-07-21. If lichess ever changes that, this is the line to revisit.
    expect(sent.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
    expect(sent.single.headers['Accept'], 'application/x-ndjson');
  });

  test('both games arrive graded, with real names and a PGN', () async {
    final result = await runImport();

    expect(result.games.map((g) => g['id']),
        ['lichess-kAdOQKeh', 'lichess-xKWdG1d1']);
    expect(result.skipped, 0);
    for (final g in result.games) {
      expect(g['source'], 'lichess');
      expect(g['moveCount'], 30);
      // the grades a pasted PGN cannot carry
      expect(g['whiteAccuracy'], isNotNull);
      expect(g['blackAccuracy'], isNotNull);
      expect((g['moves'] as List).first['label'], isNotNull);
      // and the PGN the archive's export button needs — the real movetext,
      // whose first move is the one the mapper graded first
      final movetext = (g['pgn'] as String).split('\n\n').last;
      expect(movetext, startsWith('1. ${(g['moves'] as List).first['san']}'));
    }
    final second = result.games[1];
    expect(second['white'], 'DrNykterstein');
    expect(second['black'], 'Sharkfang');
    expect(second['result'], '1-0');
  });

  test('the importing player\'s own mistakes become practice seeds', () async {
    final result = await runImport(threshold: 5);

    // Two per game, White in one and Black in the other — the mapper only
    // mines the moves the named player made.
    expect(result.practice.map((p) => p.move['san']),
        ['f6', 'Kf7', 'g3', 'a4']);
    for (final seed in result.practice) {
      expect(seed.move['bestUci'], isNotNull);
      expect(seed.move['fenBefore'], isNotNull);
      // PracticeController.maybeCollect refuses anything under minDepth, and
      // the mapper writes no depth on its moves — without this the whole
      // import would seed nothing at all, silently.
      expect(seed.move['depth'], 22);
    }
    final mistake = result.practice.last;
    expect(mistake.drop, greaterThan(10));
    expect(mistake.setupUci, 'f7f5'); // the opponent's move into the position
  });

  test('the archived game is not carrying the seed\'s depth field', () async {
    final result = await runImport();

    // The seed's move is a COPY with `depth` added. If it were the same map,
    // every imported game would be archived with a depth the server never
    // reported on moves that were never searched.
    for (final g in result.games) {
      for (final m in (g['moves'] as List)) {
        expect((m as Map).containsKey('depth'), isFalse);
      }
    }
  });

  test('the threshold keeps only the costly mistakes', () async {
    final result = await runImport(threshold: 10);

    // three of the four candidates drop 6-8 win-chance points; one drops 11.5
    expect(result.practice, hasLength(1));
    expect(result.practice.single.move['san'], 'a4');
    // and the games themselves are unaffected — the threshold is about what
    // gets drilled, not about what gets archived
    expect(result.games, hasLength(2));
  });

  test('re-importing the same period adds nothing', () async {
    final result = await runImport(
        existing: {'lichess-kAdOQKeh', 'lichess-xKWdG1d1'});

    expect(result.games, isEmpty);
    expect(result.practice, isEmpty,
        reason: 'a second import must not re-collect the same blunders');
    expect(result.skipped, 2);
  });

  test('a half-written last line is skipped, not fatal', () async {
    // What a dropped connection mid-stream actually leaves behind.
    final truncated = '$kLichessNdjson{"id":"broke","variant":"stand';
    final result = await runImport(body: truncated);

    expect(result.games, hasLength(2));
    expect(result.skipped, 1);
  });

  test('a 404 names the user rather than the status code', () async {
    await expectLater(
      runImport(body: '{"error":"Not found"}', status: 404,
          username: 'nobodyhere'),
      throwsA(isA<LichessImportException>()
          .having((e) => e.message, 'message', contains('nobodyhere'))),
    );
  });

  test('a 429 says to wait', () async {
    await expectLater(
      runImport(body: '', status: 429),
      throwsA(isA<LichessImportException>()
          .having((e) => e.message, 'message', contains('rate-limiting'))),
    );
  });

  test('a username that is not one never reaches the network', () async {
    // RECORD the urls, do not fail() inside the client: the API catches
    // everything and rethrows it as LichessImportException, so a fail() there
    // is swallowed and the assertion passes either way. Mutating the username
    // regex to `^.*$` left this file green, and three requests went out —
    // including .../api/api/account from the input '../../api/account'.
    final urls = <String>[];
    final client = MockClient((req) async {
      urls.add(req.url.toString());
      return http.Response('', 200);
    });
    for (final bad in ['', '  ', '../../api/account', 'a/b', 'x' * 40, 'a b']) {
      await expectLater(
        LichessImportApi(NodeBrainBridge(), client: client).importGames(
            username: bad, existingIds: const {}, collectThreshold: 5),
        throwsA(isA<LichessImportException>()),
      );
    }
    expect(urls, isEmpty,
        reason: 'a rejected username must never be put in a URL');
  });

  test('an unreachable lichess is reported, not thrown raw', () async {
    final client =
        MockClient((_) async => throw const SocketExceptionStandIn());
    final api = LichessImportApi(NodeBrainBridge(), client: client);
    await expectLater(
      api.importGames(
          username: 'DrNykterstein', existingIds: {}, collectThreshold: 5),
      throwsA(isA<LichessImportException>()
          .having((e) => e.message, 'message', contains('Could not reach'))),
    );
  });
}

/// Stands in for whatever the platform throws when the request never lands —
/// a SocketException on native, an opaque ClientException on web. The import
/// must not care which.
class SocketExceptionStandIn implements Exception {
  const SocketExceptionStandIn();
  @override
  String toString() => 'connection failed';
}
