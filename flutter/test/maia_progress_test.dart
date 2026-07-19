// The copy a person reads while a Maia is not yet playing.
//
// Worth testing because the previous version of this feature was invisible:
// the download line lived in GameController.statusLine, whose two call sites
// both sit behind `if (game.gameOver)`. It was correct, and never once shown.
//
//   cd flutter && flutter test test/maia_progress_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/maia_progress.dart';

void main() {
  group('fraction', () {
    test('is null without a content-length, so the bar goes indeterminate', () {
      // Honest: a determinate bar stuck at 0 reads as broken, and a server
      // that sent no length gives us nothing to divide by.
      expect(const MaiaProgress('fetching', received: 900).fraction, isNull);
      expect(const MaiaProgress('starting').fraction, isNull);
    });

    test('is the ratio when the server said how big it is', () {
      expect(const MaiaProgress('fetching', received: 50, total: 200).fraction,
          0.25);
    });

    test('cannot exceed 1, however the server counts', () {
      // gzip means received (decoded) can overshoot a compressed
      // content-length; a bar past its own end is a visible glitch
      expect(const MaiaProgress('fetching', received: 300, total: 200).fraction,
          1.0);
    });
  });

  group('describe', () {
    test('names the persona and both real numbers while downloading', () {
      final line = const MaiaProgress('fetching',
              received: 1048576, total: 3670016)
          .describe('Maia I');
      expect(line, contains('Maia I'));
      expect(line, contains('1.0MB'));
      expect(line, contains('3.5MB'));
    });

    test('reports bytes alone when there is no total', () {
      final line =
          const MaiaProgress('fetching', received: 2097152).describe('Maia V');
      expect(line, contains('2.0MB'));
      expect(line, isNot(contains('of ')));
    });

    test('the runtime phase says what it is doing, not a number', () {
      // ~13MB of WebAssembly to compile, reporting nothing. It is the longest
      // part of the wait on a phone, so it needs a name of its own rather than
      // a finished bar sitting there.
      final line = const MaiaProgress('starting').describe('Maia IX');
      expect(line, contains('Maia IX'));
      expect(line.toLowerCase(), contains('neural net'));
      expect(line, isNot(contains('MB')));
    });

    test('never promises a size it does not know', () {
      // The old copy said "about 3.5MB, once" — true of the weights, and
      // roughly half the truth for the first Maia ever, which also pulls the
      // ~3.3MB gzipped runtime. Nothing here should hardcode a size.
      for (final p in [
        const MaiaProgress('fetching', received: 10, total: 20),
        const MaiaProgress('fetching', received: 10),
        const MaiaProgress('starting'),
      ]) {
        expect(p.describe('Maia I'), isNot(contains('3.5MB')),
            reason: 'hardcoded the old promise');
      }
    });
  });
}
