// The Review tab: stored games, newest first — result, opponent, accuracy,
// blunder/mistake counts. Tap to review (pushed route).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/review_controller.dart';
import 'review_screen.dart';

class GamesListBody extends StatefulWidget {
  const GamesListBody({super.key});

  @override
  State<GamesListBody> createState() => _GamesListBodyState();
}

class _GamesListBodyState extends State<GamesListBody> {
  // no initState load: the tab is built lazily on first visit and the shell's
  // tab handler already calls loadGames() on every visit, including that one

  @override
  Widget build(BuildContext context) {
    final review = context.watch<ReviewController>();
    if (!review.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (review.games.isEmpty) {
      return const Center(
        child: Text('No games yet — finish one and it lands here.',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.separated(
      itemCount: review.games.length,
      separatorBuilder: (_, i) =>
          const Divider(height: 1, color: Color(0xFF2c2a26)),
      itemBuilder: (context, i) => _row(context, review, review.games[i]),
    );
  }

  Widget _row(BuildContext context, ReviewController review,
      Map<String, dynamic> g) {
    final result = g['result'] as String? ?? '*';
    final botColor = g['botColor'] as String?;
    final youAreWhite = botColor == 'b';
    final won = result == (youAreWhite ? '1-0' : '0-1');
    final lost = result == (youAreWhite ? '0-1' : '1-0');
    final verdict = won ? 'Won' : (lost ? 'Lost' : 'Draw');
    final color = won
        ? const Color(0xFF81B64C)
        : (lost ? const Color(0xFFCA3431) : Colors.white54);

    final personaId = g['botPersona'] as String? ?? 'bot';
    final endedAt = g['endedAt'] as String? ?? '';
    final when = endedAt.length >= 16
        ? endedAt.substring(0, 16).replaceFirst('T', ' ')
        : endedAt;
    final youAcc = (youAreWhite ? g['whiteAccuracy'] : g['blackAccuracy']);
    final counts = ((g['labelCounts'] as Map?)?[youAreWhite ? 'w' : 'b']
            as Map?)
        ?.cast<String, dynamic>();
    final blunders = (counts?['blunder'] as num?)?.toInt() ?? 0;
    final mistakes = (counts?['mistake'] as num?)?.toInt() ?? 0;

    return ListTile(
      dense: true,
      title: Row(children: [
        Text(verdict,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('vs $personaId', style: const TextStyle(fontSize: 13)),
        const Spacer(),
        if (youAcc != null)
          Text('${(youAcc as num).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
      subtitle: Text(
        '$when · ${g['moveCount']} moves'
        '${blunders > 0 ? ' · $blunders ??' : ''}'
        '${mistakes > 0 ? ' · $mistakes ?' : ''}',
        style: const TextStyle(fontSize: 11.5, color: Colors.white38),
      ),
      onTap: () {
        review.open(g);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReviewScreen()),
        );
      },
      onLongPress: () => showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Delete game?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                review.deleteGame(g['id'] as String);
                Navigator.pop(dctx);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
