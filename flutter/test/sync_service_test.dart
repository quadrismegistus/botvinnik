import 'dart:convert';

import 'package:botvinnik_mobile/stores/backup.dart';
import 'package:botvinnik_mobile/sync/sync_crypto.dart';
import 'package:botvinnik_mobile/sync/sync_service.dart';
import 'package:botvinnik_mobile/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_db.dart';
import 'support/memory_sync_store.dart';

// Cheap PBKDF2: the loop under test doesn't care about the KDF cost.
const _fast = SyncCryptoParams(iterations: 1000);

Map<String, dynamic> _game(String id, String endedAt) =>
    {'id': id, 'endedAt': endedAt, 'result': '1-0'};

Map<String, dynamic> _card(String id, int attempts) =>
    {'id': id, 'attempts': attempts};

void _seedPractice(MemoryDb db, List<Map<String, dynamic>> cards) =>
    db.kv[kPracticeKvKey] = jsonEncode(cards);

List<Map<String, dynamic>> _practiceOf(MemoryDb db) =>
    (jsonDecode(db.kv[kPracticeKvKey]!) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

Set<Object?> _practiceIds(MemoryDb db) =>
    _practiceOf(db).map((c) => c['id']).toSet();

int _attemptsFor(MemoryDb db, String id) =>
    _practiceOf(db).firstWhere((c) => c['id'] == id)['attempts'] as int;

void main() {
  group('the convergence money test', () {
    test('two devices over one store converge to the union', () async {
      final keys = await SyncCrypto.deriveKeys('shared sync phrase', params: _fast);
      final store = MemorySyncStore();

      final dbA = MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]);
      _seedPractice(dbA, [_card('pA', 3)]);
      final dbB = MemoryDb([_game('b1', '2026-07-02T00:00:00.000Z')]);
      _seedPractice(dbB, [_card('pB', 1)]);

      final a = SyncService(keys: keys, store: store, backup: BackupService(dbA));
      final b = SyncService(keys: keys, store: store, backup: BackupService(dbB));

      await a.syncNow(); // creates the blob with a1 / pA
      await b.syncNow(); // pulls a1+pA, pushes the union
      await a.syncNow(); // pulls b1+pB

      // Both devices now hold every game and every card.
      expect(dbA.games.keys.toSet(), {'a1', 'b1'});
      expect(dbB.games.keys.toSet(), {'a1', 'b1'});
      expect(_practiceIds(dbA), {'pA', 'pB'});
      expect(_practiceIds(dbB), {'pA', 'pB'});
    });

    test('order does not matter — the reverse interleaving also converges',
        () async {
      final keys = await SyncCrypto.deriveKeys('shared sync phrase', params: _fast);
      final store = MemorySyncStore();
      final dbA = MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]);
      final dbB = MemoryDb([_game('b1', '2026-07-02T00:00:00.000Z')]);
      final a = SyncService(keys: keys, store: store, backup: BackupService(dbA));
      final b = SyncService(keys: keys, store: store, backup: BackupService(dbB));

      await b.syncNow();
      await a.syncNow();
      await b.syncNow();

      expect(dbA.games.keys.toSet(), {'a1', 'b1'});
      expect(dbB.games.keys.toSet(), {'a1', 'b1'});
    });

    test('practice keeps the more-trained card on both sides', () async {
      final keys = await SyncCrypto.deriveKeys('shared sync phrase', params: _fast);
      final store = MemorySyncStore();
      // The SAME card, trained further on A than on B.
      final dbA = MemoryDb([_game('g', '2026-07-01T00:00:00.000Z')]);
      _seedPractice(dbA, [_card('same', 9)]);
      final dbB = MemoryDb([_game('g', '2026-07-01T00:00:00.000Z')]);
      _seedPractice(dbB, [_card('same', 2)]);
      final a = SyncService(keys: keys, store: store, backup: BackupService(dbA));
      final b = SyncService(keys: keys, store: store, backup: BackupService(dbB));

      await b.syncNow(); // b (2) creates
      await a.syncNow(); // a pulls b's 2, keeps its own 9, pushes 9
      await b.syncNow(); // b pulls 9, replacing its 2

      expect(_attemptsFor(dbA, 'same'), 9);
      expect(_attemptsFor(dbB, 'same'), 9);
    });
  });

  test('a concurrent writer is resolved by re-merge, never by a lost write',
      () async {
    final keys = await SyncCrypto.deriveKeys('shared sync phrase', params: _fast);
    final store = MemorySyncStore();

    final dbA = MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]);
    final dbB = MemoryDb([_game('b1', '2026-07-02T00:00:00.000Z')]);
    final a = SyncService(keys: keys, store: store, backup: BackupService(dbA));
    final b = SyncService(keys: keys, store: store, backup: BackupService(dbB));

    await a.syncNow(); // store now holds {a1} @ e1
    dbA.games['a2'] = _game('a2', '2026-07-03T00:00:00.000Z'); // A's fresh local game

    // Right as A tries to commit its update against e1, B slips a full sync in —
    // pulling a1 and pushing {a1, b1}, moving the blob to e2. A's CAS then fails
    // and it must re-merge rather than clobber b1.
    store.onBeforeUpdate = () async => b.syncNow();

    final result = await a.syncNow();

    expect(result.attempts, 2, reason: 'A lost the first CAS and retried once');
    // Nothing was dropped: the store and A both hold all three games.
    expect(dbA.games.keys.toSet(), {'a1', 'a2', 'b1'});
    final finalBlob = await store.get(keys.blobId);
    final union = jsonDecode(
      utf8.decode(await SyncCrypto.open(keys.encKey, finalBlob!.bytes)),
    );
    final ids = (union['games'] as List).map((g) => g['id']).toSet();
    expect(ids, {'a1', 'a2', 'b1'});
  });

  group('HttpSyncStore speaks the Worker protocol', () {
    final id = 'x' * 20;

    test('create sends If-None-Match: * and returns the etag', () async {
      late http.Request seen;
      final store = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((req) async {
          seen = req;
          return http.Response('', 201, headers: {'etag': 'e1'});
        }),
      );
      final etag = await store.create(id, [1, 2, 3]);
      expect(etag, 'e1');
      expect(seen.method, 'PUT');
      expect(seen.url.toString(), 'https://sync.test/b/$id');
      expect(seen.headers['if-none-match'], '*');
      expect(seen.bodyBytes, [1, 2, 3]);
    });

    test('update sends If-Match: <etag>', () async {
      late http.Request seen;
      final store = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((req) async {
          seen = req;
          return http.Response('', 200, headers: {'etag': 'e2'});
        }),
      );
      expect(await store.update(id, [9], 'e1'), 'e2');
      expect(seen.headers['if-match'], 'e1');
    });

    test('get maps 200 to bytes+etag and 404 to null', () async {
      final present = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((_) async =>
            http.Response.bytes([7, 8], 200, headers: {'etag': 'e5'})),
      );
      final blob = await present.get(id);
      expect(blob!.bytes, [7, 8]);
      expect(blob.etag, 'e5');

      final absent = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((_) async => http.Response('', 404)),
      );
      expect(await absent.get(id), isNull);
    });

    test('412 becomes SyncConflict and 413 becomes SyncTooLarge', () async {
      final conflict = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((_) async => http.Response('', 412)),
      );
      await expectLater(
        conflict.create(id, [1]),
        throwsA(isA<SyncConflict>()),
      );

      final tooBig = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((_) async => http.Response('', 413)),
      );
      await expectLater(
        tooBig.update(id, [1], 'e1'),
        throwsA(isA<SyncTooLarge>()),
      );
    });

    test('a network failure surfaces as SyncTransportException', () async {
      final broken = HttpSyncStore(
        baseUrl: 'https://sync.test',
        client: MockClient((_) async => throw http.ClientException('no route')),
      );
      await expectLater(
        broken.get(id),
        throwsA(isA<SyncTransportException>()),
      );
    });
  });
}
