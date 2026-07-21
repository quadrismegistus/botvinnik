// A name-and-material strip for one side, shown above and below the board.
//
// Ported from the Svelte MaterialBar (svelte/src/lib/components/), with one
// deliberate change: it renders the captured pieces as IMAGES from the active
// piece set, never the Unicode chess glyphs the web version uses. Those glyphs
// (♛♜♝♞♟) are in no bundled font, so drawing them on Flutter web fetches a Noto
// face from fonts.gstatic.com — a third-party request, and the exact trap the
// grade strip already had to avoid.
//
// The material is read straight off the FEN, so it needs no move history and
// stays correct through undo/redo and review.

import 'package:dartchess/dartchess.dart' show PieceKind, Role, Side;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';

/// The material a side has captured, and its point advantage — read off a FEN.
class PlayerMaterial {
  /// role → how many of the opponent's pieces of that role this side has taken.
  final Map<Role, int> captured;
  /// point advantage over the opponent (0 when behind or level).
  final int advantage;
  const PlayerMaterial(this.captured, this.advantage);
}

class PlayerPlate extends StatelessWidget {
  /// Which side this plate is for.
  final String side; // 'w' | 'b'
  /// True when this plate sits BELOW the board. It then hugs the top of its
  /// box so the name is flush against the board; the plate above the board
  /// (the default) hugs the bottom. Either way the slack in the box falls on
  /// the outer edge instead of showing as a gap between board and name.
  final bool below;
  const PlayerPlate({super.key, required this.side, this.below = false});

  static const _startCount = {
    Role.pawn: 8,
    Role.knight: 2,
    Role.bishop: 2,
    Role.rook: 2,
    Role.queen: 1,
  };
  static const _value = {
    Role.pawn: 1,
    Role.knight: 3,
    Role.bishop: 3,
    Role.rook: 5,
    Role.queen: 9,
  };
  // queen, rook, bishop, knight, pawn — heaviest first, like lichess
  static const _order = [
    Role.queen,
    Role.rook,
    Role.bishop,
    Role.knight,
    Role.pawn,
  ];

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final settings = context.watch<SettingsStore>();
    final persona = side == 'w' ? game.whitePersona : game.blackPersona;
    final name = persona?.name ?? 'You';

    final mat = materialFor(game.displayFen, side);
    final captured = mat.captured;
    final advantage = mat.advantage;
    final opp = side == 'w' ? Side.black : Side.white;
    final assets = pieceSetFor(settings).assets;
    final pieces = <Widget>[
      for (final r in _order)
        if (captured[r] != null)
          for (var i = 0; i < captured[r]!; i++)
            Image(image: assets[_kindOf(opp, r)]!, width: 16, height: 16),
    ];
    return Container(
      alignment: below ? Alignment.topLeft : Alignment.bottomLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Icon(persona == null ? Icons.person_outline : Icons.smart_toy_outlined,
              size: 15, color: Colors.white54),
          const SizedBox(width: 6),
          // Flexible + ellipsis: the Row also carries the elo, the optional
          // stand-in chip, the captured tray and the +N advantage. Left rigid,
          // a long persona name ("Maia III (sampled)") plus the chip overflowed
          // at phone widths and the clipping landed on the tray and the
          // advantage — the two things a player actually reads mid-game.
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
          ),
          if (persona != null) ...[
            const SizedBox(width: 5),
            Text('${persona.elo}',
                style: const TextStyle(fontSize: 11, color: Colors.white30)),
            // The name and elo to the left are a claim about who is playing,
            // and when the persona's engine could not answer they are false —
            // Stockfish moved instead. This is the correction, and it belongs
            // here rather than in a toast because the claim it corrects is
            // still on screen. Sticky for the game, like the flag.
            //
            // Icon, not the ⚠ glyph: this file already learned that lesson for
            // the captured pieces. U+26A0 is in no bundled face, so a Text
            // would fetch Noto from fonts.gstatic.com on web. Material icons
            // ship with the app.
            if (game.stoodInFor(persona.id)) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: "${persona.name}'s engine could not answer, so "
                    'Stockfish moved some of its moves instead.',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x33E8A33D),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 11, color: Color(0xFFE8A33D)),
                    SizedBox(width: 3),
                    Text('stand-in',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFFE8A33D))),
                  ]),
                ),
              ),
            ],
          ],
          if (pieces.isNotEmpty) ...[
            const SizedBox(width: 8),
            // A light tray behind the captured pieces. Without it the dark
            // (black) pieces vanish against the app's dark background — they
            // are drawn as images, so a mid-light backing is what gives both
            // colours their contrast, black by fill and white by outline.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF9c988c),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: pieces),
              ),
            ),
          ],
          const Spacer(),
          if (advantage > 0)
            Text('+$advantage',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF81B64C),
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Captured material and point advantage for [side] ('w'/'b'), off the FEN.
  static PlayerMaterial materialFor(String fen, String side) {
    final live = _countLive(fen);
    final me = side == 'w' ? Side.white : Side.black;
    final opp = side == 'w' ? Side.black : Side.white;
    final captured = <Role, int>{};
    var advantage = 0;
    for (final r in _order) {
      final taken = _startCount[r]! - (live[opp]![r] ?? 0);
      if (taken > 0) captured[r] = taken;
      advantage += ((live[me]![r] ?? 0) - (live[opp]![r] ?? 0)) * _value[r]!;
    }
    return PlayerMaterial(captured, advantage < 0 ? 0 : advantage);
  }

  static Map<Side, Map<Role, int>> _countLive(String fen) {
    final live = {
      Side.white: <Role, int>{},
      Side.black: <Role, int>{},
    };
    final board = fen.split(' ').first;
    for (final ch in board.split('')) {
      final role = _roleOf(ch.toLowerCase());
      if (role == null) continue;
      final s = ch == ch.toLowerCase() ? Side.black : Side.white;
      live[s]![role] = (live[s]![role] ?? 0) + 1;
    }
    return live;
  }

  static Role? _roleOf(String c) => switch (c) {
        'p' => Role.pawn,
        'n' => Role.knight,
        'b' => Role.bishop,
        'r' => Role.rook,
        'q' => Role.queen,
        _ => null, // 'k' and digits/slashes
      };

  static PieceKind _kindOf(Side side, Role role) => PieceKind.values
      .firstWhere((k) => k.side == side && k.role == role);
}
