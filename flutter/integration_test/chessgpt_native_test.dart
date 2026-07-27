// ChessGPT through the REAL native path on macOS: package:onnxruntime over
// FFI, against the three int8 nets fetched from our own release into
// Application Support.
//
// A unit test cannot reach any of it, and every failure path in
// ChessGptEngine/ChessGptWeights returns null — which GameController turns
// into a Stockfish stand-in. So a completely broken ChessGPT still plays; it
// just is not ChessGPT. That is exactly how a shipped artefact that could not
// even open went unnoticed here once already (IR version 10 against a runtime
// capping at 9), so this file exists to make that failure loud.
//
// THE EXPECTED MOVES ARE A CROSS-IMPLEMENTATION REFERENCE. They were produced
// by running each published artefact under Python + onnxruntime with no torch
// present, at temperature 0. The Dart path uses the same vocabulary, graph and
// argmax, so it must agree. Asserting merely that a move is legal would pass
// on a reversed vocabulary, a malformed prompt, or — the one that still
// downloads, runs and plays perfectly — a url serving a different variant than
// the persona asked for.
//
// WHY INDEPENDENT PROMPTS RATHER THAN ONE SELF-PLAY LINE. The first version of
// this test pinned twelve plies of the model playing itself, and it was wrong.
// After 1.e4 e5 2.Nf3 Nc6 3.Bc4 the lichess net scores 'B' (Bc5) at 6.67442
// and 'N' (Nf6) at 6.67299 — a gap of 0.0014, which is below the rounding
// difference between two onnxruntime VERSIONS on an int8 model. Python picked
// the Italian, the app picked the Two Knights, and both were right. A
// self-play line then compounds that one coin-flip through every later ply.
//
// So each case below is an independent prompt whose answer is DECISIVE, and
// the recorded top-2 logit gap is the margin of safety. The smallest is 0.479
// — some 340x the tie that broke the first design.
//
//   cd flutter && flutter test integration_test/chessgpt_native_test.dart -d macos
//
// First run downloads ~78MB (three nets). Later runs are cached.

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/engine/chessgpt_engine.dart';
import 'package:botvinnik_mobile/engine/chessgpt_weights.dart';

/// A prompt, the position it describes, and what each net answers.
///
/// The last two DISCRIMINATE: the King's Indian prompt draws a different move
/// from all three nets, so a variant fetching the wrong file fails here rather
/// than playing plausibly under the wrong name for the life of the feature.
const _cases = <({
  String label,
  String pgn,
  String fen,
  Map<String, String> expected,
})>[
  (
    label: 'the opening move',
    pgn: ';1.',
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    // gaps: lichess 0.937, stockfish 0.660, mix 0.558
    expected: {'lichess': 'e4', 'stockfish': 'e4', 'mix': 'e4'},
  ),
  (
    label: "white's second move in the open game",
    pgn: ';1.e4 e5 2.',
    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
    // gaps: lichess 1.835, stockfish 2.683, mix 2.387
    expected: {'lichess': 'Nf3', 'stockfish': 'Nf3', 'mix': 'Nf3'},
  ),
  (
    label: 'move 6 of a Najdorf — the mix net parts company',
    pgn: ';1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6 6.',
    fen: 'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 6',
    // gaps: lichess 2.564, stockfish 2.282, mix 2.148
    expected: {'lichess': 'Be3', 'stockfish': 'Be3', 'mix': 'Be2'},
  ),
  (
    label: 'move 7 of a King\'s Indian — all three disagree',
    pgn: ';1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4 d6 5.Nf3 O-O 6.Be2 e5 7.',
    fen: 'rnbq1rk1/ppp2pbp/3p1np1/4p3/2PPP3/2N2N2/PP2BPPP/R1BQK2R w KQ - 0 7',
    // gaps: lichess 0.479, stockfish 0.772, mix 0.541 — the tightest set here,
    // and still far outside int8 runtime noise.
    expected: {'lichess': 'O-O', 'stockfish': 'd5', 'mix': 'dxe5'},
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('all three nets are published, intact, and openable', () async {
    expect(ChessGptWeights.supported, isTrue, reason: 'macOS/iOS only');
    for (final v in ChessGptWeights.variants) {
      final bytes = await ChessGptWeights.load(v.id);
      expect(bytes, isNotNull,
          reason: '${v.id} did not arrive — a 404, or a checksum mismatch, '
              'which load() cannot distinguish from a dead network');
      expect(bytes!.length, v.bytes,
          reason: 'the size pinned in the variant table is wrong');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  for (final v in ChessGptWeights.variants) {
    test('${v.id} answers its reference prompts', () async {
      final engine = ChessGptEngine(v.id);
      addTearDown(engine.dispose);

      for (final c in _cases) {
        final pos = Chess.fromSetup(Setup.parseFen(c.fen));
        final san = await engine.pickMove(c.pgn,
            isLegalSan: (s) => pos.parseSan(s) != null);
        expect(san, c.expected[v.id],
            reason: '${v.id} on ${c.label}: the net either did not load '
                '(null), or this is not the net we think it is');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test('the nets are genuinely different files, not one copied three times',
      () async {
    // The discriminating prompt, read across variants in one place. Publishing
    // three assets from the same source file is a plausible slip, and it would
    // otherwise show up only as three personas that feel identical.
    final answers = <String, String>{};
    for (final v in ChessGptWeights.variants) {
      final engine = ChessGptEngine(v.id);
      addTearDown(engine.dispose);
      final c = _cases.last;
      final pos = Chess.fromSetup(Setup.parseFen(c.fen));
      final san = await engine.pickMove(c.pgn,
          isLegalSan: (s) => pos.parseSan(s) != null);
      answers[v.id] = san ?? '(none)';
    }
    expect(answers.values.toSet().length, 3,
        reason: 'three nets should give three answers here, got $answers');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a long game does not hang the board', () async {
    // The failure this replaces was a HANG, not a wrong move. The prompt was
    // truncated to exactly the model's 1023-position embedding and the
    // sampling loop then appended to it, so the second forward pass was 1024
    // long. ORT rejects that ("cannot broadcast 1023 by 1024") — and
    // package:onnxruntime raises it on the native-callback side, outside the
    // engine's catch, so the future never completed. GameController awaits
    // pickMove with no timeout of its own: the board sat with ChessGPT to
    // move, nothing thinking, input refused, until the app was killed. At 0%
    // CPU, for as long as you cared to wait.
    //
    // Reached at ply 183-185 — move 92-93 — of an ordinary game, and past it
    // EVERY move hung, because the truncation pins the context at the ceiling
    // on every attempt.
    //
    // Only an integration test can see it: the arithmetic is pinned in pure
    // Dart by chessgpt_context_test.dart, but "does the FFI future actually
    // complete" is a question about the runtime.
    final engine = ChessGptEngine(ChessGptWeights.variants.first.id);
    addTearDown(engine.dispose);

    // Well past the ceiling, so the window is doing real work. Legality is not
    // the claim — the prompt is synthetic and the model may answer with
    // anything — only that it ANSWERS.
    final long = ';1.${'e4 e5 Nf3 Nc6 Bc4 Bc5 ' * 200}';
    expect(long.length, greaterThan(1023), reason: 'precondition');

    var returned = false;
    final move = await engine
        .pickMove(long, isLegalSan: (_) => true)
        .then((v) {
      returned = true;
      return v;
    }).timeout(const Duration(minutes: 3), onTimeout: () => '(hung)');

    expect(returned, isTrue,
        reason: 'pickMove never completed — the board would be dead');
    expect(move, isNot('(hung)'));
    expect(move, isNotNull,
        reason: 'a null here is the Stockfish stand-in, i.e. still broken');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a variant nobody publishes is unavailable, not a crash', () async {
    // GameController falls through to the Stockfish stand-in on a null, which
    // is the right answer for an id that does not exist — a persona from a
    // newer build read out of an archived game, say.
    expect(ChessGptWeights.variantFor('no-such-net'), isNull);
    expect(await ChessGptWeights.load('no-such-net'), isNull);
    expect(
        await ChessGptEngine('no-such-net')
            .pickMove(';1.', isLegalSan: (_) => true),
        isNull);
  });
}
