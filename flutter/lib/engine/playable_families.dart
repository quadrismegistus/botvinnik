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
Set<String> get playableFamilies => debugPlayableFamilies ?? _realPlayableFamilies;

final Set<String> _realPlayableFamilies = {
  'squarefish',
  'stockfish',
  'horizon',
  if (RetroEngine.supported) 'retro',
  if (GarboEngine.supported) 'garbo',
  if (MaiaEngine.supported) 'maia',
  if (ChessGptEngine.supported) 'chessgpt',
  if (CustomEngineRunner.supported) 'custom',
  // Styled engines (Rodent, BrainLearn) are `custom`-store families too,
  // offered wherever a process engine can run.
  if (CustomEngineRunner.supported) 'rodent',
  if (CustomEngineRunner.supported) 'brainlearn',
};

/// Whether to ask the brain for the NATIVE roster.
///
/// Only true where a native-only family is actually playable, so the flag
/// means what it says. It is not simply `Platform.isMacOS`: the brain's
/// `nativeOnly` personas are filtered again by [playableFamilies] above, and
/// asking for a roster we then throw away is a wider door than it needs to be.
bool get wantsNativeRoster => ChessGptEngine.supported;
