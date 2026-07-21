// The Book view: what people actually play here — offline — set against what
// the engine thinks of it. Opening name for the current line, then one ranked
// table: san, the engine's evaluation and how sure it is of it, game count and
// share, and the white/draw/black bar. Tap a move to play it.
//
// The two facts are merged rather than shown in separate panels because the
// interesting rows are the ones where they disagree: a popular move the engine
// dislikes is a trap or a fashion, an engine move nobody plays is a novelty.
// Sorted by popularity (brain/explorer.ts), so engine-only moves fall to the
// bottom — the engine's own ranking is already the Lines panel.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/explorer_api.dart';
import '../brain/types.dart';
import '../stores/book_store.dart';
import '../stores/game_controller.dart';

class BookPane extends StatefulWidget {
  const BookPane({super.key});

  @override
  State<BookPane> createState() => _BookPaneState();
}

class _BookPaneState extends State<BookPane> {
  // Column widths. The eval and confidence columns are new here, and the pane
  // can be narrower than any phone — 170pt at the wide layout's maximum split
  // on a 720pt window — so the block scrolls sideways below _kMinRow rather
  // than overflowing. Same reasoning as lines_pane: ONE scroll for the whole
  // block, or the columns stop lining up and mean nothing.
  static const double _kSan = 56; // Qa1xd4#, the longest legal san
  static const double _kEval = 42;
  static const double _kConf = 34;
  static const double _kGames = 76;
  static const double _kGap = 8;
  static const double _kBarMin = 70;
  static const double _kPad = 14; // each side
  static const double _kMinRow =
      _kSan + _kEval + _kConf + _kGames + _kGap + _kBarMin + 2 * _kPad;

  /// The merged rows, memoised per position and per engine result: the pane
  /// rebuilds on every streamed depth update, and each call is a bridge round
  /// trip that runs chess.js over every engine line.
  List<UnifiedMove> _rows = const [];
  String _rowsKey = '';

  @override
  void initState() {
    super.initState();
    context.read<BookStore>().ensureLoaded();
  }

  List<UnifiedMove> _unified(BuildContext context, String fen,
      List<EngineMove> lines, Map<String, dynamic>? node) {
    final key = [
      fen,
      node == null ? '-' : 'book',
      for (final l in lines) '${l.multipv}:${l.uci}:${l.score}:${l.mate}',
    ].join('|');
    if (key == _rowsKey) return _rows;
    _rowsKey = key;
    _rows = context.read<ExplorerApi>().unifyMoves(
          fen: fen,
          lines: lines,
          lichess: node == null ? null : ExplorerApi.position(node),
        );
    return _rows;
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
    final fen = game.position.fen;
    // visibleLines, not currentLines: blind mode hides the engine here for the
    // same reason it hides the Lines panel.
    final rows = _unified(context, fen, game.visibleLines, node);
    final blackToMove = fen.split(' ')[1] == 'b';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
                rows.isEmpty
                    ? 'Out of book — on your own now.'
                    : 'Out of book — engine moves only.',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        if (rows.isNotEmpty) _table(game, rows, blackToMove),
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

  Widget _table(GameController game, List<UnifiedMove> rows, bool blackToMove) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(constraints.maxWidth, _kMinRow);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              for (final r in rows) _moveRow(game, r, blackToMove),
            ],
          ),
        ),
      );
    });
  }

  static const TextStyle _headStyle =
      TextStyle(color: Colors.white24, fontSize: 10);

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(_kPad, 6, _kPad, 2),
        child: Row(children: const [
          SizedBox(width: _kSan, child: Text('move', style: _headStyle)),
          SizedBox(width: _kEval, child: Text('eval', style: _headStyle)),
          SizedBox(width: _kConf, child: Text('sure', style: _headStyle)),
          SizedBox(width: _kGames, child: Text('played', style: _headStyle)),
          SizedBox(width: _kGap),
          Expanded(child: Text('white / draw / black', style: _headStyle)),
        ]),
      );

  Widget _moveRow(GameController game, UnifiedMove r, bool blackToMove) {
    final book = r.lichess ?? r.masters;
    return InkWell(
      onTap: () => game.playUci(r.uci),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPad, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: _kSan,
              child: Text(r.san,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            SizedBox(width: _kEval, child: _evalChip(r, blackToMove)),
            SizedBox(
              width: _kConf,
              child: Text(
                  r.confidence == null ? '' : '${r.confidence!.round()}%',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
            ),
            SizedBox(
              width: _kGames,
              child: Text(
                  book == null
                      ? '—'
                      : '${_fmt(book.games)} · ${book.pct.toStringAsFixed(0)}%',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11.5)),
            ),
            const SizedBox(width: _kGap),
            Expanded(
                child: book == null
                    ? const SizedBox(height: 16)
                    : _wdlBar(book.white, book.draws, book.black)),
          ],
        ),
      ),
    );
  }

  /// White-POV, like the Lines panel's chips — the engine reports mover-POV,
  /// but the two panels sit stacked in the wide layout and the same move
  /// carrying opposite signs in each is worse than either convention.
  Widget _evalChip(UnifiedMove r, bool blackToMove) {
    if (!r.hasEngine) {
      return const Text('—',
          style: TextStyle(color: Colors.white24, fontSize: 12));
    }
    final String text;
    if (r.mate != null) {
      final m = blackToMove ? -r.mate! : r.mate!;
      text = '#$m';
    } else {
      final e = blackToMove ? -r.score! : r.score!;
      text = (e >= 0 ? '+' : '') + e.toStringAsFixed(1);
    }
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF3a3733),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()])),
    );
  }

  /// The move's own games, as shares — the brain hands these over already
  /// converted to percentages, so nothing here divides.
  Widget _wdlBar(double w, double d, double b) {
    Widget seg(double pct, Color bg, Color fg) => Expanded(
          flex: (pct * 10).round().clamp(1, 1000),
          child: Container(
            height: 16,
            color: bg,
            alignment: Alignment.center,
            child: pct >= 12
                ? Text('${pct.round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 9.5, color: fg))
                : null,
          ),
        );

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
