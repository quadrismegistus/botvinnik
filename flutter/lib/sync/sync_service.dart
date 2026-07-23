import 'dart:convert';

import '../stores/backup.dart';
import 'sync_crypto.dart';
import 'sync_store.dart';

/// What one [SyncService.syncNow] achieved.
class SyncResult {
  const SyncResult({
    required this.pulled,
    required this.attempts,
  });

  /// New records the remote blob contributed to the local store this sync
  /// (summed across retries).
  final BackupCounts pulled;

  /// How many GET→merge→PUT rounds it took. > 1 means a concurrent writer was
  /// resolved by re-merging — never by dropping data.
  final int attempts;
}

/// One device's end of sync: pull the remote blob, merge it into the local
/// store, push the merged result back under compare-and-swap. All the hard
/// parts already exist — [BackupService] does the convergent merge, [SyncCrypto]
/// does the crypto, [SyncStore] does the transport — so this is just the loop
/// that ties them together (#203 M3).
class SyncService {
  SyncService({
    required this.keys,
    required this.store,
    required this.backup,
    this.maxAttempts = 4,
  });

  final SyncKeys keys;
  final SyncStore store;
  final BackupService backup;

  /// A CAS race re-reads and retries; this bounds it so a pathologically busy
  /// blob can't loop forever. Reaching it throws [SyncConflict].
  final int maxAttempts;

  /// GET → merge → seal → CAS PUT, retrying on a lost race. Because the merge is
  /// convergent (games: existing-wins; practice: max-attempts) and additive,
  /// re-merging after a conflict can only ever add — no write is lost.
  ///
  /// Throws [SyncTransportException] when the store is unreachable (the caller
  /// treats that as "offline, try next trigger"), [SyncTooLarge] past the size
  /// cap, or [SyncConflict] if it could not win the CAS within [maxAttempts].
  Future<SyncResult> syncNow() async {
    var pulledGames = 0;
    var pulledPractice = 0;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final remote = await store.get(keys.blobId);
      if (remote != null) {
        final plaintext = await SyncCrypto.open(keys.encKey, remote.bytes);
        final counts = await backup.importJson(utf8.decode(plaintext));
        pulledGames += counts.games;
        pulledPractice += counts.practice;
      }

      final body = await SyncCrypto.seal(
        keys.encKey,
        utf8.encode(await backup.exportJson()),
      );

      try {
        if (remote == null) {
          await store.create(keys.blobId, body);
        } else {
          await store.update(keys.blobId, body, remote.etag);
        }
        return SyncResult(
          pulled: (practice: pulledPractice, games: pulledGames),
          attempts: attempt,
        );
      } on SyncConflict {
        // Someone wrote between our GET and PUT. Loop: re-GET, re-merge (their
        // blob now includes their new records), and try the CAS again.
        continue;
      }
    }
    throw const SyncConflict();
  }
}
