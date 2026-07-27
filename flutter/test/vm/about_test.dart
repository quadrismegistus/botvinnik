// The About section and, more importantly, the compliance property under it:
// the GPL licence and third-party notices are BUNDLED and readable with no
// network. That offline availability is the point — the source link alone does
// not satisfy "the licence travels with the binary".
//
//   cd flutter && flutter test test/about_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:botvinnik_mobile/ui/about_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'botvinnik',
      packageName: 'app.botvinnik',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('the licence travels with the binary', () {
    test('LICENSE is the GPL-3.0 text', () async {
      final text = await rootBundle.loadString('assets/legal/LICENSE');
      expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(text, contains('Version 3'));
    });

    test('the notices credit every engine, including the ones added recently',
        () async {
      final text =
          await rootBundle.loadString('assets/legal/THIRD-PARTY-NOTICES.md');
      // the components that SET the licence, and the ones this session added —
      // if the CI drift guard ever lapses, a missing entry surfaces here too
      for (final name in ['Stockfish', 'morlock', 'Garbochess', 'Maia']) {
        expect(text, contains(name), reason: '$name missing from notices');
      }
    });
  });

  testWidgets('the About rows are present and License opens the bundled text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AboutSection())),
    );
    // bounded pumps, NOT pumpAndSettle: the licence screen shows a
    // CircularProgressIndicator while its asset loads, and that animates
    // forever, so pumpAndSettle would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Source code'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);
    expect(find.text('Third-party notices'), findsOneWidget);

    await tester.tap(find.text('License'));
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 400)); // finish transition

    // the row navigated to the licence screen pointed at the bundled asset.
    // That the asset itself loads with the GPL text is the two rootBundle
    // tests above — asserting the rendered text here would need runAsync to
    // drive the real file read past the widget test's fake clock.
    final screen = tester.widget<LegalTextScreen>(find.byType(LegalTextScreen));
    expect(screen.asset, 'assets/legal/LICENSE');
  });
}
