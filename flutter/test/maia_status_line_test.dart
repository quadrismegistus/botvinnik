// The Maia status line: it exists to make a stand-in explain itself, so the
// load-bearing case is that a FAILED band shows its reason, and a healthy one
// stays out of the way.
//
//   cd flutter && flutter test test/maia_status_line_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/maia_progress.dart';
import 'package:botvinnik_mobile/stores/maia_status.dart';
import 'package:botvinnik_mobile/ui/maia_status_line.dart';

Future<void> _pump(WidgetTester tester, MaiaBandState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaiaStatusLine(state: state, name: 'Botvinnik'),
        ),
      ),
    );

void main() {
  testWidgets('a failed band states the reason, not a silent stand-in',
      (tester) async {
    await _pump(tester, MaiaBandState.failed('fetch failed: 403'));

    // The verbatim worker reason — the whole point on a phone with no console.
    expect(find.textContaining('403'), findsOneWidget);
    // And it is honest that the game continues, as Stockfish.
    expect(find.textContaining('Stockfish'), findsOneWidget);
  });

  testWidgets('a downloading band shows a bar and the bytes', (tester) async {
    await _pump(
      tester,
      MaiaBandState.loading(
          const MaiaProgress('fetching', received: 1900000, total: 3500000)),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // A determinate bar when the server gave a length.
    final bar =
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, isNotNull);
    expect(find.textContaining('Downloading'), findsOneWidget);
  });

  testWidgets('a ready or idle band says nothing at all', (tester) async {
    // A bot that can play needs no annotation; the row must not clutter.
    for (final state in const [MaiaBandState.ready(), MaiaBandState.idle()]) {
      await _pump(tester, state);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    }
  });
}
