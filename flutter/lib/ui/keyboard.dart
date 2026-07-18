// Keyboard control for the desktop and web builds.
//
// Everything here is view-only: browsing history and flipping the board never
// touch the game, so a stray keypress can never cost you a move. The one key
// that acts, space, starts a preview — which is also non-destructive and
// stops on a second press.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stores/game_controller.dart';

/// What a key press means. Kept separate from the widget so the mapping can
/// be tested without standing up a GameController.
enum BoardKeyAction { back, forward, start, live, flip, preview }

/// The key, or null if this event is not ours. Repeats count, so holding an
/// arrow scrubs; modifiers do not, so Cmd-R still reloads.
BoardKeyAction? boardActionFor(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  if (HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isAltPressed) {
    return null;
  }
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
  static const List<(String, String)> bindings = [
    ('←  →', 'step back and forward through the game'),
    ('↑  ↓', 'jump to the start, or back to the live position'),
    ('space', 'play or stop a preview of the best line'),
    ('f', 'flip the board'),
    ('esc', 'stop previewing and return to the live position'),
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
          for (final (keys, what) in KeyboardControls.bindings)
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
