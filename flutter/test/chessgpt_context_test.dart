// The context window ChessGPT is handed (#235 follow-up).
//
// The bug this exists to keep out: the prompt was truncated to exactly
// [kBlockSize], the model's trained positional-embedding size, and the
// sampling loop then APPENDED characters to it. The second forward pass was
// therefore kBlockSize + 1 long, which ORT rejects — and package:onnxruntime
// raises that on the native-callback side, outside the engine's catch, so the
// future never completed. The board sat with ChessGPT to move, nothing
// thinking, input refused, until the app was killed.
//
// It was reached at ply 183-185 of an ordinary game — move 92-93 — and past
// that point EVERY move hung, because the truncation pins the context at the
// ceiling on every attempt. Not a rare game either: 93 moves is a long
// endgame, not a pathological one.
//
// Pure integer arithmetic, deliberately in its own file: the engine imports
// package:onnxruntime and so exists only where the FFI runtime does, and this
// invariant must be checkable on CI's Linux rather than only on a Mac.
//
//   cd flutter && flutter test test/chessgpt_context_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/chessgpt_context.dart';

List<int> _ids(int n) => List<int>.generate(n, (i) => i % 31);

void main() {
  test('a short prompt is handed over whole', () {
    expect(contextWindow(_ids(40), reserve: kMaxSanChars), hasLength(40));
    expect(contextWindow(_ids(40)), hasLength(40));
  });

  test('the TAIL is kept, not the head', () {
    // The recent moves are the ones that decide the next one, and a game long
    // enough to overflow is off the distribution anyway.
    final ids = _ids(kBlockSize + 500);
    final w = contextWindow(ids);
    expect(w.last, ids.last);
    expect(w.first, ids[ids.length - w.length]);
  });

  test('never more positions than the model was trained with', () {
    for (final n in [kBlockSize - 1, kBlockSize, kBlockSize + 1, 4000]) {
      expect(contextWindow(_ids(n)).length, lessThanOrEqualTo(kBlockSize),
          reason: 'a $n-token game overflowed the embedding');
    }
  });

  // The assertion the bug turns on. Truncating to kBlockSize satisfies every
  // test above and still hangs the board, because the loop appends AFTER this
  // returns — so what has to hold is the prompt PLUS what is coming.
  test('a prompt leaves room for the characters about to be appended', () {
    for (final n in [kBlockSize - 1, kBlockSize, kBlockSize + 1, 4000]) {
      final prompt = contextWindow(_ids(n), reserve: kMaxSanChars);
      expect(prompt.length + kMaxSanChars, lessThanOrEqualTo(kBlockSize),
          reason: 'a $n-token game leaves no room to sample into');
    }
  });

  test('and the whole sampling run stays inside the window', () {
    // The loop, simulated: take the prompt, append the most characters it can,
    // and re-window on every step exactly as the engine does. Nothing at any
    // point may exceed kBlockSize — that is the input ORT actually sees.
    final work = List<int>.of(contextWindow(_ids(9999), reserve: kMaxSanChars));
    for (var i = 0; i < kMaxSanChars; i++) {
      expect(contextWindow(work).length, lessThanOrEqualTo(kBlockSize),
          reason: 'forward pass ${i + 1} was over the ceiling');
      work.add(7);
    }
    expect(contextWindow(work).length, lessThanOrEqualTo(kBlockSize));
  });

  test('a reserve larger than the window still yields something to run on', () {
    // Degenerate, but it must not produce an empty tensor: ORT on a zero-length
    // input is a different crash, not a smaller one.
    expect(contextWindow(_ids(50), reserve: kBlockSize * 2), isNotEmpty);
  });
}
