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
  late String _mode = !widget.settings.botEnabled
      ? 'analysis'
      : widget.settings.botBothSides
          ? 'botvbot'
          : (widget.settings.playerColor == 'w' ? 'white' : 'black');

  static const _captions = {
    'white': 'You play White; the bot plays Black.',
    'black': 'You play Black; the bot plays White.',
    'botvbot': 'The bot plays both sides — sit back and watch.',
    'analysis': 'No opponent — you move both sides, every move still graded.',
  };

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
            // Four modes don't fit a segmented button on a phone, so chips
            // that wrap. Bot vs Bot is the new one (#58).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [
                  ('white', 'Play White'),
                  ('black', 'Play Black'),
                  ('botvbot', 'Bot vs Bot'),
                  ('analysis', 'Analysis'),
                ])
                  ChoiceChip(
                    label: Text(m.$2),
                    selected: _mode == m.$1,
                    onSelected: (_) => setState(() => _mode = m.$1),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: _mode == m.$1
                          ? const Color(0xFF81B64C)
                          : Colors.white54,
                    ),
                    backgroundColor: const Color(0xFF1f1e1b),
                    selectedColor: const Color(0xFF3a3733),
                    showCheckmark: false,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _captions[_mode]!,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                s.botBothSides = _mode == 'botvbot';
                if (_mode == 'white' || _mode == 'black') {
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
