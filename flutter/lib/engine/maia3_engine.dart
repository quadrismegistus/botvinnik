// Picks the Maia-3 transport for the platform: ort-web in a Worker on the
// web, ORT's native library over dart:ffi on macOS/iOS. Both run the same
// ONNX model with the same brain/maia3/ encode; both return RAW logits that
// only Maia3Api.computeMoveCurves knows how to read.
export 'maia3_engine_io.dart'
    if (dart.library.js_interop) 'maia3_engine_web.dart';
