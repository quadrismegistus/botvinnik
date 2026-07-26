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

  group('the published net is pinned', () {
    // Not a verification of the ARTEFACT — a unit test cannot fetch 26MB — but
    // of the two constants that address it. Both were pasted by hand, and the
    // failure mode of a typo in either is a persona that silently never loads,
    // because [load] treats every error as "unavailable".
    //
    // The artefact itself was verified by downloading the published asset and
    // comparing digests; that check lives in the release, not here.
    test('the url points at a botvinnik-engines release asset', () {
      expect(ChessGptWeights.url, isNotEmpty,
          reason: 'empty is the pre-publication state and disables the persona');
      expect(ChessGptWeights.url, startsWith('https://'));
      expect(ChessGptWeights.url,
          contains('botvinnik-engines/releases/download/'));
      expect(ChessGptWeights.url, endsWith('.onnx'));
    });

    test('the checksum is a lowercase hex sha-256', () {
      expect(ChessGptWeights.sha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'uppercase or a truncated paste would reject every download');
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
