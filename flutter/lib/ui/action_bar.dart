// The fixed bottom action bar — thumb zone. M1: opponent (opens roster),
// undo, New game. Practice/review swap their own actions in here later.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import 'games_list.dart';
import 'roster_picker.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 6,
        bottom: 6 + MediaQuery.of(context).padding.bottom,
      ),
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => showRosterPicker(context),
            icon: const Icon(Icons.smart_toy_outlined, size: 18),
            label: Text(
              game.persona?.name ?? 'Opponent',
              style: const TextStyle(fontSize: 13),
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GamesListScreen()),
            ),
            icon: const Icon(Icons.history),
            tooltip: 'Games',
            color: Colors.white70,
          ),
          IconButton(
            onPressed:
                game.moves.isEmpty || game.botThinking ? null : game.undo,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            color: Colors.white70,
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: game.newGame,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF81B64C),
              foregroundColor: const Color(0xFF161512),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('New game',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
