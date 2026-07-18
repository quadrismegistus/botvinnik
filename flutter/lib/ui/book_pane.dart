// The Book view: what people actually play here — offline. Opening name for
// the current line, then the move table: san, game count and share, and the
// white/draw/black bar. Tap a move to play it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/book_store.dart';
import '../stores/game_controller.dart';

class BookPane extends StatefulWidget {
  const BookPane({super.key});

  @override
  State<BookPane> createState() => _BookPaneState();
}

class _BookPaneState extends State<BookPane> {
  @override
  void initState() {
    super.initState();
    context.read<BookStore>().ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final book = context.watch<BookStore>();

    if (game.blind && game.botEnabled && !game.gameOver) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Blind mode — the book reopens when the game ends.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    if (!book.loaded) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Opening the book…',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    final fens = [
      if (game.moves.isEmpty)
        game.position.fen
      else ...[
        game.moves.first.fenBefore,
        ...game.moves.map((m) => m.fenAfter)
      ],
    ];
    final opening = book.openingFor(fens);
    final node = book.node(game.position.fen);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opening != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text('${opening[0]} ${opening[1]}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        if (node == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text('Out of book — on your own now.',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else
          ..._moveRows(context, game, node),
        if (node != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              '${_fmt(_total(node))} games · ${book.source.split(",").first}',
              style: const TextStyle(color: Colors.white24, fontSize: 10.5),
            ),
          ),
      ],
    );
  }

  int _total(Map<String, dynamic> node) =>
      (node['white'] as num).toInt() +
      (node['draws'] as num).toInt() +
      (node['black'] as num).toInt();

  String _fmt(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1)}M'
      : n >= 1000
          ? '${(n / 1000).toStringAsFixed(0)}k'
          : '$n';

  List<Widget> _moveRows(
      BuildContext context, GameController game, Map<String, dynamic> node) {
    final total = _total(node);
    final moves = (node['moves'] as List).cast<Map<String, dynamic>>();
    return [
      for (final m in moves)
        _moveRow(context, game, m, total),
    ];
  }

  Widget _moveRow(BuildContext context, GameController game,
      Map<String, dynamic> m, int totalGames) {
    final w = (m['white'] as num).toInt();
    final d = (m['draws'] as num).toInt();
    final b = (m['black'] as num).toInt();
    final games = w + d + b;
    final share = totalGames > 0 ? games / totalGames * 100 : 0;

    return InkWell(
      onTap: () => game.playUci(m['uci'] as String),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(m['san'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            SizedBox(
              width: 76,
              child: Text('${_fmt(games)} · ${share.toStringAsFixed(0)}%',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11.5)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _wdlBar(w, d, b)),
          ],
        ),
      ),
    );
  }

  Widget _wdlBar(int w, int d, int b) {
    final total = (w + d + b).clamp(1, 1 << 31);
    Widget seg(int n, Color bg, Color fg) {
      final pct = n / total * 100;
      return Expanded(
        flex: (n * 1000 ~/ total).clamp(1, 1000),
        child: Container(
          height: 16,
          color: bg,
          alignment: Alignment.center,
          child: pct >= 12
              ? Text('${pct.round()}%',
                  style: TextStyle(fontSize: 9.5, color: fg))
              : null,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Row(children: [
        seg(w, const Color(0xFFE8E6E1), const Color(0xFF1b1a17)),
        seg(d, const Color(0xFF6B6862), Colors.white70),
        seg(b, const Color(0xFF33312E), Colors.white70),
      ]),
    );
  }
}
