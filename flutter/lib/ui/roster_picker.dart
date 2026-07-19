// Opponent picker: a modal sheet listing the roster, grouped by family and
// sorted by elo. Selecting sets settings.personaId — GameController hears the
// change and starts a new game.
//
// The filter below is the honest edge of the port: a family appears here only
// once _pickBotMove can actually play it. Everything else in the roster would
// silently fall back to Stockfish, which is a different opponent wearing the
// persona's name.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../stores/game_controller.dart';
import '../stores/settings_store.dart';

const _playableFamilies = {'square', 'fish', 'horizon'};

void showRosterPicker(BuildContext context) {
  final game = context.read<GameController>();
  final settings = context.read<SettingsStore>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => _RosterSheet(game: game, settings: settings),
  );
}

class _RosterSheet extends StatelessWidget {
  final GameController game;
  final SettingsStore settings;
  const _RosterSheet({required this.game, required this.settings});

  @override
  Widget build(BuildContext context) {
    final personas = game.rosterPersonas
        .where((p) => _playableFamilies.contains(p.family))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => ListView.builder(
        controller: scroll,
        itemCount: personas.length,
        itemBuilder: (context, i) {
          final p = personas[i];
          final selected = p.id == settings.personaId;
          return ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: const Color(0xFF3a3733),
            leading: _familyMark(p),
            title: Text('${p.name}  ·  ${p.elo}',
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(p.blurb,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
            onTap: () {
              settings.personaId = p.id;
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  Widget _familyMark(Persona p) {
    final (glyph, color) = switch (p.family) {
      'square' => ('▦', const Color(0xFFd0b755)),
      'fish' => ('◆', const Color(0xFF5b8bb0)),
      // a sun resting on the horizon line — the same idea as the web avatar:
      // this engine cannot see past its own exchanges
      'horizon' => ('◓', const Color(0xFFc4783f)),
      _ => ('·', Colors.white38),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFF1b1a17),
      child: Text(glyph, style: TextStyle(color: color, fontSize: 15)),
    );
  }
}
