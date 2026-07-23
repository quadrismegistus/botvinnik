import 'dart:convert';

import 'package:botvinnik_mobile/stores/backup.dart';
import 'package:botvinnik_mobile/sync/sync_controller.dart';
import 'package:botvinnik_mobile/sync/sync_crypto.dart';
import 'package:botvinnik_mobile/sync/sync_key_store.dart';
import 'package:botvinnik_mobile/sync/sync_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_db.dart';
import 'support/memory_sync_store.dart';

const _fast = SyncCryptoParams(iterations: 1000);
const _phrase = 'shared sync phrase for the controller';

Map<String, dynamic> _game(String id, String endedAt) =>
    {'id': id, 'endedAt': endedAt, 'result': '1-0'};

class _FakeKeyStore implements SyncKeyStore {
  SyncSession? _session;
  int writes = 0;
  int clears = 0;

  @override
  Future<SyncSession?> read() async => _session;
  @override
  Future<void> write(SyncSession s) async {
    _session = s;
    writes++;
  }

  @override
  Future<void> clear() async {
    _session = null;
    clears++;
  }
}

/// A store whose reads always fail as if the network were down.
class _OfflineStore implements SyncStore {
  @override
  Future<StoredBlob?> get(String blobId) async =>
      throw const SyncTransportException('no network');
  @override
  Future<String> create(String id, List<int> body) async =>
      throw const SyncTransportException('no network');
  @override
  Future<String> update(String id, List<int> body, String etag) async =>
      throw const SyncTransportException('no network');
}

SyncController _controller(
  MemoryDb db,
  SyncKeyStore keyStore, {
  required SyncStore store,
}) =>
    SyncController(
      db: db,
      keyStore: keyStore,
      storeFactory: (_) => store,
      kdfParams: _fast,
    );

void main() {
  test('starts off; loadCached on an empty store keeps it off', () async {
    final c = _controller(MemoryDb(), _FakeKeyStore(),
        store: MemorySyncStore());
    await c.loadCached();
    expect(c.enabled, isFalse);
    expect(c.status.phase, SyncPhase.off);
  });

  test('enable derives once, caches the session, and pushes a first blob',
      () async {
    final store = MemorySyncStore();
    final keyStore = _FakeKeyStore();
    final db = MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]);
    final c = _controller(db, keyStore, store: store);

    await c.enable(_phrase);

    expect(c.enabled, isTrue);
    expect(c.status.phase, SyncPhase.ok);
    expect(keyStore.writes, 1);
    // The blob now exists under the derived id.
    final keys = await SyncCrypto.deriveKeys(_phrase, params: _fast);
    expect(await store.get(keys.blobId), isNotNull);
  });

  test('a re-launch restores the session from cache without re-deriving',
      () async {
    final store = MemorySyncStore();
    final keyStore = _FakeKeyStore();
    await _controller(MemoryDb(), keyStore, store: store).enable(_phrase);

    // A fresh controller with the same key store = the same device relaunching.
    final relaunched = _controller(MemoryDb(), keyStore, store: store);
    await relaunched.loadCached();

    expect(relaunched.enabled, isTrue);
    expect(relaunched.status.phase, SyncPhase.idle);
    expect(relaunched.phrase, SyncCrypto.normalizePhrase(_phrase));
    expect(keyStore.writes, 1); // loadCached wrote nothing new
  });

  test('two devices sharing a store converge to the union', () async {
    final store = MemorySyncStore();
    final dbA = MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]);
    final dbB = MemoryDb([_game('b1', '2026-07-02T00:00:00.000Z')]);
    final a = _controller(dbA, _FakeKeyStore(), store: store);
    final b = _controller(dbB, _FakeKeyStore(), store: store);

    await a.enable(_phrase); // pushes a1
    final pulledByB = await b.enableAndReport(); // pulls a1, pushes union
    await a.syncNow(); // pulls b1

    expect(dbA.games.keys.toSet(), {'a1', 'b1'});
    expect(dbB.games.keys.toSet(), {'a1', 'b1'});
    expect(pulledByB?.games, 1); // B pulled a1
  });

  test('disable clears the cache and turns off, leaving the blob', () async {
    final store = MemorySyncStore();
    final keyStore = _FakeKeyStore();
    final c = _controller(MemoryDb([_game('g', '2026-07-01T00:00:00.000Z')]),
        keyStore, store: store);
    await c.enable(_phrase);
    final keys = await SyncCrypto.deriveKeys(_phrase, params: _fast);

    await c.disable();

    expect(c.enabled, isFalse);
    expect(c.status.phase, SyncPhase.off);
    expect(keyStore.clears, 1);
    expect(await store.get(keys.blobId), isNotNull); // blob survives for others
  });

  test('a network failure surfaces as offline, not a crash', () async {
    final keyStore = _FakeKeyStore();
    // Enable against a working store so keys exist...
    final working = MemorySyncStore();
    final db = MemoryDb();
    final c = SyncController(
      db: db,
      keyStore: keyStore,
      storeFactory: (_) => working,
      kdfParams: _fast,
    );
    await c.enable(_phrase);

    // ...then a controller whose store is offline.
    final offline = SyncController(
      db: db,
      keyStore: keyStore,
      storeFactory: (_) => _OfflineStore(),
      kdfParams: _fast,
    );
    await offline.loadCached();
    final pulled = await offline.syncNow();

    expect(pulled, isNull);
    expect(offline.status.phase, SyncPhase.offline);
  });

  test('a throwing onPulled does not turn a completed sync into an error',
      () async {
    final store = MemorySyncStore();
    // A pushes a game so B's first sync pulls and fires onPulled.
    await _controller(MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]),
            _FakeKeyStore(), store: store)
        .enable(_phrase);

    final dbB = MemoryDb();
    final b = _controller(dbB, _FakeKeyStore(), store: store);
    b.onPulled = () async => throw StateError('reload boom');
    await b.enable(_phrase);

    expect(b.status.phase, SyncPhase.ok); // completed despite the callback
    expect(dbB.games.keys, contains('a1')); // and the data landed
  });

  test('advise warns on short phrases and blesses six words', () {
    final c = _controller(MemoryDb(), _FakeKeyStore(), store: MemorySyncStore());
    expect(c.advise('too short').strong, isFalse);
    expect(c.advise('one two three four five six').strong, isTrue);
  });

  group('autoSync (triggers)', () {
    test('throttles a burst to one sync per window', () async {
      final store = MemorySyncStore();
      var now = DateTime(2026, 7, 23, 12);
      final c = SyncController(
        db: MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]),
        keyStore: _FakeKeyStore(),
        storeFactory: (_) => store,
        kdfParams: _fast,
        clock: () => now,
      );
      await c.enable(_phrase); // create
      expect(store.writes, 1);

      await c.autoSync(); // within the throttle window of enable's sync → no-op
      expect(store.writes, 1);

      now = now.add(const Duration(seconds: 11)); // past the window
      await c.autoSync();
      expect(store.writes, 2);
    });

    test('does nothing when sync is off', () async {
      final store = MemorySyncStore();
      final c = _controller(MemoryDb(), _FakeKeyStore(), store: store);
      await c.autoSync();
      expect(store.writes, 0);
      expect(c.enabled, isFalse);
    });

    test('onPulled fires when a sync brings new data in, not otherwise',
        () async {
      final store = MemorySyncStore();
      final a = SyncController(
        db: MemoryDb([_game('a1', '2026-07-01T00:00:00.000Z')]),
        keyStore: _FakeKeyStore(),
        storeFactory: (_) => store,
        kdfParams: _fast,
      );
      var aPulled = 0;
      a.onPulled = () async => aPulled++;
      await a.enable(_phrase); // store was empty → nothing pulled
      expect(aPulled, 0);

      final b = SyncController(
        db: MemoryDb(),
        keyStore: _FakeKeyStore(),
        storeFactory: (_) => store,
        kdfParams: _fast,
      );
      var bPulled = 0;
      b.onPulled = () async => bPulled++;
      await b.enable(_phrase); // pulls a1
      expect(bPulled, 1);
    });
  });

  test('the practice collection also converges (max-attempts)', () async {
    final store = MemorySyncStore();
    final dbA = MemoryDb()..kv[kPracticeKvKey] = jsonEncode([
          {'id': 'card', 'attempts': 9}
        ]);
    final dbB = MemoryDb()..kv[kPracticeKvKey] = jsonEncode([
          {'id': 'card', 'attempts': 2}
        ]);
    final a = _controller(dbA, _FakeKeyStore(), store: store);
    final b = _controller(dbB, _FakeKeyStore(), store: store);

    await b.enable(_phrase); // b (2) first
    await a.enable(_phrase); // a pulls 2, keeps its 9, pushes 9
    await b.syncNow(); // b pulls 9

    int attempts(MemoryDb db) =>
        (jsonDecode(db.kv[kPracticeKvKey]!) as List).first['attempts'] as int;
    expect(attempts(dbA), 9);
    expect(attempts(dbB), 9);
  });
}

extension on SyncController {
  /// enable() then report what the first sync pulled (test convenience).
  Future<BackupCounts?> enableAndReport() async {
    await enable(_phrase);
    return status.lastPulled;
  }
}
