// The browser half of [saveTextFile] — see files.dart for why the web writes
// its own download instead of delegating to a share plugin.
//
// package:web + dart:js_interop rather than dart:html: dart:html is not
// available to the wasm compiler, and this would otherwise be the only file
// in the app standing in the way of that build.

import 'dart:js_interop';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

/// Write [text] out under [filename]. Always true: a download has no cancel
/// the page can observe. [origin] is ignored — it exists for the iPad share
/// sheet on the other side of the conditional import.
Future<bool> saveTextFile({
  required String filename,
  required String text,
  required String mimeType,
  Rect? origin,
}) async {
  final blob = web.Blob(
    <web.BlobPart>[text.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  // Attached before the click, per the comment this inherits from the Svelte
  // version: a detached anchor's click is ignored in some browsers.
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
