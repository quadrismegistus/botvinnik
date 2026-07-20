// Keyboard control for the desktop and web builds.
//
// One focus node sits above the whole shell (it has to, to reliably hold
// focus), so the handler is tab-AWARE rather than tab-GATED: it dispatches to
// the on-screen tab's action map — Play, Practice, or Review — and returns
// ignored on Settings and for any key a tab does not claim, which lets those
// keys fall through to scrolling. Nothing here can cost you a move you cannot
// see: undo/redo only fire on the Play tab, where the board is.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stores/game_controller.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';
import '../stores/settings_store.dart';

/// What a key press means on the Play tab. Kept separate from the widget so the
/// mapping can be tested without standing up a GameController.
enum BoardKeyAction { back, forward, start, live, flip, preview, undo, redo }

// holding an arrow scrubs; holding f or space must not strobe
const _repeatable = {
  BoardKeyAction.back,
  BoardKeyAction.forward,
  BoardKeyAction.start,
  BoardKeyAction.live,
};

/// The Play key, or null if this event is not ours. Repeats count only for the
/// browse keys, so holding an arrow scrubs but holding f doesn't spin the
/// board and holding space doesn't toggle the preview thirty times a second.
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

  final action = switch (event.logicalKey) {
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
  if (event is KeyRepeatEvent && !_repeatable.contains(action)) return null;
  return action;
}

/// Wraps the app in a focus scope that turns key presses into per-tab actions.
///
/// Uses a plain [Focus] rather than [Shortcuts]/[Actions] because these are
/// global, single-key bindings with no widget wanting to override them, and
/// a bare key handler is far less machinery for that.
class KeyboardControls extends StatelessWidget {
  final GameController game;
  final ReviewController review;
  final PracticeController practice;
  final SettingsStore settings;

  /// The tab on screen (0 Play, 1 Practice, 2 Review, 3 Settings). The focus
  /// node is above the shell, so the handler needs to know which tab's map to
  /// use — and to stay out of Settings and off any key a tab doesn't claim.
  final int Function() currentTab;

  final Widget child;

  const KeyboardControls({
    super.key,
    required this.game,
    required this.review,
    required this.practice,
    required this.settings,
    required this.currentTab,
    required this.child,
  });

  static const _play = 0, _practice = 1, _review = 2;

  /// What the keys do, grouped by tab, for the help sheet — one source, so the
  /// sheet cannot drift from the bindings. Spelled out rather than ← → ↑ ↓ ⌘ ⇧:
  /// none of those glyphs exist in Roboto, so drawing them made Flutter web
  /// fetch Noto Sans Symbols from fonts.gstatic.com — a third-party request the
  /// offline build cannot serve. [mac] switches the modifier words.
  static List<(String, List<(String, String)>)> bindingsByTab(
          {required bool mac}) =>
      [
        (
          'Play',
          [
            ('Left / Right', 'step back and forward through the game'),
            ('Up / Down', 'jump to the start, or back to the live position'),
            ('space', 'play or stop a preview of the best line'),
            ('f', 'flip the board'),
            ('h', 'blind mode — hide the engine help'),
            ('esc', 'stop previewing and return to the live position'),
            (mac ? 'Cmd Z' : 'Ctrl+Z', 'undo'),
            (mac ? 'Shift Cmd Z' : 'Ctrl+Shift+Z / Ctrl+Y', 'redo'),
          ],
        ),
        (
          'Practice',
          [
            ('? or /', 'hint — escalates: think → square → best'),
            ('b', 'reveal the best move'),
            ('r', 'retry the puzzle'),
            ('n', 'next puzzle'),
          ],
        ),
        (
          'Review',
          [
            ('Left / Right', 'step back and forward through the moves'),
            ('Up / Down', 'jump to the first or last move'),
          ],
        ),
      ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    switch (currentTab()) {
      case _play:
        return _playKey(event);
      case _practice:
        return _practiceKey(event);
      case _review:
        return _reviewKey(event);
      default:
        return KeyEventResult.ignored; // Settings: the page owns its keys
    }
  }

  bool _noCommand(HardwareKeyboard k) =>
      !k.isMetaPressed && !k.isControlPressed && !k.isAltPressed;

  KeyEventResult _playKey(KeyEvent event) {
    // h toggles blind mode ("hide"); a plain press, not a repeat, so holding
    // it doesn't strobe. b is deliberately left free for a future "show best".
    if (event is KeyDownEvent &&
        _noCommand(HardwareKeyboard.instance) &&
        event.logicalKey == LogicalKeyboardKey.keyH) {
      settings.blind = !settings.blind;
      return KeyEventResult.handled;
    }
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

  KeyEventResult _reviewKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_noCommand(HardwareKeyboard.instance)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (review.canPrev) review.prev();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (review.canNext) review.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.home) {
      review.goto(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.end) {
      review.goto(review.moves.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // let other keys scroll the move table
  }

  KeyEventResult _practiceKey(KeyEvent event) {
    // state-changing keys, so no repeat: holding r must not re-serve endlessly
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_noCommand(HardwareKeyboard.instance)) return KeyEventResult.ignored;
    if (practice.current == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyR) {
      practice.retry();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      practice.nextPuzzle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      practice.reveal();
      return KeyEventResult.handled;
    }
    // ? is Shift+/ on a US layout (same physical key → slash); the character
    // check catches layouts where it is not
    if (key == LogicalKeyboardKey.slash || event.character == '?') {
      practice.hint();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title: const Text('Keyboard', style: TextStyle(fontSize: 15)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (tab, binds) in KeyboardControls.bindingsByTab(mac: mac)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 5),
                child: Text(tab.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.1,
                        color: Colors.white38,
                        fontWeight: FontWeight.w700)),
              ),
              for (final (keys, what) in binds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        // 'Shift Cmd Z' is ~67px at this size; the old ⇧⌘Z was
                        // 8. Too narrow and the rows silently wrap to two lines.
                        width: 84,
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
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}
