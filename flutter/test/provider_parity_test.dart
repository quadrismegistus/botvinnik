// Every brain API a widget reads from the tree must be PROVIDED in main.dart.
//
// This has now shipped twice. Both times the widget test supplied its own
// Provider, so the suite was green while the real app threw
// ProviderNotFoundException the moment the pane was opened:
//
//   - GradingApi, read by Review's summary (#140) — deleting the provider left
//     144 tests green and crashed Review on open.
//   - ExplorerApi, read by the Book pane (#141) — deleting the provider left
//     198 tests green and crashed the Book pane on open.
//
// Nothing spans that gap: main.dart's provider list is built inside a widget
// no test constructs, and every pane test injects its own fakes by design. So
// the check is over the SOURCE, the same shape as brain/familyParity.test.ts.
//
// A unit test cannot catch this class. This can.
//
//   cd flutter && flutter test test/provider_parity_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every *Api read from the widget tree is provided in main.dart', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run from flutter/ — the paths here are relative');

    // What widgets ask the tree for.
    final read = <String>{};
    final readPattern = RegExp(r'context\.(?:read|watch)<([A-Za-z]+Api)>');
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in readPattern.allMatches(f.readAsStringSync())) {
        read.add(m.group(1)!);
      }
    }

    // What the boot gate puts there. Deliberately loose about the Provider
    // flavour and tight about the type name.
    final main = File('lib/main.dart').readAsStringSync();
    // Line-scoped rather than one regex over the whole file: a provider reads
    // `Provider(create: (_) => ChessApi(bridge))`, and any pattern trying to
    // span that has to cross the `)` of `(_)`.
    final apiCall = RegExp(r'([A-Za-z]+Api)\(');
    final provided = <String>{
      for (final line in main.split('\n'))
        if (line.contains('Provider'))
          for (final m in apiCall.allMatches(line)) m.group(1)!,
    };

    expect(provided, isNotEmpty,
        reason: 'no providers found — the scan has drifted');
    expect(read, isNotEmpty,
        reason: 'the scan found nothing — the pattern has drifted, and a '
            'silently empty scan is the one way this test could go vacuous');

    for (final api in read) {
      expect(provided, contains(api),
          reason: '$api is read from the widget tree but never provided in '
              'main.dart — the app will throw ProviderNotFoundException on '
              'the first screen that reads it');
    }
  });
}
