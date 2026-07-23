import 'package:flutter/foundation.dart';

import '../db/app_db.dart';
import '../stores/backup.dart';
import 'sync_config.dart';
import 'sync_crypto.dart';
import 'sync_key_store.dart';
import 'sync_service.dart';
import 'sync_store.dart';

enum SyncPhase { off, idle, syncing, ok, offline, error }

class SyncStatus {
  const SyncStatus(
    this.phase, {
    this.lastSyncedAt,
    this.message,
    this.lastPulled,
  });

  final SyncPhase phase;
  final DateTime? lastSyncedAt;

  /// A human-readable detail for [SyncPhase.error] / [SyncPhase.offline].
  final String? message;

  /// What the most recent sync pulled in — lets the UI know whether to reload
  /// the Practice/Review controllers.
  final BackupCounts? lastPulled;
}

/// Advisory (never a gate) on a chosen phrase's strength — the user asked to be
/// warned, not refused.
class PhraseAdvice {
  const PhraseAdvice({required this.strong, required this.message});
  final bool strong;
  final String message;
}

/// The stateful face of sync (#203 M4): owns the on/off state, the cached
/// session, and the status the UI renders. The actual GET→merge→PUT loop is
/// [SyncService] (M3); this adds persistence (so PBKDF2 runs once per device),
/// error/offline handling, and change notification.
///
/// Dependencies are injected so it can be driven in tests without the secure-
/// storage plugin, the network, or the slow real KDF cost.
class SyncController extends ChangeNotifier {
  SyncController({
    required AppDb db,
    required SyncKeyStore keyStore,
    SyncStore Function(SyncKeys keys)? storeFactory,
    SyncCryptoParams kdfParams = SyncCryptoParams.start,
    DateTime Function()? clock,
  })  : _backup = BackupService(db),
        // ignore: prefer_initializing_formals — keep the public `keyStore:` name
        _keyStore = keyStore,
        _storeFactory =
            storeFactory ?? ((_) => HttpSyncStore(baseUrl: kSyncEndpoint)),
        // ignore: prefer_initializing_formals — keep the public `kdfParams:` name
        _kdfParams = kdfParams,
        _now = clock ?? DateTime.now;

  final BackupService _backup;
  final SyncKeyStore _keyStore;
  final SyncStore Function(SyncKeys) _storeFactory;
  final SyncCryptoParams _kdfParams;
  final DateTime Function() _now;

  SyncSession? _session;
  SyncStatus _status = const SyncStatus(SyncPhase.off);
  bool _busy = false;
  DateTime? _lastSyncAt;

  /// The app wires this to reload the Practice/Review controllers after a sync
  /// pulls new data — so a background sync (launch / resume / after a game)
  /// refreshes the tabs even when the Sync screen isn't open. Kept a plain
  /// callback so the controller stays decoupled from those controllers.
  Future<void> Function()? onPulled;

  /// A burst of triggers (launch + resume close together, or a rematch) must
  /// not hammer the server; [autoSync] coalesces to at most one sync per window.
  static const Duration _autoThrottle = Duration(seconds: 10);

  bool get enabled => _session != null;
  String? get phrase => _session?.phrase;
  SyncStatus get status => _status;

  /// Restore a cached session at startup — no PBKDF2, no network. Leaves sync
  /// off if none was set up.
  Future<void> loadCached() async {
    _session = await _keyStore.read();
    _status = SyncStatus(_session == null ? SyncPhase.off : SyncPhase.idle);
    notifyListeners();
  }

  /// A fresh six-word diceware suggestion for the UI's phrase field.
  String suggestPhrase() => SyncCrypto.generatePhrase();

  /// Strength advice — advisory only, by word count.
  PhraseAdvice advise(String phrase) {
    final words = SyncCrypto.normalizePhrase(phrase)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .length;
    if (words >= 6) {
      return const PhraseAdvice(
          strong: true, message: 'Strong. Save it in your password manager.');
    }
    if (words >= 4) {
      return const PhraseAdvice(
          strong: false,
          message: 'Usable, but six or more words is much harder to guess.');
    }
    return const PhraseAdvice(
        strong: false,
        message:
            'Short — easy to guess. Use six or more words; anyone who guesses '
            'it can read your data.');
  }

  /// Turn sync on: derive the keys (slow — the one PBKDF2), cache the session,
  /// and do a first sync. [phrase] is normalized before use.
  Future<void> enable(String phrase) async {
    _set(const SyncStatus(SyncPhase.syncing, message: 'Setting up…'));
    final normalized = SyncCrypto.normalizePhrase(phrase);
    final keys = await SyncCrypto.deriveKeys(normalized, params: _kdfParams);
    _session = SyncSession(phrase: normalized, keys: keys);
    await _keyStore.write(_session!);
    await syncNow();
  }

  /// Stop syncing on this device and forget the keys. Does NOT delete the blob —
  /// other devices keep syncing, and re-entering the phrase restores it here.
  Future<void> disable() async {
    await _keyStore.clear();
    _session = null;
    _set(const SyncStatus(SyncPhase.off));
  }

  /// GET → merge → push. Returns what the remote contributed locally (so the UI
  /// can reload Practice/Review), or null if sync is off, already running, or
  /// the sync did not complete.
  Future<BackupCounts?> syncNow() async {
    final session = _session;
    if (session == null || _busy) return null;
    _busy = true;
    _lastSyncAt = _now();
    _set(SyncStatus(SyncPhase.syncing, lastSyncedAt: _status.lastSyncedAt));
    try {
      final service = SyncService(
        keys: session.keys,
        store: _storeFactory(session.keys),
        backup: _backup,
      );
      final result = await service.syncNow();
      _set(SyncStatus(SyncPhase.ok,
          lastSyncedAt: _now(), lastPulled: result.pulled));
      final pulled = result.pulled;
      if (pulled.games > 0 || pulled.practice > 0) {
        // Refresh the tabs the pull wrote underneath — but a failure here must
        // not turn a completed sync into a reported error: the CAS PUT already
        // succeeded and the merge is on disk.
        try {
          await onPulled?.call();
        } catch (e) {
          debugPrint('sync: tab refresh (onPulled) failed: $e');
        }
      }
      return pulled;
    } on SyncTransportException {
      _set(SyncStatus(SyncPhase.offline,
          lastSyncedAt: _status.lastSyncedAt,
          message: 'Offline — will retry later.'));
      return null;
    } on SyncTooLarge {
      _set(SyncStatus(SyncPhase.error,
          lastSyncedAt: _status.lastSyncedAt,
          message: 'Archive too large to sync.'));
      return null;
    } catch (e) {
      _set(SyncStatus(SyncPhase.error,
          lastSyncedAt: _status.lastSyncedAt, message: '$e'));
      return null;
    } finally {
      _busy = false;
    }
  }

  /// A background sync for the automatic triggers (launch / resume / after a
  /// game). Silent and throttled: it never throws (syncNow swallows), never
  /// pops a dialog, and no-ops if sync is off, already running, or another sync
  /// happened within [_autoThrottle]. The manual "Sync now" calls [syncNow]
  /// directly, so it is never throttled.
  Future<void> autoSync() async {
    if (!enabled || _busy) return;
    final last = _lastSyncAt;
    if (last != null && _now().difference(last) < _autoThrottle) return;
    await syncNow();
  }

  void _set(SyncStatus status) {
    _status = status;
    notifyListeners();
  }
}
