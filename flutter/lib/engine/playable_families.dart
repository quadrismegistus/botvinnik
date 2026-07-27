// Which bot families this runtime can actually PLAY — one answer, in one
// place, for every surface that offers an opponent.
//
// This existed twice and neither copy was load-bearing, which was the bug.
// `roster_picker._playableFamilies` filtered its own sheet, `bot_picker` did
// not filter at all, and both were safe only because the brain roster was
// requested with `availablePersonas(false)` — the WEB roster, which drops
// every `nativeOnly` family. That hid Dala for the right reason by accident,
// and ChessGPT for the wrong one: it is native-only, so it never reached any
// picker on any platform, including the ones that run it.
//
// The distinction the brain cannot make, and Dart can: `nativeOnly` says
// "needs the native shell", not "we implemented it". Dala is nativeOnly AND
// unimplemented — it wants an lc0 sidecar nobody built (#45) — so it stays out
// here on its own terms rather than by riding a flag meant for something else.
// Offering it would put three personas in the New Game sheet that silently
// play as a Stockfish stand-in (#117), which is the exact failure this file
// exists to prevent.

import 'package:flutter/foundation.dart';

import 'chessgpt_engine.dart';
import 'custom_engine_runner.dart';
import 'garbo_engine.dart';
import 'maia_engine.dart';
import 'retro_engine.dart';

/// A family's name as a player should read it.
///
/// Capitalising the id is right for most of them — squarefish, stockfish,
/// maia, retro, rodent, horizon all come out correctly — and wrong for the
/// ones whose names carry internal capitals. It lived in bot_picker only, so
/// the New Game row said "ChessGPT" while the roster sheet heading beside it
/// said "Chessgpt".
const _familyNames = <String, String>{
  'chessgpt': 'ChessGPT',
  'brainlearn': 'BrainLearn',
};

String familyLabel(String family) =>
    _familyNames[family] ??
    (family.isEmpty ? family : family[0].toUpperCase() + family.substring(1));

/// Overrides [playableFamilies] for a widget test.
///
/// Necessary, not a convenience. Several `supported` getters check for real
/// artefacts rather than the platform — `RetroEngine.supported` on macOS wants
/// the staged binaries, which exist in a built .app and not in a `flutter
/// test` run — so without this a test asserting "Retro is a family" depends on
/// whether someone has built the app recently, and on which host. That class
/// of gate has silently made this suite macOS-only twice.
@visibleForTesting
Set<String>? debugPlayableFamilies;

/// Families with a working implementation on this platform.
///
/// Deliberately a whitelist. A new family that forgets to add itself is
/// invisible, which is recoverable; a family that appears without an engine
/// behind it plays as something else under its own name, which is not.
Set<String> get playableFamilies =>
    debugPlayableFamilies ?? _realPlayableFamilies;

/// Every family this app knows how to play, and the capability each needs.
///
/// A literal, deliberately: `brain/familyParity.test.ts` reads this block for
/// the family strings and checks them against the brain's PERSONAS and against
/// roster_picker's glyph switch. Nothing in either language's type system
/// spans that gap.
const _familyNeeds = <String, String>{
  'squarefish': 'always',
  'stockfish': 'always',
  'horizon': 'always',
  'retro': 'retro',
  'garbo': 'garbo',
  // Maia and ChessGPT are both onnxruntime over FFI, on the same platforms.
  'maia': 'ort',
  'chessgpt': 'ort',
  'custom': 'process',
  // Styled engines (Rodent, BrainLearn) are `custom`-store families too,
  // offered wherever a process engine can run.
  'rodent': 'process',
  'brainlearn': 'process',
};

/// The whitelist as a PURE FUNCTION of what this runtime can do.
///
/// Split out so it is testable on the machine that actually runs the tests.
/// CI is ubuntu-latest, where every `supported` getter is false — so a test
/// phrased against those getters cannot tell a correct whitelist from one with
/// a family deleted, because both answer the same on Linux. That is not a
/// hypothetical: the first version of this file's test suite passed on CI with
/// the bug it was written to catch. Passing the capabilities in lets a Linux
/// test assert "given ORT, ChessGPT is offered", which is the claim that
/// matters.
@visibleForTesting
Set<String> familiesFor({
  required bool ort,
  required bool retro,
  required bool garbo,
  required bool process,
}) {
  final have = {
    'always': true,
    'ort': ort,
    'retro': retro,
    'garbo': garbo,
    'process': process,
  };
  return {
    for (final e in _familyNeeds.entries)
      if (have[e.value] ?? false) e.key,
  };
}

final Set<String> _realPlayableFamilies = familiesFor(
  ort: MaiaEngine.supported && ChessGptEngine.supported,
  retro: RetroEngine.supported,
  garbo: GarboEngine.supported,
  process: CustomEngineRunner.supported,
);

/// Whether to ask the brain for the NATIVE roster.
///
/// DERIVED from [playableFamilies], not re-read from the platform. Two
/// reasons, and the second is why it changed:
///
///   * It states the actual condition — ask for the native-only personas when
///     a native-only family is playable — so it cannot drift from the filter
///     that runs immediately afterwards.
///   * It follows debugPlayableFamilies, which makes it testable anywhere. As
///     `=> ChessGptEngine.supported` it was false on CI's Linux, where the
///     hardcoded-false bug it exists to prevent is indistinguishable from
///     correct behaviour — and a test asserting it against that same getter
///     was a tautology that `Platform.isMacOS` and `=> true` both satisfied.
bool get wantsNativeRoster => playableFamilies.contains('chessgpt');
