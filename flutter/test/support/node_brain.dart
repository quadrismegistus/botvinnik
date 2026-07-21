// A [JsBridge] that runs the REAL bundle, in node.
//
// Every other Dart-side test of a brain call fakes the far side, which is fine
// for asserting what crosses the bridge and useless for asserting what the
// brain does with it. `estimatePlayerElo` is the case where that distinction
// is the whole point: its job is as much refusing games as fitting them, and a
// stub bridge that returns a canned estimate proves a refusal that never
// happened.
//
// So this evaluates assets/brain.js — the same bundle the app ships, byte for
// byte, which CI already pins against its TypeScript sources — through the
// same [buildBrainExpr] the real bridges use. What it cannot cover is the
// transport: JavaScriptCore on native and the browser on web are still their
// own thing. What it does cover is the marshalling and the brain's behaviour
// over realistic records.
//
// Node is not an optional dependency of this repo (the bundle cannot be built
// without it, and CI's flutter job installs it before running these tests), so
// a missing node FAILS rather than skips. A skipped exclusion test is exactly
// as reassuring as no exclusion test.

import 'dart:convert';
import 'dart:io';

import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/js_bridge_shared.dart';

/// The loader. The bundle opens with `"use strict"` and hangs itself off a
/// top-level `var brain`, which in a node module scope would be module-local
/// and unreachable — so it is evaluated as a function body that hands `brain`
/// back. argv[1] is the bundle path and argv[2] the expression.
const String _kLoader = r'''
const fs = require('fs');
const src = fs.readFileSync(process.argv[1], 'utf8');
const brain = new Function(src + '; return brain;')();
const out = new Function('brain', 'return ' + process.argv[2] + ';')(brain);
process.stdout.write(out === undefined ? 'undefined' : String(out));
''';

class NodeBrainBridge implements JsBridge {
  /// Every expression evaluated, in order — so a test can assert what actually
  /// crossed, not only what came back.
  final List<String> exprs = [];

  /// Relative to the CWD `flutter test` runs in, like the font paths in
  /// review_summary_test.dart.
  static const String bundle = 'assets/brain.js';

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final expr = buildBrainExpr(fn, args, isProperty);
    exprs.add(expr);
    final proc = Process.runSync('node', ['-e', _kLoader, bundle, expr],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    if (proc.exitCode != 0) {
      throw StateError('node failed on `$fn`:\n${proc.stderr}');
    }
    return decodeBrainResult(proc.stdout as String);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
