// chess.com import test doubles (#166), shared by the api test and the ui test.
//
// The NETWORK is faked at http.Client with the REAL response shape — the
// archive INDEX and a monthly `games` array — verified by hand against
// api.chess.com on 2026-07-21 (200, no token, `access-control-allow-origin: *`)
// and trimmed to the fields the walk reads.
//
// The BRIDGE is faked too, unlike the lichess tests, ON PURPOSE: `ccGameToStored`
// is a new brain export not in the committed assets/brain.js yet (rebuilt at
// reconcile, not on this branch), so a NodeBrainBridge would load the old
// bundle and throw. The mapping itself is proved against the TypeScript source
// in brain/chesscomCore.test.ts and guarded by name in scripts/smoke-brain.mjs;
// these doubles let the Dart side — the walk, the dedupe, the cap, the URL, the
// UI — be tested without it.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:botvinnik_mobile/brain/js_bridge.dart';

/// One archived game, in the shape the API returns (the fields the mapper
/// reads, unaltered). The clock-annotated movetext is chess.com's own.
Map<String, dynamic> ccGame({
  required String uuid,
  required int endTime,
  String rules = 'chess',
  String white = 'botvinnik_fan',
  String black = 'Opponent99',
  String whiteResult = 'win',
  String blackResult = 'checkmated',
}) =>
    {
      'uuid': uuid,
      'rules': rules,
      'time_class': 'rapid',
      'end_time': endTime,
      'white': {'username': white, 'rating': 1240, 'result': whiteResult},
      'black': {'username': black, 'rating': 1255, 'result': blackResult},
      'pgn': '[White "$white"]\n[Black "$black"]\n[Result "1-0"]\n\n'
          '1. e4 {[%clk 0:10:00]} 1... e5 {[%clk 0:10:00]} 2. Qh5 3. Bc4 '
          'Nf6 4. Qxf7# 1-0',
    };

/// The archive index body for [months] (paths like '2024/03'), as chess.com
/// serves it: oldest-first, which the API must reverse.
String archivesBody(String user, List<String> months) => jsonEncode({
      'archives': [
        for (final m in months)
          'https://api.chess.com/pub/player/$user/games/$m',
      ],
    });

String monthBody(List<Map<String, dynamic>> games) =>
    jsonEncode({'games': games});

/// A client that serves the archive index for [user] and a body per month URL,
/// and records every request. Anything else 404s.
({http.Client client, List<Uri> urls}) chesscomServer({
  required String user,
  required List<String> months,
  required Map<String, String> monthBodies, // '2024/03' -> body
  int archivesStatus = 200,
}) {
  final urls = <Uri>[];
  final client = MockClient((req) async {
    urls.add(req.url);
    final path = req.url.path;
    if (path.endsWith('/games/archives')) {
      return http.Response(archivesBody(user, months), archivesStatus);
    }
    for (final entry in monthBodies.entries) {
      if (path.endsWith('/games/${entry.key}')) {
        return http.Response(entry.value, 200);
      }
    }
    return http.Response('{"error":"not found"}', 404);
  });
  return (client: client, urls: urls);
}

/// Stands in for the brain's `ccGameToStored`: the same contract, UNGRADED, so
/// the Dart walk can be driven without the (not-yet-rebuilt) bundle. Returns
/// null for a non-standard variant, exactly as the real mapper does — which is
/// what lets the skip-count assertions mean anything.
class FakeCcBridge implements JsBridge {
  int calls = 0;

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    calls++;
    final cc = (args[0] as Map).cast<String, dynamic>();
    final name = (args[1] as String).toLowerCase();
    if (cc['rules'] != 'chess' || cc['pgn'] == null) return null;
    final white = (cc['white'] as Map).cast<String, dynamic>();
    final black = (cc['black'] as Map).cast<String, dynamic>();
    final humanColor = (white['username'] as String).toLowerCase() == name
        ? 'w'
        : (black['username'] as String).toLowerCase() == name
            ? 'b'
            : null;
    return {
      'stored': {
        'id': 'chesscom-${cc['uuid']}',
        'endedAt': DateTime.fromMillisecondsSinceEpoch(
                (cc['end_time'] as num).toInt() * 1000,
                isUtc: true)
            .toIso8601String(),
        'result': white['result'] == 'win'
            ? '1-0'
            : black['result'] == 'win'
                ? '0-1'
                : '1/2-1/2',
        'source': 'chesscom',
        'white': white['username'],
        'black': black['username'],
        'botColor': humanColor == 'w'
            ? 'b'
            : humanColor == 'b'
                ? 'w'
                : null,
        'botElo': null,
        'whiteAccuracy': null,
        'blackAccuracy': null,
        'moveCount': 7,
        'moves': const [],
      },
      'humanColor': humanColor,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
