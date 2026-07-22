// Inline opponent picker for the New Game sheet: choose You or a bot FAMILY,
// then dial the strength beside it — a slider for the families where strength
// is a real continuous axis (Squarefish/Stockfish/Horizon: the persona name is
// literally "<family> <elo>"), a segmented pick for the ones that are distinct
// opponents rather than a dial (Maia's nets, Retro's historical engines).
//
// It resolves to the SAME personas the roster always used (squarefish-1500,
// maia-1900, custom-<id>…), so calibration, the per-bot W-L-D records and the
// crowns are untouched — this is a nicer selector, not a new model. The full
// list, with those records, stays one tap away behind "Browse all".
//
// W-L-D / crowns beside the slider, and a custom engine's own UCI_Elo cap here,
// are deliberate fast-follows (this is "just the slider" first).

import 'package:flutter/material.dart';

import '../brain/types.dart';
import '../stores/game_controller.dart';

/// Families that are a set of DISTINCT opponents, not one engine dialled up and
/// down — shown as a segmented pick, never a strength slider.
const _variantFamilies = {'maia', 'retro'};

const _accent = Color(0xFF81B64C);

class BotPicker extends StatelessWidget {
  final String label; // 'White' / 'Black'
  final GameController game;

  /// The selected persona id, or null for the human.
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  /// Opens the full roster modal (records, crowns, near-your-level).
  final VoidCallback onBrowseAll;

  const BotPicker({
    super.key,
    required this.label,
    required this.game,
    required this.selectedId,
    required this.onChanged,
    required this.onBrowseAll,
  });

  @override
  Widget build(BuildContext context) {
    final options = _options();
    final selected = selectedId == null ? null : game.personaFor(selectedId);
    final selectedKey = selected == null ? null : _keyOf(selected);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                  width: 46,
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70))),
              const Spacer(),
              TextButton(
                onPressed: onBrowseAll,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Browse all…', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('You', selectedId == null, () => onChanged(null)),
              for (final o in options)
                _chip(o.label, selectedKey == o.key, () => onChanged(o.pick.id)),
            ],
          ),
          if (selected != null) _strength(selected),
        ],
      ),
    );
  }

  Widget _strength(Persona selected) {
    final family = selected.family;
    final members = _familyMembers(family);
    if (members.length < 2) return const SizedBox.shrink(); // nothing to dial

    if (_variantFamilies.contains(family) || members.length == 2) {
      // Distinct opponents (or just two levels): a segmented pick, labelled.
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 46),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in members)
              _chip(_variantFamilies.contains(family) ? m.name : '${m.elo}',
                  m.id == selected.id, () => onChanged(m.id)),
          ],
        ),
      );
    }

    // A real strength axis: a slider snapping to the calibrated steps.
    final i = members.indexWhere((m) => m.id == selected.id);
    final cur = i < 0 ? 0 : i;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 40),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: cur.toDouble(),
              min: 0,
              max: (members.length - 1).toDouble(),
              divisions: members.length - 1,
              label: '${members[cur].elo}',
              activeColor: _accent,
              onChanged: (v) => onChanged(members[v.round()].id),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text('${members[cur].elo}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    color: _accent,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }

  // ---- options + grouping ---------------------------------------------------

  /// The picker's top-level choices: one per built-in family, and each custom
  /// engine on its own (they are individual engines, not a graded family).
  List<_Option> _options() {
    final byFamily = <String, List<Persona>>{};
    final custom = <Persona>[];
    for (final p in game.rosterPersonas) {
      if (p.family == 'custom') {
        custom.add(p);
      } else {
        (byFamily[p.family] ??= []).add(p);
      }
    }
    final out = <_Option>[];
    for (final entry in byFamily.entries) {
      final members = [...entry.value]..sort((a, b) => a.elo.compareTo(b.elo));
      // Default a family to its median strength; the slider takes it from there.
      final pick = members[members.length ~/ 2];
      out.add(_Option(
        key: 'family:${entry.key}',
        label: _familyLabel(entry.key),
        pick: pick,
      ));
    }
    for (final p in custom) {
      out.add(_Option(key: 'custom:${p.id}', label: p.name, pick: p));
    }
    return out;
  }

  List<Persona> _familyMembers(String family) {
    if (family == 'custom') return const []; // a custom engine is a single pick
    final members = game.rosterPersonas
        .where((p) => p.family == family)
        .toList()
      ..sort((a, b) => a.elo.compareTo(b.elo));
    return members;
  }

  String _keyOf(Persona p) =>
      p.family == 'custom' ? 'custom:${p.id}' : 'family:${p.family}';

  static String _familyLabel(String family) =>
      family.isEmpty ? family : family[0].toUpperCase() + family.substring(1);

  Widget _chip(String text, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                color: selected ? const Color(0xFF161512) : Colors.white70)),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: const Color(0xFF1f1e1b),
        selectedColor: _accent,
        side: BorderSide(
            color: selected ? _accent : const Color(0xFF3a3733)),
      );
}

class _Option {
  /// Stable identity of the top-level choice ('family:squarefish' / 'custom:…').
  final String key;
  final String label;

  /// The persona selecting this option lands on (the family's median, or the
  /// engine itself); the strength control refines it from there.
  final Persona pick;

  const _Option({required this.key, required this.label, required this.pick});
}
