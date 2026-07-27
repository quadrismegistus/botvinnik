// How much of a game ChessGPT is allowed to see at once.
//
// Split out of chessgpt_engine_io.dart, which imports package:onnxruntime and
// so only exists on the platforms with the FFI runtime — this is pure integer
// arithmetic and the invariant it enforces is the one that hung the board, so
// it needs to be checkable on CI's Linux rather than only on a Mac.
//
// The invariant: the model was trained with a positional embedding of exactly
// [kBlockSize] positions, and the sampling loop APPENDS to whatever context it
// is given. So the prompt has to leave room for what is about to be added to
// it. Pinning the prompt at kBlockSize instead made the second forward pass
// kBlockSize + 1 long, which ORT rejects — and package:onnxruntime raises that
// on the native-callback side, where the engine's catch cannot see it, so the
// future never completed and the bot's turn never ended.

import 'dart:math';

/// The model's trained context, exactly: `gpt.wpe.weight` is [1023, 512].
const int kBlockSize = 1023;

/// The longest SAN is 7 characters ("Qa1xb2#"); 10 leaves room and still
/// bounds a runaway sample.
const int kMaxSanChars = 10;

/// The tail of [ids] the model may be handed, keeping [reserve] positions free
/// for characters the caller is going to append.
///
/// The head is dropped rather than the tail: a game long enough to overflow is
/// already off the distribution, and the recent moves are the ones that
/// determine the next one.
List<int> contextWindow(List<int> ids, {int reserve = 0}) {
  final room = max(1, kBlockSize - reserve);
  return ids.length > room ? ids.sublist(ids.length - room) : ids;
}
