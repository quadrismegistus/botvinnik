// The brain's CLASS table: for each move classification, its glyph, colour,
// and noun. Everything that renders a graded move — the Insights card, the
// move list, the win chart, the review strip — reads its marks from here.
//
// (The file keeps its name for now; it once held the under-board grade strip,
// which moved into the Insights card so the board could take back the height.)

import 'package:flutter/material.dart';

/// The brain's CLASS table {label: {glyph, color, noun}}, provided at boot.
class ClassTable {
  final Map<String, dynamic> raw;
  const ClassTable(this.raw);

  String glyph(String label) => (raw[label]?['glyph'] as String?) ?? '';

  /// Icon stand-ins for the three glyphs no bundled font contains.
  ///
  /// The brain ships `★` best, `✔` excellent, `✓` good (classifications.ts).
  /// None is in Roboto, so drawing them made Flutter web fetch a Noto face
  /// from fonts.gstatic.com — on the verdict line under the board, i.e. on
  /// every graded move. That is a third-party request, and unservable on a
  /// cold offline start.
  ///
  /// The other six (`‼ ! ?! ? × ??`) are Roboto-covered and stay as text.
  /// Substituting on THIS side rather than in classifications.ts leaves the
  /// Svelte app's rendering alone, where browser fallback fonts have them.
  static const Map<String, IconData> _iconGlyphs = {
    'best': Icons.star,
    'excellent': Icons.done_all,
    'good': Icons.check,
  };

  /// The label's mark, as an inline span: an icon where Roboto has no glyph,
  /// plain text otherwise. Callers use `Text.rich` so the noun beside it keeps
  /// the normal font.
  InlineSpan glyphSpan(String label, {double size = 13, Color? color}) {
    final icon = _iconGlyphs[label];
    if (icon == null) return TextSpan(text: glyph(label));
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(icon, size: size, color: color ?? this.color(label)),
    );
  }

  String noun(String label) => (raw[label]?['noun'] as String?) ?? label;
  Color color(String label) {
    final hex = raw[label]?['color'] as String?;
    if (hex == null || !hex.startsWith('#')) return Colors.white70;
    final v = int.parse(hex.substring(1), radix: 16);
    return Color(0xFF000000 | v);
  }
}
