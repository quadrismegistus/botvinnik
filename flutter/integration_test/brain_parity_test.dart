// On-device fixture replay: the golden fixtures (emitted from the web TS,
// pinned in git) played through the REAL JsBridge on the simulator. This is
// the layer that catches marshalling bugs — null vs undefined, number
// precision, dropped fields — that node replay can't see.
//
//   cd flutter && flutter test integration_test/brain_parity_test.dart \
//       -d <simulator-id>

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/brain/js_bridge.dart';

const double _tol = 1e-6;

bool deepEqual(dynamic a, dynamic b, Set<String> ignore) {
  if (identical(a, b)) return true;
  if (a is num && b is num) {
    final scale = [1.0, a.abs().toDouble(), b.abs().toDouble()]
        .reduce((x, y) => x > y ? x : y);
    return (a - b).abs() <= _tol * scale;
  }
  if (a == null || b == null) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEqual(a[i], b[i], ignore)) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    final ka = a.keys.where((k) => !ignore.contains(k) && a[k] != null).toSet();
    final kb = b.keys.where((k) => !ignore.contains(k) && b[k] != null).toSet();
    if (ka.length != kb.length) return false;
    for (final k in ka) {
      if (!kb.contains(k) || !deepEqual(a[k], b[k], ignore)) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('brain fixtures replay identically through the bridge',
      (tester) async {
    final bridge = await JsBridge.load();
    final doc = jsonDecode(
        await rootBundle.loadString('assets/brain-fixtures.json'))
        as Map<String, dynamic>;
    final fixtures = (doc['fixtures'] as List).cast<Map<String, dynamic>>();

    final failures = <String>[];
    for (var i = 0; i < fixtures.length; i++) {
      final f = fixtures[i];
      final fn = f['fn'] as String;
      final args = (f['args'] as List)
          .map((a) => a == '__OMIT__' ? JsBridge.omit : a)
          .toList();
      dynamic actual;
      try {
        actual = bridge.call(fn, args: args);
      } catch (e) {
        failures.add('[$i] $fn threw: $e');
        continue;
      }
      final ignore = ((f['ignore'] as List?) ?? const []).cast<String>().toSet();
      if (!deepEqual(actual, f['expected'], ignore)) {
        failures.add('[$i] $fn:\n'
            '  expected ${jsonEncode(f['expected'])}\n'
            '  actual   ${jsonEncode(actual)}');
      }
    }

    bridge.dispose();
    expect(failures, isEmpty,
        reason: 'fixture mismatches:\n${failures.join('\n')}');
  });
}
