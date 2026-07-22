// The "Pick a bot" modal, family-first, several shapes of second page.
//
// Page one lists opponents with a line of description each. Tapping one goes to:
//  - a STRENGTH SLIDER, for a family that is a smooth ELO ladder — Squarefish,
//    Stockfish, Horizon, and Maia (its nets, ordered by rating);
//  - a SECOND-PAGE LIST, for a family whose members are distinct opponents, not
//    a dial — Retro's 1948-78 engines;
//  - "More engines", a SECOND-PAGE LIST of the downloaded / hand-added UCI
//    engines (lowest reachable rating first), each opening its own cap page;
//  - a CAP page, for one such engine: a rating slider ONLY when the engine
//    actually implements UCI_Elo (verified in the catalog — Velvet does), over
//    exactly its advertised range; otherwise an honest "full strength, no cap"
//    note rather than a slider the engine would silently ignore.
// A single bot with nothing to choose is picked straight from page one.
//
// Every path returns the roster's own persona id, so calibration, the per-bot
// W-L-D records (#142) and crowns are untouched. "Browse all" drops to the flat
// roster (with those records), unchanged.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../stores/custom_engine.dart';
import '../stores/engine_catalog.dart';
import '../stores/game_controller.dart';
import 'roster_picker.dart' show pickBot;

/// Families whose members are distinct opponents shown on a second page, never
/// dialled — Maia is deliberately NOT here now (it is an ELO slider).
const _listFamilies = {'retro'};
const _accent = Color(0xFF81B64C);

/// Short, family-level copy for the slider families; a listed member or a
/// custom engine uses its own blurb.
const _familyDesc = <String, String>{
  'squarefish':
      'Sound but tactically fallible — set the rating and it misses more, or less.',
  'stockfish':
      'Stockfish with the strength limiter on — cold and accurate at whatever rating you pick.',
  'horizon': 'A shallow-searching engine — a couple of strengths.',
  'maia': 'Neural nets that move like real humans of a given rating — slide to pick one.',
  'dala': 'A neural net dialled to a rating band.',
};

Future<String?> pickBotFamily(BuildContext context, {String? current}) {
  final game = context.read<GameController>();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => _FamilyPicker(game: game, current: current),
  );
}

enum _SubKind { slider, list, custom, moreEngines }

class _FamilyPicker extends StatefulWidget {
  final GameController game;
  final String? current;
  const _FamilyPicker({required this.game, required this.current});

  @override
  State<_FamilyPicker> createState() => _FamilyPickerState();
}

class _FamilyPickerState extends State<_FamilyPicker> {
  /// Null = the list. Otherwise the second page: (kind, family-or-personaId).
  (_SubKind, String)? _sub;

  // Custom-engine cap page state, seeded when it is opened.
  bool _capOn = false;
  int _capElo = 1500;

  @override
  Widget build(BuildContext context) {
    final sub = _sub;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: sub == null
            ? _list()
            : switch (sub.$1) {
                _SubKind.slider => _sliderPage(sub.$2),
                _SubKind.list => _listPage(sub.$2),
                _SubKind.custom => _customPage(sub.$2),
                _SubKind.moreEngines => _moreEnginesPage(),
              },
      ),
    );
  }

  // ---- page one ------------------------------------------------------------

  Widget _list() {
    final entries = _entries();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text('Pick a bot',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries) _entryRow(e),
              const Divider(height: 12, color: Color(0xFF3a3733)),
              ListTile(
                dense: true,
                leading: const Icon(Icons.list, size: 20, color: Colors.white38),
                title: const Text('Browse all…', style: TextStyle(fontSize: 13)),
                subtitle: const Text('The full roster, with your record vs each.',
                    style: TextStyle(fontSize: 11, color: Colors.white38)),
                onTap: _browseAll,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entryRow(_Entry e) {
    final chevron =
        const Icon(Icons.chevron_right, size: 20, color: Colors.white38);
    switch (e.kind) {
      case _Kind.slider:
        return _row(e.family,
            title: _familyLabel(e.family),
            subtitle: _familyDesc[e.family] ??
                e.members[e.members.length ~/ 2].blurb,
            trailing: chevron,
            onTap: () => setState(() => _sub = (_SubKind.slider, e.family)));
      case _Kind.list:
        return _row(e.family,
            title: _familyLabel(e.family),
            subtitle: _familyDesc[e.family] ?? e.members.first.blurb,
            trailing: chevron,
            onTap: () => setState(() => _sub = (_SubKind.list, e.family)));
      case _Kind.moreEngines:
        // All downloaded / hand-added engines behind one row, opened as a
        // second-page list rather than one loose row each.
        return _row(e.family,
            title: 'More engines',
            subtitle: 'Downloaded and custom UCI engines — '
                '${e.members.length} available.',
            trailing: chevron,
            onTap: () => setState(() => _sub = (_SubKind.moreEngines, '')));
      case _Kind.direct:
        final p = e.persona!;
        return _row(p.family,
            title: '${p.name}  ·  ${p.elo}',
            subtitle: p.blurb,
            onTap: () => Navigator.pop(context, p.id));
    }
  }

  Future<void> _browseAll() async {
    final id = await pickBot(context, current: widget.current);
    if (id != null && mounted) Navigator.pop(context, id);
  }

  Widget _row(String family,
          {required String title,
          required String subtitle,
          Widget? trailing,
          required VoidCallback onTap}) =>
      ListTile(
        dense: true,
        leading: Icon(_familyIcon(family), size: 22, color: _familyColor(family)),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
        trailing: trailing,
        onTap: onTap,
      );

  Widget _backBar(String title, {VoidCallback? onBack}) => Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: onBack ?? () => setState(() => _sub = null),
          ),
          // Expanded + ellipsis: a custom engine's name is free text with no
          // length limit, and a long one otherwise overflows the sheet width.
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      );

  // ---- second page: strength slider (ELO families) -------------------------

  Widget _sliderPage(String family) {
    final members = _membersOf(family);
    var i = members.indexWhere((m) => m.id == widget.current);
    if (i < 0) i = members.length ~/ 2;

    return StatefulBuilder(
      builder: (context, setInner) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _backBar(_familyLabel(family))),
              Text('${members[i].elo}',
                  style: const TextStyle(
                      fontSize: 20,
                      color: _accent,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 12),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(members[i].blurb,
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ),
          Slider(
            value: i.toDouble(),
            min: 0,
            max: (members.length - 1).toDouble(),
            divisions: members.length - 1,
            label: '${members[i].elo}',
            activeColor: _accent,
            onChanged: (v) => setInner(() => i = v.round()),
          ),
          _playButton(members[i].name, () => Navigator.pop(context, members[i].id)),
        ],
      ),
    );
  }

  // ---- second page: a list of distinct members (Retro) ---------------------

  Widget _listPage(String family) {
    final members = _membersOf(family);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBar(_familyLabel(family)),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in members)
                _row(family,
                    title: '${m.name}  ·  ${m.elo}',
                    subtitle: m.blurb,
                    onTap: () => Navigator.pop(context, m.id)),
            ],
          ),
        ),
      ],
    );
  }

  // ---- second page: the downloaded / custom engines, weakest-first ---------

  Widget _moreEnginesPage() {
    // Lowest reachable rating first: an engine that dials down (Velvet) floats
    // above the full-strength crushers, so what a human can actually play sits
    // at the top.
    final engines = _membersOf('custom')
      ..sort((a, b) => _lowestElo(a).compareTo(_lowestElo(b)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBar('More engines'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in engines)
                _row('custom',
                    title: p.name,
                    subtitle: _engineStrengthLine(p),
                    trailing: const Icon(Icons.chevron_right,
                        size: 20, color: Colors.white38),
                    onTap: () => _openCustom(p)),
            ],
          ),
        ),
      ],
    );
  }

  /// Seed the cap page for [p] and open it. The seed lands inside the engine's
  /// real range so the slider never shows a rating it could not play.
  void _openCustom(Persona p) {
    final cfg = context.read<CustomEngineStore>().byPersonaId(p.id);
    final entry = catalogEntryById(cfg?.id);
    final seed = cfg?.elo ?? p.elo;
    setState(() {
      _capOn = cfg?.limitElo ?? false;
      _capElo = entry != null && entry.capsElo
          ? seed.clamp(entry.eloMin, entry.eloMax).toInt()
          : seed.clamp(600, 3200).toInt();
      _sub = (_SubKind.custom, p.id);
    });
  }

  /// The lowest rating a custom engine can be played at: its cap floor if it
  /// dials down, else its (fixed) full-strength rating.
  int _lowestElo(Persona p) {
    final entry = catalogEntryById(_engineId(p));
    return entry != null && entry.capsElo ? entry.eloMin : p.elo;
  }

  /// The one-line strength summary under an engine on the More-engines list.
  String _engineStrengthLine(Persona p) {
    final entry = catalogEntryById(_engineId(p));
    if (entry == null) return p.blurb; // hand-added: capability unknown
    return entry.capsElo
        ? 'Dials ${entry.eloMin}–${entry.eloMax}'
        : 'Full strength · ${p.elo}';
  }

  /// The catalog id behind a custom persona (`custom-velvet` → `velvet`).
  static String _engineId(Persona p) =>
      p.id.startsWith(CustomEngine.personaPrefix)
          ? p.id.substring(CustomEngine.personaPrefix.length)
          : p.id;

  // ---- second page: a custom engine's UCI_Elo cap --------------------------

  Widget _customPage(String personaId) {
    final store = context.read<CustomEngineStore>();
    final cfg = store.byPersonaId(personaId);
    if (cfg == null) return _list(); // removed under us

    final entry = catalogEntryById(cfg.id);

    // A catalogued engine we KNOW cannot cap (verified against its source): no
    // slider that would silently do nothing, just the fact. Saving forces the
    // cap off so a stale saved rating can never reappear as a false label.
    if (entry != null && !entry.capsElo) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backBar(cfg.name,
              onBack: () => setState(() => _sub = (_SubKind.moreEngines, ''))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              '${cfg.name} has no rating limiter, so it always plays at full '
              'strength (about ${cfg.elo}). There is nothing to dial down.',
              style: const TextStyle(fontSize: 12.5, color: Colors.white54),
            ),
          ),
          _playButton(cfg.name, () async {
            if (cfg.limitElo) await store.upsert(cfg.copyWith(limitElo: false));
            if (mounted) Navigator.pop(context, personaId);
          }),
        ],
      );
    }

    // A capping engine dials over its ADVERTISED range; an unknown hand-added
    // engine keeps the honest "may be ignored" hedge over a generic range.
    final caps = entry != null && entry.capsElo;
    final (capMin, capMax) = caps ? (entry.eloMin, entry.eloMax) : (600, 3200);
    final capSubtitle = caps
        ? 'Dials ${cfg.name} between $capMin and $capMax via UCI_Elo.'
        : 'Sends UCI_Elo. Works only if this engine supports it — full strength '
            'otherwise.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backBar(cfg.name),
        SwitchListTile(
          dense: true,
          title: const Text('Cap strength', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            capSubtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          activeThumbColor: _accent,
          value: _capOn,
          onChanged: (v) => setState(() => _capOn = v),
        ),
        if (_capOn)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _capElo
                      .toDouble()
                      .clamp(capMin.toDouble(), capMax.toDouble()),
                  min: capMin.toDouble(),
                  max: capMax.toDouble(),
                  divisions: ((capMax - capMin) / 25).round(),
                  label: '$_capElo',
                  activeColor: _accent,
                  onChanged: (v) => setState(() => _capElo = v.round()),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text('$_capElo',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 14,
                        color: _accent,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 12),
            ],
          ),
        _playButton(cfg.name, () async {
          // Only write the rating when the cap is ON — otherwise toggling the
          // cap off would rewrite the saved rating with a slider value that was
          // never applied, so the Engines screen would show a strength the
          // engine never played at.
          await store.upsert(cfg.copyWith(
              limitElo: _capOn, elo: _capOn ? _capElo : cfg.elo));
          if (mounted) Navigator.pop(context, personaId);
        }),
      ],
    );
  }

  Widget _playButton(String name, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF161512),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Text('Play $name',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  // ---- grouping ------------------------------------------------------------

  List<_Entry> _entries() {
    final byFamily = <String, List<Persona>>{};
    for (final p in widget.game.rosterPersonas) {
      (byFamily[p.family] ??= []).add(p);
    }
    final out = <_Entry>[];
    byFamily.forEach((family, members) {
      members.sort((a, b) => a.elo.compareTo(b.elo));
      if (family == 'custom') {
        // One "More engines" row; the engines themselves live on its sub-page.
        out.add(_Entry(_Kind.moreEngines, family, members, null));
      } else if (_listFamilies.contains(family)) {
        out.add(_Entry(_Kind.list, family, members, null));
      } else if (members.length >= 2) {
        out.add(_Entry(_Kind.slider, family, members, null));
      } else {
        for (final p in members) {
          out.add(_Entry(_Kind.direct, family, const [], p));
        }
      }
    });
    out.sort((a, b) => a.sortElo.compareTo(b.sortElo));
    return out;
  }

  List<Persona> _membersOf(String family) => widget.game.rosterPersonas
      .where((p) => p.family == family)
      .toList()
    ..sort((a, b) => a.elo.compareTo(b.elo));

  static String _familyLabel(String f) =>
      f.isEmpty ? f : f[0].toUpperCase() + f.substring(1);
}

enum _Kind { slider, list, direct, moreEngines }

class _Entry {
  final _Kind kind;
  final String family;
  final List<Persona> members; // slider / list
  final Persona? persona; // custom / direct
  const _Entry(this.kind, this.family, this.members, this.persona);

  int get sortElo => persona?.elo ?? members[members.length ~/ 2].elo;
}

IconData _familyIcon(String family) => switch (family) {
      'squarefish' => Icons.grid_view,
      'stockfish' => Icons.diamond_outlined,
      'horizon' => Icons.wb_twilight,
      'retro' => Icons.memory,
      'garbo' => Icons.data_object,
      'maia' => Icons.psychology_outlined,
      'custom' => Icons.terminal,
      _ => Icons.smart_toy_outlined,
    };

Color _familyColor(String family) => switch (family) {
      'squarefish' => const Color(0xFFd0b755),
      'stockfish' => const Color(0xFF5b8bb0),
      'horizon' => const Color(0xFFc4783f),
      'retro' => const Color(0xFF9a7bb0),
      'garbo' => const Color(0xFF6f9e8a),
      'maia' => const Color(0xFFb06f8a),
      'custom' => const Color(0xFF7d8fa0),
      _ => Colors.white38,
    };
