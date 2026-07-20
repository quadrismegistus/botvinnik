// Where the shipped engines live inside the macOS .app.
//
// This is the layout half of notarization (#67): executable code in
// `Contents/Resources` is rejected, because the hardened runtime treats
// Resources as data and a binary there is unsigned nested code by definition.
// Engines therefore live in `Contents/MacOS` and are signed in the same build
// phase that copies them.
//
// It is worth a test rather than a comment because both failure modes are
// silent. A binary left in Resources builds and runs perfectly well and is
// only rejected at submission, months later. A resolver still pointing at the
// old path falls through to a system-installed engine — which works on the
// developer's machine and finds nothing inside the sandbox, where the whole
// roster then plays as somebody else.
//
//   cd flutter && flutter test integration_test/bundle_layout_test.dart -d macos

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/engine/process_engine.dart';
import 'package:botvinnik_mobile/engine/retro_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Contents/MacOS/<app> → Contents/MacOS
  final macOS = File(Platform.resolvedExecutable).parent;
  final resources = Directory('${macOS.parent.path}/Resources');

  test('the engine the app resolves is the bundled one', () {
    final resolved = ProcessEngine.resolveBinary();
    expect(resolved, isNotNull, reason: 'no engine found at all');
    // Not just "an engine exists": a resolver pointing at the old location
    // would find Homebrew's instead, pass every local test, and fail inside
    // the sandbox where nothing outside the bundle can be spawned.
    expect(resolved, startsWith(macOS.path),
        reason: 'resolved $resolved, which is outside the app bundle');
  }, skip: !Platform.isMacOS);

  test('retro is offered, and from Contents/MacOS', () {
    expect(RetroEngine.supported, isTrue);
    for (final engine in ['turochamp', 'bernstein', 'sargon']) {
      expect(File('${macOS.path}/retro/$engine').existsSync(), isTrue,
          reason: '$engine is not in Contents/MacOS/retro');
    }
  }, skip: !Platform.isMacOS);

  test('Contents/Resources holds no executables', () {
    // The build phase clears the old destinations, so a stale build cannot
    // leave a copy behind that would still be found — and still be rejected.
    expect(Directory('${resources.path}/retro').existsSync(), isFalse);
    expect(File('${resources.path}/stockfish').existsSync(), isFalse);
  }, skip: !Platform.isMacOS);
}
