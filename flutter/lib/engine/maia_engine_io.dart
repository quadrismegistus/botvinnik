// Maia on native: not yet. [MaiaEngine.supported] is false, so the roster
// picker does not offer the six Maia personas here.
//
// This is the most tractable of the three native gaps, and the only one with
// a real pub package waiting for it:
//
//   * **onnxruntime** (pub) wraps ORT's native library via FFI, so there is no
//     runtime to port — the model, the input shape and the output are all the
//     same artifacts the web uses. Import it lazily; an eager import is what
//     put ort-web in the Svelte app's entry chunk and cost every visitor
//     ~190KB for a bot most of them never pick.
//   * **The encoding and decoding are already shared.** brain/maia/ holds both
//     as pure functions, so native needs no new chess logic — only a way to
//     call them. They are synchronous and fast, which is exactly the shape the
//     brain bridge can carry, unlike Garbo's search or retro's engines.
//   * **The weights still cannot be bundled.** They are GPL-3.0, which is why
//     they are fetched at runtime rather than shipped. On iOS that means a
//     download on first use and somewhere sensible to cache it — the one
//     genuinely new piece of work here.
//
// So: not blocked, and unlike Garbo not awkward. Just not done.

class MaiaEngine {
  MaiaEngine({this.onFetching});

  final void Function()? onFetching;

  static bool get supported => false;

  Future<String?> move(
    List<String> fenHistory, {
    required int band,
    double temperature = 0,
  }) async =>
      null;

  void dispose() {}
}
