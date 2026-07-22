// The "Pick a bot" modal, family-first.
//
// Page one is a short list of opponents with a line of description each:
//  - families that are a smooth ELO ladder (Squarefish/Stockfish/Horizon —
//    whose persona name is literally "<family> <elo>") collapse to ONE row that
//    opens a strength slider;
//  - families that are DISTINCT opponents rather than a dial (Maia's nets,
//    Retro's 1948–78 engines), plus single bots and each custom engine, are
//    listed directly — you pick the one you want.
//
// Every choice resolves to the SAME persona id the roster always used, so
// calibration, the per-bot W-L-D records (#142) and crowns are untouched. The
// flat list with those records is still one tap away via "Browse all".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../stores/game_controller.dart';
import 'roster_picker.dart' show pickBot;

/// Families that are a set of distinct opponents, never a strength slider.
const _variant = {'maia', 'retro'};
const _accent = Color(0xFF81B64C);

/// Short, family-level copy for the slider families; a listed member uses its
/// own blurb instead.
const _familyDesc = <String, String>{
  'squarefish':
      'Sound but tactically fallible — set the rating and it misses more, or less.',
  'stockfish':
      'Stockfish with the strength limiter on — cold and accurate at whatever rating you pick.',
  'horizon': 'A shallow-searching engine — a couple of strengths.',
  'dala': 'A neural net dialled to a rating band.',
};

/// Pick an opponent, family-first. Returns the chosen persona id, or null.
Future<String?> pickBotFamily(BuildContext context, {String? current}) {
  final game = context.read<GameController>();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => _FamilyPicker(game: game, current: current),
  );
}

class _FamilyPicker extends StatefulWidget {
  final GameController game;
  final String? current;
  const _FamilyPicker({required this.game, required this.current});

  @override
  State<_FamilyPicker> createState() => _FamilyPickerState();
}

class _FamilyPickerState extends State<_FamilyPicker> {
  /// Null = the list; a family key = its strength sub-page.
  String? _sliderFamily;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: _sliderFamily == null ? _list() : _slider(_sliderFamily!),
      ),
    );
  }

  // ---- page one: the opponent list ----------------------------------------

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
              for (final e in entries)
                if (e.members != null)
                  _row(
                    icon: _familyIcon(e.family),
                    color: _familyColor(e.family),
                    title: _familyLabel(e.family),
                    subtitle: _familyDesc[e.family] ??
                        e.members![e.members!.length ~/ 2].blurb,
                    trailing: const Icon(Icons.chevron_right,
                        size: 20, color: Colors.white38),
                    onTap: () => setState(() => _sliderFamily = e.family),
                  )
                else
                  _row(
                    icon: _familyIcon(e.persona!.family),
                    color: _familyColor(e.persona!.family),
                    title: '${e.persona!.name}  ·  ${e.persona!.elo}',
                    subtitle: e.persona!.blurb,
                    onTap: () => Navigator.pop(context, e.persona!.id),
                  ),
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

  Future<void> _browseAll() async {
    final id = await pickBot(context, current: widget.current);
    if (id != null && mounted) Navigator.pop(context, id);
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(icon, size: 22, color: color),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
        trailing: trailing,
        onTap: onTap,
      );

  // ---- page two: the strength slider --------------------------------------

  Widget _slider(String family) {
    final members = _membersOf(family);
    // Default to the current pick if it is in this family, else the median.
    var i = members.indexWhere((m) => m.id == widget.current);
    if (i < 0) i = members.length ~/ 2;

    return StatefulBuilder(
      builder: (context, setInner) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() => _sliderFamily = null),
              ),
              Text(_familyLabel(family),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${members[i].elo}',
                  style: const TextStyle(
                      fontSize: 20,
                      color: _accent,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 12),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, members[i].id),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF161512),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Play ${members[i].name}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ---- grouping ------------------------------------------------------------

  List<_Entry> _entries() {
    final byFamily = <String, List<Persona>>{};
    for (final p in widget.game.rosterPersonas) {
      (byFamily[p.family] ??= []).add(p);
    }
    final out = <_Entry>[];
    byFamily.forEach((family, members) {
      members.sort((a, b) => a.elo.compareTo(b.elo));
      // A slider only for a real ELO ladder: several members, one engine, not a
      // set of distinct opponents.
      if (members.length >= 2 && !_variant.contains(family) && family != 'custom') {
        out.add(_Entry.family(family, members));
      } else {
        for (final p in members) {
          out.add(_Entry.persona(p));
        }
      }
    });
    // Gentlest first, like the roster.
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

class _Entry {
  final String family;

  /// Non-null for a slider family (its members); null for a direct pick.
  final List<Persona>? members;

  /// Non-null for a direct pick.
  final Persona? persona;

  _Entry.family(this.family, this.members) : persona = null;
  _Entry.persona(Persona p)
      : persona = p,
        family = p.family,
        members = null;

  /// Sort key: a family by its median strength, a direct pick by its own.
  int get sortElo =>
      members != null ? members![members!.length ~/ 2].elo : persona!.elo;
}

// The family's glyph + colour, matching the roster headings.
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
