// The offline opening book: two baked assets, no lichess at runtime.
//  - openings.json: the canonical ECO/name table (lichess/chess-openings)
//  - book.json: move statistics counted from a public lichess database
//    dump by scripts/build-book-from-dump.mts
// Both keyed by EPD (fen fields 1-4). Loaded lazily on first Book view.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class BookStore extends ChangeNotifier {
  Map<String, dynamic> _book = const {};
  Map<String, dynamic> _openings = const {};
  String source = '';
  bool loaded = false;
  bool _loading = false;

  Future<void> ensureLoaded() async {
    if (loaded || _loading) return;
    _loading = true;
    try {
      final bookDoc = jsonDecode(await rootBundle.loadString('assets/book.json'))
          as Map<String, dynamic>;
      _book = (bookDoc['book'] as Map).cast<String, dynamic>();
      source = (bookDoc['source'] as String?) ?? '';
      final opDoc =
          jsonDecode(await rootBundle.loadString('assets/openings.json'))
              as Map<String, dynamic>;
      _openings = (opDoc['openings'] as Map).cast<String, dynamic>();
    } finally {
      loaded = true;
      _loading = false;
      notifyListeners();
    }
  }

  static String epd(String fen) => fen.split(' ').take(4).join(' ');

  /// Book stats for a position, or null when out of book.
  Map<String, dynamic>? node(String fen) =>
      (_book[epd(fen)] as Map?)?.cast<String, dynamic>();

  /// [eco, name] when this exact position is a named opening.
  List<String>? openingAt(String fen) =>
      (_openings[epd(fen)] as List?)?.cast<String>();

  /// The opening the game is IN: the deepest named position along the
  /// played path (fens oldest→newest).
  List<String>? openingFor(List<String> fens) {
    for (final fen in fens.reversed) {
      final hit = openingAt(fen);
      if (hit != null) return hit;
    }
    return null;
  }
}
