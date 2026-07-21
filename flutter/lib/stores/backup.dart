// Getting the data out, and back in again (#138).
//
// Two things leave this app: one game's PGN, and the whole archive plus the
// practice collection as a single JSON document. The archive can at least be
// replayed from memory; the practice queue cannot. It accumulates one blunder
// at a time out of games actually played, so a reinstall without this file is
// not an inconvenience, it is the loss of the only thing here that took months
// to make.
//
// PORTED from svelte/src/lib/backup.ts rather than rewritten. The envelope is
// byte-compatible with the Svelte app's, so a backup taken from botvinnik.app
// before the Flutter port restores here — which was the other half of what
// that file was for ("doubles as migration between origins"). More
// importantly the MERGE is ported: which copy of a practice item wins when
// both sides have one is a decision about conflicting training history, and
// re-deriving it from scratch is how you quietly throw away the reps.
//
// The rules, verbatim from the source:
//
//   - practice dedupes by id, keeping the copy with MORE attempts — the one
//     that has been trained. Not the newer one, not the incoming one: reps are
//     the thing you cannot get back by playing again.
//   - games dedupe by id and the copy already here WINS. A stored game is
//     immutable once archived, so there is nothing an incoming duplicate could
//     carry that is better, and "restore" must never be able to damage what is
//     already on the device.
//   - merge, never clobber. Import is additive in both tables; nothing is
//     deleted, so restoring the wrong file costs you nothing but noise.

import 'dart:convert';

import '../db/app_db.dart';

/// The kv row the practice collection lives in.
///
/// A literal copy of `PracticeController`'s private `_kvKey`, which in turn is
/// the web app's localStorage key name. Two declarations of one string is a
/// drift hazard, so it is covered rather than commented at: the round-trip
/// test in test/backup_test.dart writes through [BackupService] and reads back
/// through a REAL PracticeController, and goes red if these ever disagree.
/// Reading the practice table straight from the db is what lets backup stay
/// out of the controller: import has to write the collection wholesale, and a
/// controller that owns a session (current puzzle, hint tier, attempt) is the
/// wrong place to hang "replace everything" on.
const kPracticeKvKey = 'botvinnik-practice-v1';

const kBackupApp = 'botvinnik';
const kBackupVersion = 1;

/// The file is not one of ours, or is not JSON at all. Carries a sentence fit
/// to show the user — a restore that fails silently is worse than one that
/// fails, because the user's next move is to reinstall.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// What an import actually added — reported back so "nothing happened" and
/// "everything was already here" are distinguishable, which they are not from
/// the outside.
typedef BackupCounts = ({int practice, int games});

/// `botvinnik-backup-2026-07-21.json`, the Svelte file's naming.
String backupFilename(DateTime at) =>
    'botvinnik-backup-${at.toIso8601String().substring(0, 10)}.json';

/// `botvinnik-You-vs-Squarefish-2026-07-21.pgn`.
///
/// Stripped to `[A-Za-z0-9_-]` per segment, as the Svelte version did: these
/// names carry persona names and imported PGN headers ("Kasparov, G."), and a
/// comma or a slash in a filename is a bug on some of the three platforms and
/// merely ugly on the rest.
String pgnFilename({String? white, String? black, required String endedAt}) {
  String seg(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  final date = endedAt.length >= 10 ? endedAt.substring(0, 10) : endedAt;
  return 'botvinnik-${seg(white ?? 'game')}-vs-${seg(black ?? 'bot')}'
      '-${seg(date)}.pgn';
}

/// Read [key] as a number, defaulting to 0.
///
/// The Svelte source is `item.attempts ?? 0`, which in JS also swallows a
/// string or a bool by comparing it with `>` under coercion. A backup file is
/// user-supplied text, so the Dart port refuses to cast instead: anything that
/// is not a number reads as 0, and an item with a junk `attempts` therefore
/// loses to any copy that has been trained rather than crashing the restore.
double _attempts(Map<String, dynamic> item) {
  final v = item['attempts'];
  return v is num ? v.toDouble() : 0;
}

/// The merge, in one pure function so the decision above can be tested without
/// a database.
///
/// Order is load-bearing and matches the JS `Map`: items already here keep
/// their positions (including when they are REPLACED by a better-trained
/// copy), and genuinely new items land at the end in file order. That is what
/// keeps a restore from silently reshuffling the queue.
({List<Map<String, dynamic>> items, int added}) mergePractice(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
) {
  // Keyed on the raw id, not on a String cast: a hand-edited file with a
  // missing id must not throw in the middle of a restore. This reproduces the
  // JS exactly, null key and all.
  final byId = <Object?, Map<String, dynamic>>{
    for (final i in existing) i['id']: i,
  };
  var added = 0;
  for (final item in incoming) {
    final cur = byId[item['id']];
    if (cur == null) {
      byId[item['id']] = item;
      added++;
    } else if (_attempts(item) > _attempts(cur)) {
      byId[item['id']] = item;
    }
  }
  return (items: byId.values.toList(), added: added);
}

/// Backup and restore over the store itself, both tables at once.
class BackupService {
  final AppDb _db;
  const BackupService(this._db);

  Future<List<Map<String, dynamic>>> _practice() async {
    final raw = await _db.kvGet(kPracticeKvKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((i) => (i as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      // PracticeController treats a corrupt row as an empty collection rather
      // than a crash; a backup of nothing is the honest export of that state.
      return [];
    }
  }

  /// The whole backup document.
  Future<Map<String, dynamic>> build({DateTime? at}) async => {
        'app': kBackupApp,
        'version': kBackupVersion,
        'exportedAt': (at ?? DateTime.now()).toIso8601String(),
        'practice': await _practice(),
        'games': await _db.listGames(),
      };

  Future<String> exportJson({DateTime? at}) async =>
      jsonEncode(await build(at: at));

  /// Merge [text] into the store. Throws [BackupFormatException] on anything
  /// that is not one of our files.
  Future<BackupCounts> importJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const BackupFormatException('That file is not JSON.');
    }
    // Same three conditions as the source, and no version check — the field is
    // written so a future format CAN be told apart, but rejecting on it today
    // would only reject the Svelte files this is meant to accept.
    if (decoded is! Map ||
        decoded['app'] != kBackupApp ||
        decoded['practice'] is! List ||
        decoded['games'] is! List) {
      throw const BackupFormatException('Not a botvinnik backup file.');
    }

    final incomingPractice = (decoded['practice'] as List)
        .whereType<Map>()
        .map((i) => i.cast<String, dynamic>())
        .toList();
    final merged = mergePractice(await _practice(), incomingPractice);
    await _db.kvPut(kPracticeKvKey, jsonEncode(merged.items));

    final have = (await _db.listGames()).map((g) => g['id']).toSet();
    var gamesAdded = 0;
    for (final g in (decoded['games'] as List).whereType<Map>()) {
      final game = g.cast<String, dynamic>();
      // AppDb.saveGame indexes on a parsed endedAt and keys on a String id, so
      // a truncated record would throw HALFWAY through the loop — leaving some
      // games restored, some not, and an error message where the counts should
      // be. Skipped instead: the file someone is restoring in a panic is
      // exactly the one likely to be damaged, and 40 of 41 games beats none.
      // `is! String` on endedAt as well as parseability: the interpolated form
      // stringifies, so a JSON NUMBER like 20260721 parsed fine here and then
      // threw on AppDb's `endedAt as String` — aborting the restore mid-loop,
      // which is the exact failure this guard exists to prevent. The test that
      // claimed to cover it passed only because its damaged fixture used an
      // unparseable string.
      if (game['id'] is! String ||
          game['endedAt'] is! String ||
          DateTime.tryParse(game['endedAt'] as String) == null) {
        continue;
      }
      // Deliberate deviation from the source, which never adds to this set and
      // so counts a file containing the same game twice as two additions. The
      // second write is an upsert either way; only the number shown to the
      // user was wrong.
      if (!have.add(game['id'])) continue;
      await _db.saveGame(game);
      gamesAdded++;
    }

    return (practice: merged.added, games: gamesAdded);
  }
}
