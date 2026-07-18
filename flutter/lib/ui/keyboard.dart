// Keyboard control for the desktop and web builds.
//
// Everything here is view-only: browsing history and flipping the board never
// touch the game, so a stray keypress can never cost you a move. The one key
// that acts, space, starts a preview — which is also non-destructive and
// stops on a second press.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stores/game_controller.dart';

/// What a key press means. Kept separate from the widget so the mapping can
/// be tested without standing up a GameController.
enum BoardKeyAction { back, forward, start, live, flip, preview, undo, redo }

/// The key, or null if this event is not ours. Repeats count, so holding an
/// arrow scrubs.
///
/// Undo and redo are the only bindings that take a modifier. ⌘Z / ⇧⌘Z is the
/// macOS standard; Ctrl-Y is the Windows one and is accepted there too, but
/// deliberately not on a Mac, where ⌘Y means something else in most apps.
BoardKeyAction? boardActionFor(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keys = HardwareKeyboard.instance;
  final command = keys.isMetaPressed || keys.isControlPressed;

  if (command) {
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      return keys.isShiftPressed ? BoardKeyAction.redo : BoardKeyAction.undo;
    }
    // Windows/Linux redo; on macOS ⌘Y is not this
    if (event.logicalKey == LogicalKeyboardKey.keyY &&
        keys.isControlPressed &&
        !keys.isMetaPressed) {
      return BoardKeyAction.redo;
    }
    return null; // every other combination belongs to the OS or the browser
  }
  if (keys.isAltPressed) return null;

  return switch (event.logicalKey) {
    LogicalKeyboardKey.arrowLeft => BoardKeyAction.back,
    LogicalKeyboardKey.arrowRight => BoardKeyAction.forward,
    LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.home =>
      BoardKeyAction.start,
    LogicalKeyboardKey.arrowDown ||
    LogicalKeyboardKey.end ||
    LogicalKeyboardKey.escape =>
      BoardKeyAction.live,
    LogicalKeyboardKey.keyF => BoardKeyAction.flip,
    LogicalKeyboardKey.space => BoardKeyAction.preview,
    _ => null,
  };
}

/// Wraps the app in a focus scope that turns key presses into navigation.
///
/// Uses a plain [Focus] rather than [Shortcuts]/[Actions] because these are
/// global, single-key bindings with no widget wanting to override them, and
/// a bare key handler is far less machinery for that.
class KeyboardControls extends StatelessWidget {
  final GameController game;
  final Widget child;
  const KeyboardControls({super.key, required this.game, required this.child});

  /// What the keys do, for the help sheet — one list, so the sheet cannot
  /// drift from the bindings.
  /// [mac] switches the modifier glyphs; the bindings themselves are the same
  /// apart from Ctrl-Y, which is a Windows convention.
  static List<(String, String)> bindingsFor({required bool mac}) => [
        ('←  →', 'step back and forward through the game'),
        ('↑  ↓', 'jump to the start, or back to the live position'),
        ('space', 'play or stop a preview of the best line'),
        ('f', 'flip the board'),
        ('esc', 'stop previewing and return to the live position'),
        (mac ? '⌘Z' : 'Ctrl+Z', 'undo'),
        (mac ? '⇧⌘Z' : 'Ctrl+Shift+Z / Ctrl+Y', 'redo'),
      ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final action = boardActionFor(event);
    if (action == null) return KeyEventResult.ignored;
    switch (action) {
      case BoardKeyAction.back:
        game.browseBy(-1);
      case BoardKeyAction.forward:
        game.browseBy(1);
      case BoardKeyAction.start:
        game.browseTo(0);
      case BoardKeyAction.live:
        game.browseLive();
      case BoardKeyAction.flip:
        game.toggleFlip();
      case BoardKeyAction.preview:
        _togglePreview();
      case BoardKeyAction.undo:
        if (game.canUndo) game.undo();
      case BoardKeyAction.redo:
        if (game.canRedo) game.redo();
    }
    return KeyEventResult.handled;
  }

  void _togglePreview() {
    if (game.previewing) {
      game.stopPreview();
      return;
    }
    final lines = game.visibleLines;
    if (lines.isEmpty) return;
    game.startPreview(game.position.fen, lines.first.pv.toList());
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: _onKey, child: child);
}

/// The bindings, shown from the app bar. Cheap to add and it stops the
/// shortcuts being folklore.
void showKeyboardHelp(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title: const Text('Keyboard', style: TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (keys, what) in KeyboardControls.bindingsFor(
              mac: defaultTargetPlatform == TargetPlatform.macOS))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(keys,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF81B64C))),
                  ),
                  Expanded(
                    child: Text(what,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.white70)),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}
