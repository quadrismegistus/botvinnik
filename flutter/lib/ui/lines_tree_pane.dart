// The Tree view: the game's exploration map. Played path through the middle
// (white), the engine's live alternatives branching from the current
// position (colored red→green by quality), and the ghosts of alternatives
// past (dim). Tap a live first move to watch it play out on the board.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import '../stores/lines_tree_model.dart';

const double _kHeight = 300;

class LinesTreePane extends StatefulWidget {
  const LinesTreePane({super.key});

  @override
  State<LinesTreePane> createState() => _LinesTreePaneState();
}

class _LinesTreePaneState extends State<LinesTreePane> {
  final ScrollController _scroll = ScrollController();
  String _lastAnchor = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final tree = game.linesTree;
    if (tree == null || tree.nodes.length <= 1) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('The tree grows as the game is explored.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    // follow the frontier — but only when the POSITION advances, not on
    // every streamed depth tick (that read as a distracting shimmy)
    if (tree.anchorId != _lastAnchor) {
      _lastAnchor = tree.anchorId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final anchor = tree.nodes[tree.anchorId];
        if (anchor == null) return;
        final target =
            (anchor.x - 100).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      });
    }

    final playable = tree.playableUci();
    // Blind only bites in a real game: on the analysis board both sides are the
    // player and there is no opponent to hide the engine from.
    final blind = game.blind && game.botEnabled;
    return SizedBox(
      height: _kHeight,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: GestureDetector(
          onTapUp: (d) {
            // hit-test nodes; a live first move out of the current position
            // gets PLAYED (the web's click-to-play), not previewed
            for (final n in tree.nodes.values) {
              if ((d.localPosition.dx - n.x).abs() <= kNodeW / 2 + 4 &&
                  (d.localPosition.dy - n.y).abs() <= kNodeH / 2 + 4) {
                final uci = playable[n.id];
                if (uci != null) game.playUci(uci);
                return;
              }
            }
          },
          child: CustomPaint(
            // reserve lookahead past the anchor: right after a move the old
            // continuations are pruned and the new ones haven't streamed, so
            // a nodes-only width briefly shrinks and the scroll clamp yanks
            // the anchor to the right edge
            size: Size(
                [
                  tree.widthFor(blind: blind),
                  (tree.nodes[tree.anchorId]?.x ?? 0) + 340,
                  MediaQuery.of(context).size.width,
                ].reduce(max),
                _kHeight),
            painter: _TreePainter(tree,
                blind ? const {} : playable.keys.toSet(),
                blind: blind),
          ),
        ),
      ),
    );
  }
}

class _TreePainter extends CustomPainter {
  final LinesTreeModel tree;
  final Set<String> playable;
  final bool blind; // the past stays, the present won't hint
  final int version;

  /// Resolved once here rather than per node, and asked of the model rather
  /// than decided in the painter — the three things blind has to withhold used
  /// to be three independent checks, and one of them was missing.
  final Set<String> _visibleNodes;
  final String? _bestNodeId;

  _TreePainter(this.tree, this.playable, {this.blind = false})
      : version = tree.version,
        _visibleNodes = tree.visibleNodeIds(blind: blind),
        _bestNodeId = tree.visibleBestNodeId(blind: blind);

  Color _qualityColor(double pctBest) {
    final v = pctBest.clamp(0.0, 100.0);
    return HSVColor.fromAHSV(1, 1.2 * v, 0.65, 0.55).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // links first
    for (final entry in tree.links.entries) {
      final l = entry.value;
      final from = tree.nodes[l.source];
      final to = tree.nodes[l.target];
      if (from == null || to == null) continue;
      final onPath = tree.pathKeys.contains(entry.key);
      final live = tree.liveKeys.contains(entry.key);
      if (blind && tree.isLiveHint(entry.key)) {
        continue; // no engine opinion about the position in front of the player
      }

      final p0 = Offset(from.x + kNodeW / 2, from.y);
      final p1 = Offset(to.x - kNodeW / 2, to.y);
      final mid = (p0.dx + p1.dx) / 2;
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(mid, p0.dy, mid, p1.dy, p1.dx, p1.dy);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = onPath ? 2.4 : (live ? 1.8 : 1.0)
        ..color = onPath
            ? Colors.white38
            : live
                ? _qualityColor(l.pctBest)
                : Colors.white.withValues(alpha: 0.10);
      canvas.drawPath(path, paint);

      // cp label on live off-path links out of the anchor
      if (live && !onPath && l.source == tree.anchorId) {
        final text =
            (l.cp >= 0 ? '+' : '') + l.cp.toStringAsFixed(1);
        final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(
                  color: _qualityColor(l.pctBest), fontSize: 9)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid - tp.width / 2, min(p0.dy, p1.dy) - 2));
      }
    }

    // nodes on top
    for (final n in tree.nodes.values) {
      // a node IS its move name, so withholding the link is not enough
      if (!_visibleNodes.contains(n.id)) continue;
      if (n.id == kRoot) {
        canvas.drawCircle(Offset(n.x, n.y), 3,
            Paint()..color = Colors.white38);
        continue;
      }
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(n.x, n.y), width: kNodeW, height: kNodeH),
        const Radius.circular(5),
      );
      final isBest = n.id == _bestNodeId;
      final isPlayable = playable.contains(n.id);
      final white = n.color == 'w';
      canvas.drawRRect(
          rect,
          Paint()
            ..color = white ? const Color(0xFFE8E6E1) : const Color(0xFF33312E));
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isBest ? 2 : 1
          ..color = isBest
              ? const Color(0xFF81B64C)
              : isPlayable
                  ? Colors.white54
                  : Colors.white12,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: n.san,
          style: TextStyle(
            color: white ? const Color(0xFF1b1a17) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: kNodeW - 6);
      tp.paint(canvas,
          Offset(n.x - tp.width / 2, n.y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      // `blind` as well as `version`: the model only bumps version on ingest,
      // and analysis stops at depth 22 or 3s. Toggling blind after that built a
      // new painter, got `false` here, and left the engine's lines painted on
      // the cached layer until the next move.
      old.version != version || old.blind != blind;
}
