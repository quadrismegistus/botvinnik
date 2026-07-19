// What a Maia is doing while it is not yet playing.
//
// Deliberately not in maia_engine.dart: that file is a conditional export and
// can hold nothing of its own, and both the web engine and the native stub
// need this shape.

/// A Maia move that is waiting on something other than inference.
class MaiaProgress {
  /// `fetching` — pulling the band's weights over the network.
  /// `starting` — compiling the ONNX runtime and building the session.
  final String phase;

  /// Bytes of the model received so far, and the total if the server said.
  /// Both zero during `starting`, which has no measurable denominator.
  final int received;
  final int total;

  const MaiaProgress(this.phase, {this.received = 0, this.total = 0});

  /// 0..1, or null when the server sent no content-length. Null means "show
  /// bytes, not a bar" rather than "show a bar at zero".
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)}MB';

  /// A line to put in front of a person who is waiting.
  ///
  /// The old copy promised "about 3.5MB, once" — true of the weights and a
  /// roughly 2x understatement of the first Maia ever, which also pulls the
  /// ~3.3MB (gzipped) ONNX runtime. Real numbers as they arrive beat a
  /// confident wrong one.
  String describe(String personaName) => switch (phase) {
        'fetching' => total > 0
            ? 'Downloading $personaName — ${_mb(received)} of ${_mb(total)}'
            : 'Downloading $personaName — ${_mb(received)}',
        // The runtime is ~13MB of WebAssembly to compile and this is where a
        // slow phone sits for a few seconds with nothing else to report.
        _ => 'Starting $personaName’s neural net…',
      };
}
