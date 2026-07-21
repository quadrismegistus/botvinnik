// The Maia weights cache on the web: nothing this side of the app owns.
//
// The browser's copy lives in IndexedDB, written by web/maia/maia-worker.js
// on the first move that needs a band — so there is no file to check and no
// download to start from here.
//
// And that is deliberate rather than merely unimplemented. #30 stopped
// shipping these weights to every visitor; ~10MB of unasked-for download is a
// much less friendly thing to do to somebody who opened a tab than to somebody
// who installed an app, so native prefetches (see maia_weights_io.dart) and
// the web keeps fetching on demand.
//
// [MaiaWeights.cached] therefore stays null — "nobody has looked", not "none
// of them are there". The roster picker says the same thing it always said on
// this platform: a short download the first time, then it plays offline.

import 'package:flutter/foundation.dart';

class MaiaWeights {
  MaiaWeights._();

  /// The three nets behind six personas, as on native.
  static const List<int> bands = [1100, 1500, 1900];

  static final ValueNotifier<Set<int>?> _cached = ValueNotifier(null);

  /// Always null here: the worker's IndexedDB cache is not visible from Dart,
  /// and guessing would be worse than admitting it.
  static ValueListenable<Set<int>?> get cached => _cached;

  /// Deliberately nothing.
  static Future<void> prefetch() async {}

  /// Deliberately nothing — there is no file to look for.
  static Future<void> refresh() async {}
}
