// The Dart side of the square-control bridge shape (#56): the marshalling
// boundary (ControlCell.fromJson) and the margin → tint-intensity mapping the
// painter grades opacity by (controlTintGrade). The on-device parity test
// proves the brain emits {side,margin,held} correctly; these prove the Dart
// side CONSUMES it correctly — the half no fixture replay covers.
//
//   cd flutter && flutter test test/control_cell_test.dart

import 'package:botvinnik_mobile/brain/chess_api.dart';
import 'package:botvinnik_mobile/ui/board_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ControlCell.fromJson', () {
    test('reads an integer margin as a double', () {
      final c = ControlCell.fromJson({'side': 'b', 'margin': 9, 'held': false});
      expect(c.side, 'b');
      expect(c.margin, 9.0);
      expect(c.held, isFalse);
    });

    test('tolerates a fractional margin without throwing', () {
      // The brain only emits integer margins today, but the cast is `as num`
      // .toDouble() precisely so a future fractional margin can't crash the
      // board — pin that.
      final c = ControlCell.fromJson({'side': 'w', 'margin': 2.5, 'held': false});
      expect(c.margin, 2.5);
    });

    test('defaults held to false when the key is absent', () {
      final c = ControlCell.fromJson({'side': 'w', 'margin': 0});
      expect(c.held, isFalse);
    });

    test('carries held through when the brain opts it on', () {
      final c = ControlCell.fromJson({'side': 'w', 'margin': 0, 'held': true});
      expect(c.held, isTrue);
    });
  });

  group('controlTintGrade', () {
    test('margin 0 keeps the old flat look (1.0x)', () {
      expect(controlTintGrade(0), 1.0);
    });

    test('a queen (margin 9) doubles the intensity (2.0x)', () {
      expect(controlTintGrade(9), 2.0);
    });

    test('scales linearly between', () {
      expect(controlTintGrade(4.5), closeTo(1.5, 1e-9));
    });

    test('clamps a margin beyond 9 rather than overshooting', () {
      expect(controlTintGrade(100), 2.0,
          reason: 'a hypothetical king-scale margin must not push alpha over 2x');
    });

    test('clamps a negative margin up to the flat baseline', () {
      expect(controlTintGrade(-3), 1.0);
    });
  });
}
