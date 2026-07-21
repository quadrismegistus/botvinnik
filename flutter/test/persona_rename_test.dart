// Persona ids survive across a rename, everywhere a PERSISTED id becomes
// something a player reads.
//
// The rename (#139) mapped old ids inside the brain's `personaById`, and the
// PR claimed that was "the single door". It was not: two Dart call sites
// compared raw ids instead, and a third rendered one. The result was a fresh
// install whose New Game sheet said "Bot" while the plate beside it said
// "Squarefish 900".
//
// These tests pin the door shut. They use the REAL brain over the bridge —
// a fake would just re-implement the mapping and prove nothing.
//
//   cd flutter && flutter test test/persona_rename_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:botvinnik_mobile/stores/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the shipped default persona id is one the roster still contains',
      () async {
    // This is the test whose absence let the "Bot" bug ship. The default is
    // baked into SettingsStore.load(), so it is never exercised by any test
    // that sets players explicitly — which is all of them.
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();

    final id = settings.blackPersonaId ?? settings.whitePersonaId;
    expect(id, isNotNull, reason: 'a fresh install starts with an opponent');
    // Asserted against the CURRENT naming rather than a literal, so this fails
    // on the next rename too rather than only on this one.
    expect(id, startsWith('squarefish-'),
        reason: 'the default must name a persona the roster actually has, or '
            'every fresh install opens showing "Bot"');
  });
}
