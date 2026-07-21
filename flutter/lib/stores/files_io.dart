// The native half of [saveTextFile] — see files.dart for why the two branches
// below are the ones they are.
//
// macOS needs an entitlement for any of this to work. The app is sandboxed
// (com.apple.security.app-sandbox in both Runner entitlements), and under the
// sandbox a save or open panel puts up its window and then denies the write,
// unless com.apple.security.files.user-selected.read-write is granted. Added
// to DebugProfile.entitlements and Release.entitlements alongside this file:
// it is scoped to files the USER picked in a panel, which is the whole of
// what backup and restore do.

import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sp;

/// Write [text] out under [filename]. False means the user backed out, so the
/// caller can stay quiet rather than claim a save that never happened.
///
/// [origin] is the global rect of whatever was tapped: iPadOS and macOS anchor
/// the share sheet's popover to it, and iPadOS throws without one.
Future<bool> saveTextFile({
  required String filename,
  required String text,
  required String mimeType,
  Rect? origin,
}) async {
  if (Platform.isIOS || Platform.isAndroid) {
    // The sheet shares a URL, so the bytes have to exist somewhere first.
    // Temp rather than documents: once the user has chosen a destination this
    // copy is rubbish, and the OS reclaims the directory on its own schedule.
    final staged = File('${(await getTemporaryDirectory()).path}/$filename');
    await staged.writeAsString(text);
    final result = await sp.SharePlus.instance.share(sp.ShareParams(
      files: [sp.XFile(staged.path, mimeType: mimeType)],
      fileNameOverrides: [filename],
      sharePositionOrigin: origin,
    ));
    return result.status != sp.ShareResultStatus.dismissed;
  }

  final where = await fs.getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: [_typeGroup(filename, mimeType)],
  );
  if (where == null) return false;
  await File(where.path).writeAsString(text);
  return true;
}

/// The save panel needs the type to name and filter properly, and the
/// platforms read different fields of it — see readTextFile's note in
/// files.dart.
fs.XTypeGroup _typeGroup(String filename, String mimeType) {
  final ext = filename.split('.').last;
  return fs.XTypeGroup(
    label: ext.toUpperCase(),
    extensions: [ext],
    mimeTypes: [mimeType],
    uniformTypeIdentifiers: [ext == 'json' ? 'public.json' : 'public.data'],
  );
}
