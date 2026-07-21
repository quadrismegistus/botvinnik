// Moving a file between the app and wherever the user keeps their things,
// on the three targets this codebase ships to (#138).
//
// READING IN is the same everywhere: file_selector's `openFile`, which is
// flutter.dev's own package and the one API in it implemented on web, macOS
// and iOS alike — an `<input type="file">` in the browser, NSOpenPanel on the
// Mac, the document picker on the phone. Its web branch also completes with
// an empty list on the picker's `cancel` event (file_selector_web
// dom_helper.dart), so a dismissed dialog resolves rather than hanging, which
// is the one thing a hand-rolled input would have had to get right.
//
// WRITING OUT has no such common API, so [saveTextFile] is a conditional
// import over two branches. The reasoning, because the wrong choice here is
// invisible until someone is on the platform it fails on:
//
//   web — a Blob and an `<a download>`, written out in files_web.dart rather
//     than delegated. The obvious delegation is share_plus, whose web branch
//     is navigator.share() with a download fallback; but navigator.share is
//     absent in desktop Firefox and present in desktop Chrome, so which of
//     the two behaviours a user gets would depend on their browser. The web
//     build is where most of the users are and where the Svelte app set the
//     expectation of a plain download, so a plain download is what it does.
//     share_plus's fallback also hands the anchor a `data:` URI, which
//     browsers cap in length; a Blob URL does not, and the archive is the one
//     file here that grows without bound.
//
//   macOS and the other desktops — file_selector's native save panel. The
//     macOS share sheet has no save-to-disk service in it: it offers AirDrop,
//     Mail, Messages and Notes, so a user asking for a backup file would have
//     to mail it to themselves. The panel is also the only one of the three
//     that lets the user say WHERE, which is most of the point of a backup.
//
//   iOS — the share sheet, because iOS has no save panel; "Save to Files…" is
//     an entry inside it. The bytes are staged in the temp directory first
//     because the sheet takes a file URL, not a string.

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/widgets.dart';

export 'files_io.dart' if (dart.library.js_interop) 'files_web.dart';

/// The shape of [saveTextFile], so the widgets that call it can take it as a
/// parameter. A conditional export cannot be stubbed, and a save that reached
/// the real platform channel under `flutter test` would either hang or throw —
/// so the widget holds the function and the tests hand it a recorder, which is
/// also the only way to assert the FILENAME and the bytes a tap produced.
typedef TextFileSaver = Future<bool> Function({
  required String filename,
  required String text,
  required String mimeType,
  Rect? origin,
});

/// The shape of [readTextFile], for the same reason.
typedef TextFileReader = Future<String?> Function({
  required String extension,
  required String mimeType,
  required String uti,
});

/// The global rect of whatever [context] draws, for [TextFileSaver]'s
/// `origin` — the popover anchor iPadOS requires and macOS uses.
///
/// Typed-checked rather than cast. `findRenderObject` walks DOWN from an
/// element that has none of its own, and inside a ListView that walk can
/// arrive at the RenderSliverList instead of a box: the cast form threw
/// `'RenderSliverList' is not a subtype of 'RenderBox?'` the first time a
/// button in the archive list was tapped. An anchor is a nicety; losing the
/// export is not.
Rect? tapOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Ask the user for a file and return its text. Null means they cancelled.
///
/// All three filters are given because the platforms honour different ones:
/// macOS reads the UTI, the browser the extension and MIME type, iOS the UTI
/// alone — and file_selector_ios throws outright on a type group carrying no
/// UTI, so the field is not optional in practice.
Future<String?> readTextFile({
  required String extension,
  required String mimeType,
  required String uti,
}) async {
  final picked = await fs.openFile(acceptedTypeGroups: [
    fs.XTypeGroup(
      label: extension.toUpperCase(),
      extensions: [extension],
      mimeTypes: [mimeType],
      uniformTypeIdentifiers: [uti],
    ),
  ]);
  return picked == null ? null : await picked.readAsString();
}
