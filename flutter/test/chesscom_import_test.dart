// Importing a player's games from chess.com (#166) — the Dart-side walk.
//
// The network doubles and the bridge stand-in are in support/chesscom_fixture.dart
// (which explains why the BRIDGE is faked here where the lichess test uses the
// real bundle: `ccGameToStored` is a new export not in the committed brain.js
// yet). What THIS file owns is the Dart side — the month-walk, the dedupe, the
// cap, the URL, cancellation, and how errors are shaped for the user.
//
//   cd flutter && flutter test test/chesscom_import_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:botvinnik_mobile/brain/chesscom_import_api.dart';

import 'support/chesscom_fixture.dart';

void main() {
  test('the pinned fixture is the real response shape, not an invention', () {
    final g = ccGame(uuid: 'u1', endTime: 1710095400);
    // the exact keys the mapper reads; a fixture that drifted would test
    // nothing the app will ever meet
    expect(g.keys,
        containsAll(['uuid', 'rules', 'time_class', 'end_time', 'white', 'black', 'pgn']));
    expect((g['white'] as Map).keys, containsAll(['username', 'result']));
    expect(g['pgn'], contains('[Result'));
  });

  test('the archive index is fetched anonymously, at the lower-cased name',
      () async {
    final srv = chesscomServer(
      user: 'botvinnikfan',
      months: ['2024/03'],
      monthBodies: {'2024/03': monthBody([ccGame(uuid: 'u1', endTime: 1)])},
    );
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    await api.importGames(username: 'BotvinnikFan', existingIds: const {});

    final index = srv.urls.first;
    expect(index.scheme, 'https');
    expect(index.host, 'api.chess.com');
    // the name goes into the path LOWER-CASED, as the API requires
    expect(index.path, '/pub/player/botvinnikfan/games/archives');
    // no token, and none needed — verified against the live endpoint 2026-07-21
    for (final req in [index]) {
      expect(req.toString(), isNot(contains('token')));
    }
  });

  test('walks months newest-first and archives each game UNGRADED', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/02', '2024/03'], // API order: oldest first
      monthBodies: {
        '2024/02': monthBody([ccGame(uuid: 'feb', endTime: 1706700000)]),
        '2024/03': monthBody([ccGame(uuid: 'mar', endTime: 1709900000)]),
      },
    );
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    final result =
        await api.importGames(username: 'botvinnik_fan', existingIds: const {});

    expect(result.games.map((g) => g['id']),
        ['chesscom-mar', 'chesscom-feb'],
        reason: 'newest month first');
    expect(result.cancelled, isFalse);
    for (final g in result.games) {
      expect(g['source'], 'chesscom');
      expect(g['white'], 'botvinnik_fan');
      expect(g['black'], 'Opponent99');
      // the whole distinction from lichess: no grades come with it
      expect(g['whiteAccuracy'], isNull);
      expect((g['moves'] as List), isEmpty);
    }
    // the archive index was fetched before the newer month, and the newer
    // month before the older one
    expect(srv.urls.map((u) => u.path).toList(), [
      '/pub/player/botvinnik_fan/games/archives',
      '/pub/player/botvinnik_fan/games/2024/03',
      '/pub/player/botvinnik_fan/games/2024/02',
    ]);
  });

  test('a re-import of the same period adds nothing', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/03'],
      monthBodies: {
        '2024/03': monthBody([
          ccGame(uuid: 'already', endTime: 1709900000),
          ccGame(uuid: 'fresh', endTime: 1709800000),
        ]),
      },
    );
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    final result = await api.importGames(
        username: 'botvinnik_fan', existingIds: {'chesscom-already'});

    expect(result.games.map((g) => g['id']), ['chesscom-fresh']);
    expect(result.skipped, 1);
  });

  test('caps at max and does not fetch the months past it', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/01', '2024/02', '2024/03'],
      monthBodies: {
        '2024/03': monthBody([
          ccGame(uuid: 'm3a', endTime: 1709900001),
          ccGame(uuid: 'm3b', endTime: 1709900000),
        ]),
        '2024/02': monthBody([ccGame(uuid: 'm2', endTime: 1706700000)]),
        '2024/01': monthBody([ccGame(uuid: 'm1', endTime: 1704100000)]),
      },
    );
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    final result = await api.importGames(
        username: 'botvinnik_fan', existingIds: const {}, max: 1);

    expect(result.games.map((g) => g['id']), ['chesscom-m3a']);
    // the earlier months must never be requested — the whole point of a cap on
    // a decades-deep history is that it stops walking
    expect(srv.urls.map((u) => u.path),
        isNot(contains('/pub/player/botvinnik_fan/games/2024/02')));
  });

  test('a game whose mapping throws is skipped, not fatal to the whole batch',
      () async {
    // The mapper is guarded now, but the walk must survive a throw it did NOT
    // anticipate — a record shape the brain never saw. One bad game across the
    // bridge must be skipped-and-counted, never abort the import and discard the
    // hundreds of good games behind it.
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/03'],
      monthBodies: {
        '2024/03': monthBody([
          ccGame(uuid: 'good1', endTime: 1709900002),
          ccGame(uuid: 'bad', endTime: 1709900001),
          ccGame(uuid: 'good2', endTime: 1709900000),
        ]),
      },
    );
    final result = await ChesscomImportApi(_ThrowOnUuidBridge('bad'), client: srv.client)
        .importGames(username: 'botvinnik_fan', existingIds: const {});

    expect(result.games.map((g) => g['id']), ['chesscom-good1', 'chesscom-good2'],
        reason: 'the good games still land; the thrower did not take them down');
    expect(result.skipped, 1);
    expect(result.cancelled, isFalse);
  });

  test('a non-standard game is skipped, not archived', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/03'],
      monthBodies: {
        '2024/03': monthBody([
          ccGame(uuid: 'std', endTime: 1709900001),
          ccGame(uuid: 'variant', endTime: 1709900000, rules: 'chess960'),
        ]),
      },
    );
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    final result =
        await api.importGames(username: 'botvinnik_fan', existingIds: const {});

    expect(result.games.map((g) => g['id']), ['chesscom-std']);
    expect(result.skipped, 1);
  });

  test('cancelling stops the walk after the game in flight', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: ['2024/02', '2024/03'],
      monthBodies: {
        '2024/03': monthBody([
          ccGame(uuid: 'a', endTime: 1709900002),
          ccGame(uuid: 'b', endTime: 1709900001),
          ccGame(uuid: 'c', endTime: 1709900000),
        ]),
        '2024/02': monthBody([ccGame(uuid: 'd', endTime: 1706700000)]),
      },
    );
    var cancel = false;
    final api = ChesscomImportApi(FakeCcBridge(), client: srv.client);
    final result = await api.importGames(
      username: 'botvinnik_fan',
      existingIds: const {},
      // flip the flag the instant the first game lands; the api polls it
      // before the next one and stops
      onProgress: (p) {
        if (p.gamesAdded >= 1) cancel = true;
      },
      isCancelled: () => cancel,
    );

    expect(result.cancelled, isTrue);
    expect(result.games, hasLength(1));
    // and the second month was never touched
    expect(srv.urls.map((u) => u.path),
        isNot(contains('/pub/player/botvinnik_fan/games/2024/02')));
  });

  test('a username that is not one never reaches the network', () async {
    // RECORD the urls; do NOT fail() inside the client. The api catches
    // everything and rethrows it as ChesscomImportException, so a fail() there
    // is swallowed and the test passes either way (the lichess review learned
    // this the hard way). A bad name must never be put in a URL at all.
    final urls = <String>[];
    final client = MockClient((req) async {
      urls.add(req.url.toString());
      return http.Response('{}', 200);
    });
    for (final bad in ['', '  ', '../../pub/player', 'a/b', 'ab', 'x' * 40, 'a b']) {
      await expectLater(
        ChesscomImportApi(FakeCcBridge(), client: client)
            .importGames(username: bad, existingIds: const {}),
        throwsA(isA<ChesscomImportException>()),
      );
    }
    expect(urls, isEmpty,
        reason: 'a rejected username must never be put in a URL');
  });

  test('a 404 on the index names the user', () async {
    final srv = chesscomServer(
      user: 'nobodyhere',
      months: const [],
      monthBodies: const {},
      archivesStatus: 404,
    );
    await expectLater(
      ChesscomImportApi(FakeCcBridge(), client: srv.client)
          .importGames(username: 'nobodyhere', existingIds: const {}),
      throwsA(isA<ChesscomImportException>()
          .having((e) => e.message, 'message', contains('nobodyhere'))),
    );
  });

  test('a 429 says to wait', () async {
    final srv = chesscomServer(
      user: 'botvinnik_fan',
      months: const [],
      monthBodies: const {},
      archivesStatus: 429,
    );
    await expectLater(
      ChesscomImportApi(FakeCcBridge(), client: srv.client)
          .importGames(username: 'botvinnik_fan', existingIds: const {}),
      throwsA(isA<ChesscomImportException>()
          .having((e) => e.message, 'message', contains('rate-limiting'))),
    );
  });

  test('an unreachable chess.com is reported, not thrown raw', () async {
    final client = MockClient((_) async => throw const _SocketStandIn());
    await expectLater(
      ChesscomImportApi(FakeCcBridge(), client: client)
          .importGames(username: 'botvinnik_fan', existingIds: const {}),
      throwsA(isA<ChesscomImportException>()
          .having((e) => e.message, 'message', contains('Could not reach'))),
    );
  });
}

class _SocketStandIn implements Exception {
  const _SocketStandIn();
  @override
  String toString() => 'connection failed';
}

/// A bridge that throws on one uuid — the shape-drifted record the walk must
/// survive — and maps everything else exactly as [FakeCcBridge] does.
class _ThrowOnUuidBridge extends FakeCcBridge {
  final String badUuid;
  _ThrowOnUuidBridge(this.badUuid);

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final cc = (args[0] as Map).cast<String, dynamic>();
    if (cc['uuid'] == badUuid) throw StateError('drifted record');
    return super.call(fn, args: args, isProperty: isProperty);
  }
}
