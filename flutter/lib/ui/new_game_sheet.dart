// The new-game sheet. Assign each side to the human or any bot, then start —
// this is where opponent selection lives, because who plays which side is a
// game-start choice, not a persistent global setting.
//
//   You (W) vs bot (B)  → you play White
//   bot (W) vs bot (B)  → bot-vs-bot, you watch (and they can be different bots)
//   You (W) vs You (B)  → analysis, you move both sides

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
    isScrollControlled: true,
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
  // null = the human plays this side; otherwise a bot persona id.
  late String? _white = widget.settings.whitePersonaId;
  late String? _black = widget.settings.blackPersonaId;

  String _nameOf(String? id) {
    if (id == null) return 'You';
    for (final p in widget.game.rosterPersonas) {
      if (p.id == id) return p.name;
    }
    return 'Bot';
  }

  String get _summary {
    final w = _white == null, b = _black == null;
    if (w && b) return 'Analysis — you move both sides, every move still graded.';
    if (w) return 'You play White; ${_nameOf(_black)} plays Black.';
    if (b) return 'You play Black; ${_nameOf(_white)} plays White.';
    return '${_nameOf(_white)} (White) vs ${_nameOf(_black)} (Black) — you watch.';
  }

  Future<void> _pickBotFor(bool white) async {
    final current = white ? _white : _black;
    final id =
        await pickBot(context, current: current ?? widget.settings.personaId);
    if (id == null || !mounted) return; // dismissed
    setState(() => white ? _white = id : _black = id);
  }

  Widget _chip(String text, bool selected, VoidCallback onTap,
        ) =>
      ChoiceChip(
        label: Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                color: selected ? const Color(0xFF81B64C) : Colors.white54)),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: const Color(0xFF1f1e1b),
        selectedColor: const Color(0xFF3a3733),
        showCheckmark: false,
      );

  Widget _sideRow(String label, bool white) {
    final id = white ? _white : _black;
    final isYou = id == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 52,
              child: Text(label,
                  style: const TextStyle(fontSize: 14, color: Colors.white70))),
          const SizedBox(width: 6),
          _chip('You', isYou,
              () => setState(() => white ? _white = null : _black = null)),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _chip(
                isYou ? 'Pick a bot…' : _nameOf(id),
                !isYou,
                () => _pickBotFor(white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            _sideRow('White', true),
            _sideRow('Black', false),
            const SizedBox(height: 8),
            Text(_summary,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                widget.settings.setPlayers(white: _white, black: _black);
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
