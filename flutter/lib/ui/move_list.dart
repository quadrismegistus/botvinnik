// Simple SAN move table with grade coloring — the Moves tab.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import 'grade_strip.dart';

class MoveListPane extends StatelessWidget {
  const MoveListPane({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    final table = context.read<ClassTable>();
    final rows = <TableRow>[];
    for (var i = 0; i < game.moves.length; i += 2) {
      final white = game.moves[i];
      final black = i + 1 < game.moves.length ? game.moves[i + 1] : null;
      rows.add(TableRow(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${i ~/ 2 + 1}.',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ),
        _cell(white, table),
        black == null ? const SizedBox() : _cell(black, table),
      ]));
    }
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('No moves yet.',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(34),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
        },
        children: rows,
      ),
    );
  }

  Widget _cell(MoveRecord m, ClassTable table) {
    final label = m.grade?.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(m.san, style: const TextStyle(fontSize: 13)),
        if (label != null) ...[
          const SizedBox(width: 4),
          Text(table.glyph(label),
              style: TextStyle(color: table.color(label), fontSize: 11)),
        ],
      ]),
    );
  }
}
