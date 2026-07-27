// ChessGPT over ORT: a language model that learned chess by reading a million
// human games, as a bot persona.
//
// Adam Karvonen's nanoGPT trained on Lichess PGN text (arxiv 2403.15498). It
// is a next-CHARACTER predictor over movetext — ";1.e4 e5 2." and so on — with
// no search of any kind, which is the whole reason it is interesting here:
// every other bot on the roster is one Stockfish dialled down, so their
// mistakes are all the same engine's mistakes with the calculation cut short.
// This one's are its own.
//
// NO STRENGTH FIGURE HERE ON PURPOSE. This file carried "~1250 on our ladder,
// draws about six games in ten" and both were artefacts of the harness, not
// measurements of the model. Every run seeded a 4-ply opening and handed the
// engine a bare FEN; playing Black, the model's first position was 5 plies
// deep, past what the UCI shim's bounded backward search could reconstruct,
// so it declined the move — and a declined move was tallied as a DRAW. Half
// of every run was that, not chess. The harnesses now send `position startpos
// moves ...`, and a figure goes here when one has been measured through them.
//
// THE INPUT IS MOVETEXT, NOT A POSITION — which is the root of the artefact
// above, and worth stating plainly because it does not look like a constraint
// until it silently becomes one. There is no way to hand this model a FEN: a
// position with no history is off-distribution and it produces noise. That
// costs nothing HERE, because [GameController] holds the move list anyway and
// [movesToPgn] takes it directly. It costs a great deal at any boundary that
// speaks FEN, which is most of them.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'chessgpt_weights.dart';

/// The 32 characters the model was trained on: SAN, and nothing else.
///
/// Order is load-bearing — it IS the tokenizer, taken from the author's own
/// meta.pkl rather than reconstructed, because a plausible-looking vocabulary
/// in the wrong order encodes silently wrong instead of failing.
const String kChessGptVocab = ' #+-.0123456789;=BKNOQRabcdefghx';

/// The longest SAN is 7 characters ("Qa1xb2#"); 10 leaves room and still
/// bounds a runaway sample.
const int _kMaxSanChars = 10;

/// Trained context. A game long enough to overflow it is already off the
/// distribution, so the tail is kept and the head dropped.
const int _kBlockSize = 1023;

class _Net {
  _Net(this.session, this.tokensName, this.logitsName);
  final OrtSession session;
  final String tokensName;
  final String logitsName;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    session.release();
  }
}

class ChessGptEngine {
  /// One engine per VARIANT. The net is chosen at construction rather than per
  /// move because [_Net] holds an OrtSession over 26MB of weights: switching
  /// variants means a different session, not a different argument, and making
  /// that look like a parameter invites a caller to alternate them move by
  /// move and pay a full session build each time.
  ChessGptEngine(this.variantId);

  final String variantId;

  /// ORT's native library, so the same platforms Maia runs on. The web build
  /// returns false — see chessgpt_engine_web.dart for why this one is not
  /// merely unported but a poor fit there.
  static bool get supported => ChessGptWeights.supported;

  static bool _envReady = false;
  static final Map<int, int> _stoi = {
    for (var i = 0; i < kChessGptVocab.length; i++) kChessGptVocab.codeUnitAt(i): i
  };

  _Net? _net;
  Future<_Net?>? _loading;

  /// Movetext in the shape the model was trained on: `;1.e4 e5 2.Nf3 ` with
  /// the number before each WHITE move and nothing before Black's.
  ///
  /// The trailing move number matters. Asked to continue ";1.e4 e5 " the model
  /// dutifully starts writing "2", which is not a move — so a white move must
  /// be prompted with its number already present.
  static String movesToPgn(List<String> sans, {required bool whiteToMove, required int fullmove}) {
    final b = StringBuffer(';');
    for (var i = 0; i < sans.length; i++) {
      if (i.isEven) b.write('${(i ~/ 2) + 1}.');
      b
        ..write(sans[i])
        ..write(' ');
    }
    if (whiteToMove) b.write('$fullmove.');
    return b.toString();
  }

  Future<_Net?> _ensure() => _loading ??= _load();

  Future<_Net?> _load() async {
    if (!supported) return null;
    final bytes = await ChessGptWeights.load(variantId);
    if (bytes == null) return null;
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    // Single-threaded, as Maia is: a 26MB net sharing a phone with the UI is
    // better off staying out of the scheduler's way.
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1);
    try {
      final session = OrtSession.fromBuffer(bytes, options);
      final inName = session.inputNames.first;
      final outName = session.outputNames.first;
      _net = _Net(session, inName, outName);
      return _net;
    } catch (e) {
      // Logged, not swallowed. Every failure here becomes a null that
      // GameController reads as "use the Stockfish stand-in", so a broken
      // runtime is indistinguishable from a slow network unless it says so.
      debugPrint('[chessgpt] session build failed for $variantId: $e');
      return null;
    } finally {
      options.release();
    }
  }

  /// One forward pass: the logits for the NEXT character.
  ///
  /// The graph returns only the final position's row — sampling needs one, and
  /// shipping the whole (1, T, 32) tensor across the FFI boundary to discard
  /// T-1 of it is pure cost.
  Future<Float32List?> _logits(_Net net, List<int> ids) async {
    final t = Int64List.fromList(ids);
    final input = OrtValueTensor.createTensorWithDataList(t, [1, ids.length]);
    final run = OrtRunOptions();
    try {
      final outs = await net.session.runAsync(run, {net.tokensName: input}, [net.logitsName]);
      if (outs == null || outs.isEmpty) return null;
      final v = outs.first?.value;
      outs.first?.release();
      if (v is List && v.isNotEmpty && v.first is List) {
        return Float32List.fromList(
            (v.first as List).map((e) => (e as num).toDouble()).toList());
      }
      return null;
    } catch (e) {
      debugPrint('[chessgpt] inference failed: $e');
      return null;
    } finally {
      input.release();
      run.release();
    }
  }

  /// The model's move for [pgn], as SAN — or null if it never produced one.
  ///
  /// [isLegalSan] is the caller's legality check; the model emits characters,
  /// not moves, and nothing in its objective distinguishes a legal move from a
  /// plausible-looking illegal one.
  ///
  /// An illegal sample is RETRIED with temperature, never replaced by a random
  /// legal move: a random move is a different player wearing this one's name,
  /// and this persona exists precisely because its choices are its own.
  Future<String?> pickMove(
    String pgn, {
    required bool Function(String san) isLegalSan,
    double temperature = 0.0,
    Random? random,
  }) async {
    final net = await _ensure();
    if (net == null) return null;
    final rng = random ?? Random();

    for (var attempt = 0; attempt < 6; attempt++) {
      final temp = attempt == 0 ? temperature : max(0.5, temperature);
      final ids = <int>[];
      for (final unit in pgn.codeUnits) {
        final id = _stoi[unit];
        if (id != null) ids.add(id);
      }
      if (ids.isEmpty) return null;
      final ctx = ids.length > _kBlockSize ? ids.sublist(ids.length - _kBlockSize) : ids;

      final san = StringBuffer();
      final work = List<int>.of(ctx);
      for (var i = 0; i < _kMaxSanChars; i++) {
        final logits = await _logits(net, work);
        if (logits == null) return null;
        final next = temp <= 0 ? _argmax(logits) : _sample(logits, temp, rng);
        final ch = kChessGptVocab[next];
        if ((ch == ' ' || ch == ';') && san.isNotEmpty) break;
        san.write(ch);
        work.add(next);
      }
      final out = san.toString().trim();
      if (out.isNotEmpty && isLegalSan(out)) return out;
    }
    return null;
  }

  static int _argmax(Float32List v) {
    var best = 0;
    for (var i = 1; i < v.length; i++) {
      if (v[i] > v[best]) best = i;
    }
    return best;
  }

  static int _sample(Float32List v, double temp, Random rng) {
    var maxV = v[0];
    for (final x in v) {
      if (x > maxV) maxV = x;
    }
    var sum = 0.0;
    final p = Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      p[i] = exp((v[i] - maxV) / temp);
      sum += p[i];
    }
    var r = rng.nextDouble() * sum;
    for (var i = 0; i < p.length; i++) {
      r -= p[i];
      if (r <= 0) return i;
    }
    return p.length - 1;
  }

  void dispose() {
    _net?.release();
    _net = null;
    _loading = null;
  }
}
