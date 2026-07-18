// The undo/redo stack discipline, extracted so it can be tested without the
// controller's engine and bridge dependencies. The bug this file exists for:
// undo APPENDED each undone batch while redo consumed from the FRONT, so two
// consecutive undos followed by a redo replayed the newest moves onto the
// oldest position — the move list went non-contiguous and the board
// teleported. The stack must stay in game order, oldest first, always.

import 'game_controller.dart' show MoveRecord;

class RedoStack {
  final List<MoveRecord> _stack = [];

  bool get isEmpty => _stack.isEmpty;
  bool get isNotEmpty => _stack.isNotEmpty;

  /// Any new move makes the stored future unreachable.
  void clear() => _stack.clear();

  /// Store one undo's worth, [newestFirst] as undo pops them. PREPENDS:
  /// these moves are older than whatever an earlier undo already stored.
  void pushUndone(List<MoveRecord> newestFirst) {
    _stack.insertAll(0, newestFirst.reversed);
  }

  /// Take one redo's worth from the front: the oldest stored player move,
  /// plus the bot replies sitting on it when [botEnabled].
  List<MoveRecord> takeBatch({
    required bool botEnabled,
    required String playerColor,
  }) {
    if (_stack.isEmpty) return const [];
    final batch = <MoveRecord>[_stack.removeAt(0)];
    if (botEnabled) {
      while (_stack.isNotEmpty && _stack.first.color != playerColor) {
        batch.add(_stack.removeAt(0));
      }
    }
    return batch;
  }
}
