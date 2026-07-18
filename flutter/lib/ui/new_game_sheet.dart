// The new-game sheet (from the + button): pick the opponent, pick your
// side — White, Black, or no bot at all (analysis board) — and start.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import '../stores/settings_store.dart';
import 'roster_picker.dart';

void showNewGameSheet(BuildContext context) {
  final game = context.read<GameController>();
  final settings = context.read<SettingsStore>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    builder: (_) => _NewGameSheet(game: game, settings: settings),
  );
}

class _NewGameSheet extends StatefulWidget {
  final GameController game;
  final SettingsStore settings;
  const _NewGameSheet({required this.game, required this.settings});

  @override
  State<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends State<_NewGameSheet> {
  late String _mode = widget.settings.botEnabled
      ? (widget.settings.playerColor == 'w' ? 'white' : 'black')
      : 'analysis';

  @override
  Widget build(BuildContext context) {
    final persona = widget.game.persona;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.smart_toy_outlined, color: Colors.white70),
              title: Text(persona == null
                  ? 'Choose opponent'
                  : '${persona.name} · ${persona.elo}'),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () => showRosterPicker(context),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'white', label: Text('You: White')),
                ButtonSegment(value: 'black', label: Text('You: Black')),
                ButtonSegment(value: 'analysis', label: Text('Analysis')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFF3a3733),
                selectedForegroundColor: const Color(0xFF81B64C),
                foregroundColor: Colors.white54,
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            if (_mode == 'analysis')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'No opponent — you move both sides, every move still graded.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final s = widget.settings;
                // set fields, then start explicitly — GameController reacts
                // to the settings change with a newGame of its own; the
                // explicit call covers the nothing-changed case
                s.botEnabled = _mode != 'analysis';
                if (_mode != 'analysis') {
                  s.playerColor = _mode == 'white' ? 'w' : 'b';
                }
                widget.game.newGame();
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF81B64C),
                foregroundColor: const Color(0xFF161512),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Start',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
