// The one piece of ChessGPT that is pure logic and worth pinning: the PGN
// prompt. Everything else is ORT and a download.
//
//   cd flutter && flutter test test/chessgpt_engine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:botvinnik_mobile/engine/chessgpt_engine.dart';
// The io implementation directly, not the conditional export: [url] and
// [sha256Hex] address a native download and are deliberately absent from the
// web stub, whose shared surface is only supported/load/discard/isCached.
// Duplicating a checksum into a second file to satisfy an import is how the
// two drift apart.
import 'package:botvinnik_mobile/engine/chessgpt_weights_io.dart';

void main() {
  group('movesToPgn — the prompt the model was trained on', () {
    test('numbers white moves and not black ones', () {
      expect(
        ChessGptEngine.movesToPgn(['e4', 'e5', 'Nf3'],
            whiteToMove: false, fullmove: 2),
        ';1.e4 e5 2.Nf3 ',
      );
    });

    test('a WHITE move to play is prompted with its number', () {
      // Without the trailing number the model is asked to continue
      // ";1.e4 e5 " and starts writing "2", which is not a SAN. This showed up
      // as black-to-move working and white-to-move failing.
      expect(
        ChessGptEngine.movesToPgn(['e4', 'e5'], whiteToMove: true, fullmove: 2),
        ';1.e4 e5 2.',
      );
    });

    test('a BLACK move to play gets no number', () {
      expect(
        ChessGptEngine.movesToPgn(['e4'], whiteToMove: false, fullmove: 1),
        ';1.e4 ',
      );
    });

    test('the opening position is a bare semicolon plus the number', () {
      expect(ChessGptEngine.movesToPgn([], whiteToMove: true, fullmove: 1), ';1.');
    });
  });

  group('the published nets are pinned', () {
    // Not a verification of the ARTEFACTS — a unit test cannot fetch 78MB —
    // but of the constants that address them. Every one was pasted by hand,
    // and the failure mode of a typo is a persona that silently never loads,
    // because [load] treats every error as "unavailable".
    //
    // The artefacts themselves were verified by downloading each published
    // asset and comparing digests; that check lives in the release notes.
    test('there are three, and their ids are distinct and stable', () {
      // The id is the filename, the persona id AND the stored setting, so a
      // rename silently orphans a player's downloaded net and their choice of
      // opponent.
      expect(ChessGptWeights.variants.map((v) => v.id),
          containsAll(['lichess', 'stockfish', 'mix']));
      expect(ChessGptWeights.variants.map((v) => v.id).toSet().length,
          ChessGptWeights.variants.length);
    });

    test('each url points at the family release asset for its own id', () {
      for (final v in ChessGptWeights.variants) {
        expect(v.url, startsWith('https://'));
        // The TAG, not just the path. It is the only hand-pasted segment left
        // in the url, and getting it wrong 404s all three downloads while
        // every assertion about the filename still passes.
        expect(v.url,
            contains('botvinnik-engines/releases/download/chessgpt-8layers-int8/'));
        expect(v.url, endsWith('chessgpt-${v.id}-8layers-int8.onnx'),
            reason: 'a url pointing at another variant is the one mistake '
                'here that still downloads, runs, and plays the wrong bot');
      }
    });

    test('each checksum is a distinct lowercase hex sha-256', () {
      final seen = <String>{};
      for (final v in ChessGptWeights.variants) {
        expect(v.sha256, matches(RegExp(r'^[0-9a-f]{64}$')),
            reason: 'uppercase or a truncated paste rejects every download');
        expect(seen.add(v.sha256), isTrue,
            reason: 'two variants sharing a checksum means one was copied and '
                'not updated — and then one of them can never validate');
      }
    });

    test('variantFor round-trips every id and rejects an unknown one', () {
      for (final v in ChessGptWeights.variants) {
        expect(ChessGptWeights.variantFor(v.id)?.id, v.id);
      }
      expect(ChessGptWeights.variantFor('no-such-net'), isNull);
      expect(ChessGptWeights.variantFor(null), isNull);
    });
  });

  test('the vocabulary is the 32 characters the model was trained on', () {
    // Order IS the tokenizer — taken from the author's meta.pkl, not
    // reconstructed. A plausible vocabulary in the wrong order encodes
    // silently wrong rather than failing.
    expect(kChessGptVocab.length, 32);
    expect(kChessGptVocab, ' #+-.0123456789;=BKNOQRabcdefghx');
  });
}
