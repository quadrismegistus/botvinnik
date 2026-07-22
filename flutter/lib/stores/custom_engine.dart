// Player-added UCI engines, and the store that persists them.
//
// A custom engine is any UCI binary the player points the app at — Viridithas,
// a dev build, another Stockfish. It joins the roster as a `custom`-family
// persona and plays as an opponent through a ProcessEngine (native desktop);
// the config here is transport-agnostic, so the Phase 2 server transport reuses
// it unchanged. It is NEVER the analysis engine — only an opponent.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../brain/types.dart';
import '../db/app_db.dart';
import 'engine_catalog.dart';

@immutable
class CustomEngine {
  /// Stable across renames; the persona id is derived from it.
  final String id;
  final String name;

  /// The UCI binary. A path on native; on the Phase 2 server transport this is
  /// the server-side engine key instead.
  final String path;

  /// Display rating, and the [UCI_Elo] target when [limitElo] is set.
  final int elo;

  /// Thinking time per move, milliseconds.
  final int movetimeMs;

  /// Send `UCI_LimitStrength true` + `UCI_Elo <elo>` before each `go`, so a
  /// strong engine can be dialled to its labelled rating. Only takes effect if
  /// the engine advertises those options (Viridithas does); ignored otherwise,
  /// which is why it is opt-in — an engine that ignores it plays full strength
  /// and the label would lie.
  final bool limitElo;

  const CustomEngine({
    required this.id,
    required this.name,
    required this.path,
    this.elo = 1500,
    this.movetimeMs = 1000,
    this.limitElo = false,
  });

  static const personaPrefix = 'custom-';
  String get personaId => '$personaPrefix$id';

  /// A roster persona backed by this engine. The blurb names the binary so two
  /// engines with the same display name are still tellable apart.
  Persona toPersona() => Persona({
        'id': personaId,
        'name': name,
        'elo': elo,
        'family': 'custom',
        'blurb': 'Your engine · ${_basename(path)}',
      });

  CustomEngine copyWith({
    String? name,
    String? path,
    int? elo,
    int? movetimeMs,
    bool? limitElo,
  }) =>
      CustomEngine(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        elo: elo ?? this.elo,
        movetimeMs: movetimeMs ?? this.movetimeMs,
        limitElo: limitElo ?? this.limitElo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'elo': elo,
        'movetimeMs': movetimeMs,
        'limitElo': limitElo,
      };

  factory CustomEngine.fromJson(Map<String, dynamic> j) => CustomEngine(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
        elo: (j['elo'] as num?)?.toInt() ?? 1500,
        movetimeMs: (j['movetimeMs'] as num?)?.toInt() ?? 1000,
        limitElo: j['limitElo'] as bool? ?? false,
      );

  static String _basename(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }
}

/// The player's custom engines, persisted in [AppDb]'s kv store and exposed as
/// roster personas. Watched by the roster picker and the settings screen, so an
/// add / edit / remove reflows both.
class CustomEngineStore extends ChangeNotifier {
  final AppDb _db;
  static const _kvKey = 'custom_engines';

  List<CustomEngine> _engines = const [];
  bool _loaded = false;

  CustomEngineStore(this._db) {
    _load();
  }

  /// Whether the initial read from disk has completed. The roster tolerates
  /// `false` (an empty list until it lands, then a notify), so nothing blocks
  /// boot on it.
  bool get isLoaded => _loaded;

  List<CustomEngine> get engines => List.unmodifiable(_engines);

  /// One persona per engine — EXCEPT an engine whose catalog entry declares
  /// named styles (Rodent, BrainLearn), which becomes one persona per style,
  /// all sharing the one binary. A style persona's id is
  /// `custom-<engine>~<styleKey>`, and its family is the engine's own id.
  List<Persona> get personas => _engines.expand((e) {
        final entry = catalogEntryById(e.id);
        if (entry != null && entry.personalities.isNotEmpty) {
          return entry.personalities.map((p) => _stylePersona(e, p, entry));
        }
        return [e.toPersona()];
      }).toList(growable: false);

  Persona _stylePersona(
          CustomEngine e, EnginePersonality p, EngineCatalogEntry entry) =>
      Persona({
        'id': '${e.personaId}~${p.key}',
        'name': p.name,
        // Strength is one engine-wide dial shared by every style: when the
        // player has capped the engine, all its styles show that rating;
        // otherwise the catalog's full-strength figure.
        'elo': e.limitElo ? e.elo : entry.elo,
        // Its own family (the engine id), so the picker groups Rodent's styles
        // apart from BrainLearn's.
        'family': entry.id,
        'blurb': p.blurb,
      });

  /// The engine a `custom-…` persona id is backed by, or null — used by the
  /// controller to route a move, and to tell a stale saved id from a live one.
  /// A style persona (`custom-rodent~tal`) resolves to its shared binary.
  CustomEngine? byPersonaId(String? personaId) {
    if (personaId == null ||
        !personaId.startsWith(CustomEngine.personaPrefix)) {
      return null;
    }
    // Drop any `~style` suffix: every style shares the one engine record.
    final id = personaId
        .substring(CustomEngine.personaPrefix.length)
        .split('~')
        .first;
    for (final e in _engines) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The UCI option a style persona sends before each search
  /// (`custom-rodent~tal` -> `PersonalityFile value tal.txt`,
  /// `custom-brainlearn~mcts` -> `MCTS value true`), or null for a plain
  /// single-style engine. Resolved from the catalog, so it survives a persona id
  /// that outlived a since-removed style.
  String? styleOptionFor(String? personaId) {
    if (personaId == null ||
        !personaId.startsWith(CustomEngine.personaPrefix)) {
      return null;
    }
    final rest = personaId.substring(CustomEngine.personaPrefix.length);
    final tilde = rest.indexOf('~');
    if (tilde < 0) return null;
    final entry = catalogEntryById(rest.substring(0, tilde));
    if (entry == null) return null;
    final key = rest.substring(tilde + 1);
    for (final p in entry.personalities) {
      if (p.key == key) return p.setoption;
    }
    return null;
  }

  Future<void> upsert(CustomEngine engine) async {
    final i = _engines.indexWhere((e) => e.id == engine.id);
    _engines = i >= 0
        ? (List.of(_engines)..[i] = engine)
        : [..._engines, engine];
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _engines = _engines.where((e) => e.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final raw = await _db.kvGet(_kvKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _engines = list.map(CustomEngine.fromJson).toList();
      }
    } catch (_) {
      // A corrupt document starts the player over rather than crashing boot;
      // the next upsert overwrites it.
      _engines = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() => _db.kvPut(
      _kvKey, jsonEncode(_engines.map((e) => e.toJson()).toList()));

  /// A fresh id. Time-based rather than a running counter so it needs no prior
  /// read of the list and never collides across a delete-then-add.
  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
