// Bot picker: a modal sheet listing the roster as one flat list sorted by elo,
// so families interleave by strength rather than being grouped. `pickBot`
// RETURNS the chosen id (Navigator result); the New Game sheet decides what to
// do with it. It sets nothing itself.
//
// The filter below is the honest edge of the port: a family appears here only
// once _pickBotMove can actually play it. Everything else in the roster would
// silently fall back to Stockfish, which is a different opponent wearing the
// persona's name. GameController still HAS that fallback, for ids that arrive
// without passing through this sheet — the point of the filter is that nobody
// is ever offered one on purpose.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../engine/garbo_engine.dart';
import '../engine/maia_engine.dart';
import '../engine/retro_engine.dart';
import '../stores/game_controller.dart';

// Three families are platform-conditional rather than simply present, and
// each answers for itself: retro spawns a bundled binary and so plays on the
// web and macOS, Maia runs ORT over FFI and so plays on the web, macOS and
// iOS, Garbo is still a Web Worker and so plays only on the web. Listing one
// where it cannot play would be the exact substitution this filter exists to
// prevent.
final _playableFamilies = {
  'square',
  'fish',
  'horizon',
  if (RetroEngine.supported) 'retro',
  if (GarboEngine.supported) 'garbo',
  if (MaiaEngine.supported) 'maia',
};

/// Pick a bot. Returns the chosen persona id, or null if dismissed — it no
/// longer mutates global state, because "who plays this side" is now a choice
/// the New Game sheet assembles, not a persistent setting the picker commits.
Future<String?> pickBot(BuildContext context, {String? current}) {
  final game = context.read<GameController>();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => _RosterSheet(game: game, current: current),
  );
}

class _RosterSheet extends StatelessWidget {
  final GameController game;
  final String? current;
  const _RosterSheet({required this.game, this.current});

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
          final selected = p.id == current;
          return ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: const Color(0xFF3a3733),
            leading: _familyMark(p),
            title: Text('${p.name}  ·  ${p.elo}',
                style: const TextStyle(fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.white38)),
                // Maia is the one persona family that reaches the network, and
                // the only place the app does at all. Say so before it is
                // chosen rather than during the pause it causes — the weights
                // are GPL-3.0 and deliberately not shipped with the app, so
                // this is a permanent property, not a first-run detail.
                if (p.maiaBand != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    // Not "a 3.5MB model, once": that is the weights alone and
                    // omits the ~3.3MB runtime, which a deploy re-fetches (see
                    // MaiaProgress.reassurance). "A short download" promises
                    // neither a size nor a frequency it cannot keep; "then
                    // plays offline" is the durable truth.
                    child: Text(
                      'a short download the first time — then plays offline',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF9a8f7a)),
                    ),
                  ),
              ],
            ),
            onTap: () => Navigator.pop(context, p.id),
          );
        },
      ),
    );
  }

  /// Material Icons rather than the Unicode glyphs these used to be (▦ ◆ ◓).
  /// Those live in no bundled font, so drawing them made Flutter web fetch
  /// Noto Sans Symbols 2 from fonts.gstatic.com the moment this sheet opened —
  /// a third-party request, and one the offline build could not serve. The
  /// icon font is already bundled and tree-shaken, so these cost ~nothing.
  Widget _familyMark(Persona p) {
    final (icon, color) = switch (p.family) {
      'square' => (Icons.grid_view, const Color(0xFFd0b755)),
      'fish' => (Icons.diamond_outlined, const Color(0xFF5b8bb0)),
      // a sun resting on the horizon — the same idea as the web avatar: this
      // engine cannot see past its own exchanges
      'horizon' => (Icons.wb_twilight, const Color(0xFFc4783f)),
      // a valve, for the machines that had them
      'retro' => (Icons.memory, const Color(0xFF9a7bb0)),
      // hand-written JavaScript, so: braces
      'garbo' => (Icons.data_object, const Color(0xFF6f9e8a)),
      // a net trained on people
      'maia' => (Icons.psychology_outlined, const Color(0xFFb06f8a)),
      _ => (Icons.circle, Colors.white38),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFF1b1a17),
      child: Icon(icon, color: color, size: 17),
    );
  }
}
