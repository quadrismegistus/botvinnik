// The Settings tab. Small on purpose — settings that belong to a specific
// flow (opponent, side) live in that flow's sheet; this is for the app-wide
// knobs.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show NormalMove, Side;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../stores/practice_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final practice = context.watch<PracticeController>();
    final belowThreshold = practice.items.length - practice.servable.length;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const _SectionLabel('Board'),
        SwitchListTile(
          dense: true,
          title: const Text('Engine arrows'),
          subtitle: const Text(
            'The engine\'s top three moves, green fading by rank.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showArrows,
          onChanged: (v) => settings.showArrows = v,
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Threat arrow'),
          subtitle: const Text(
            'What the opponent would do with a free move, when it wins material.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showThreats,
          onChanged: (v) => settings.showThreats = v,
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Square control'),
          subtitle: const Text(
            'Tint squares each side safely controls — green yours, red theirs.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showControl,
          onChanged: (v) => settings.showControl = v,
        ),
        const _SectionLabel('Board colors'),
        const _BoardColorSection(),
        const _SectionLabel('Practice'),
        ListTile(
          dense: true,
          title: const Text('Practice mistakes losing at least'),
          subtitle: Text(
            'Everything ≥5% is collected; this filters which puzzles '
            'you actually drill.'
            '${belowThreshold > 0 ? ' ($belowThreshold collected below the current bar)' : ''}',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          trailing: DropdownButton<int>(
            value: settings.collectThreshold,
            underline: const SizedBox(),
            items: const [5, 10, 15, 20, 30]
                .map((v) =>
                    DropdownMenuItem(value: v, child: Text('$v% win chance')))
                .toList(),
            onChanged: (v) {
              if (v != null) settings.collectThreshold = v;
            },
          ),
        ),
        ListTile(
          dense: true,
          title: const Text('Collected puzzles'),
          subtitle: Text(
            '${practice.items.length} total · ${practice.servable.length} above the bar · ${practice.due} due',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
        ),
      ],
    );
  }
}

/// Square and highlight colors, with a live board sample — the real board is
/// on another tab, so the sample is what makes a change legible while you
/// are choosing it. Edits apply as you drag, and Cancel puts the color back.
class _BoardColorSection extends StatelessWidget {
  const _BoardColorSection();

  static const _sampleFen =
      'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              StaticChessboard(
                size: 132,
                fen: _sampleFen,
                lastMove: NormalMove.fromUci('e2e4'),
                orientation: Side.white,
                settings: staticBoardSettingsFor(s),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Swatch(
                      label: 'Light squares',
                      color: s.lightSquare,
                      onPick: (c) => s.lightSquare = c,
                    ),
                    _Swatch(
                      label: 'Dark squares',
                      color: s.darkSquare,
                      onPick: (c) => s.darkSquare = c,
                    ),
                    _Swatch(
                      label: 'Last move',
                      color: s.lastMoveColor,
                      withAlpha: true,
                      onPick: (c) => s.lastMoveColor = c,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kBoardPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = kBoardPresets[i];
              final selected = p.light.toARGB32() == s.lightSquare.toARGB32() &&
                  p.dark.toARGB32() == s.darkSquare.toARGB32();
              return _PresetChip(
                preset: p,
                selected: selected,
                onTap: () => s.applySquares(p.light, p.dark),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Row(
            children: [
              const Text('Pieces', style: TextStyle(fontSize: 13)),
              const Spacer(),
              DropdownButton<String>(
                value: pieceSetFor(s).name,
                underline: const SizedBox(),
                isDense: true,
                items: PieceSet.values
                    .map((p) => DropdownMenuItem(
                          value: p.name,
                          child: Text(p.label,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) s.pieceSet = v;
                },
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 4),
            child: TextButton(
              onPressed: s.resetBoardColors,
              child: const Text('Reset to default'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A preset shown as what it is: four squares of the actual board.
class _PresetChip extends StatelessWidget {
  final BoardPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? const Color(0xFF81B64C) : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(children: [
                  _cell(preset.light),
                  _cell(preset.dark),
                ]),
                Row(children: [
                  _cell(preset.dark),
                  _cell(preset.light),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(preset.name,
              style: TextStyle(
                fontSize: 10,
                color: selected ? const Color(0xFF81B64C) : Colors.white54,
              )),
        ],
      ),
    );
  }

  Widget _cell(Color c) => Container(width: 15, height: 15, color: c);
}

class _Swatch extends StatelessWidget {
  final String label;
  final Color color;
  final bool withAlpha;
  final ValueChanged<Color> onPick;
  const _Swatch({
    required this.label,
    required this.color,
    required this.onPick,
    this.withAlpha = false,
  });

  Future<void> _open(BuildContext context) async {
    final original = color;
    final restored = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f1e1b),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: original,
            onColorChanged: onPick, // live: the sample repaints as you drag
            enableAlpha: withAlpha,
            hexInputBar: true,
            portraitOnly: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (restored ?? true) onPick(original);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // checker behind the chip so a translucent color reads as one
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF3a3733),
              ),
              child: Container(
                width: 26,
                height: 18,
                margin: const EdgeInsets.all(1),
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              color: Colors.white38,
              fontWeight: FontWeight.w600)),
    );
  }
}
