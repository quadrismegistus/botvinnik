// The new-game sheet. Assign each side to the human or any bot, then start —
// this is where opponent selection lives, because who plays which side is a
// game-start choice, not a persistent global setting.
//
//   You (W) vs bot (B)  → you play White
//   bot (W) vs bot (B)  → bot-vs-bot, you watch (and they can be different bots)
//   You (W) vs You (B)  → analysis, you move both sides
//
// It is also where a RATED game is started (#168), for the same reason: being
// on the record is a choice about one game, not a persistent setting. The
// switch is what turns blind on and the three overlays off — this sheet owns
// that, because they are the player's settings and GameController does not own
// them; the controller only records that the game was started rated.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/chess_clock.dart';
import '../stores/game_controller.dart';
import '../stores/settings_store.dart';
import 'bot_picker.dart';
import 'maia_status_line.dart';

void showNewGameSheet(BuildContext context) {
  final game = context.read<GameController>();
  final settings = context.read<SettingsStore>();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => _NewGameSheet(game: game, settings: settings),
  );
}

class _NewGameSheet extends StatefulWidget {
  final GameController game;
  final SettingsStore settings;
  const _NewGameSheet({required this.game, required this.settings});

  @override
  State<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends State<_NewGameSheet> {
  // null = the human plays this side; otherwise a bot persona id.
  late String? _white = widget.settings.whitePersonaId;
  late String? _black = widget.settings.blackPersonaId;

  // optional: start from a pasted FEN instead of the standard position
  final _fen = TextEditingController();
  String? _fenError;

  // Off by default, and deliberately not remembered between games: a rated
  // game is a thing the player decides to sit down for, and a sticky switch
  // would put them on the record without their having said so this time.
  bool _rated = false;

  /// Off by default and not remembered between games, like [_rated] — a
  /// session-scoped choice, not a standing preference (issue #167).
  bool _refuseBlunders = false;

  /// The clock a rated game runs on. Null is a rated game with no clock, which
  /// is still rated — the time control is a property of the game, not of what
  /// counts.
  TimeControl? _time = TimeControl.parse('10+0');

  /// A rated game needs exactly one human and one bot. Analysis has no result
  /// to rate and bot-vs-bot has no human in it — `playerElo` refuses both
  /// regardless, so offering the switch there would be a promise the archive
  /// does not keep.
  bool get _rateable => (_white == null) != (_black == null);

  @override
  void dispose() {
    _fen.dispose();
    super.dispose();
  }

  String _nameOf(String? id) {
    if (id == null) return 'You';
    // personaFor, not a roster scan: the stored id may predate a rename, and a
    // scan falls through to 'Bot' while the plate names the bot correctly.
    return widget.game.personaFor(id)?.name ?? 'Bot';
  }

  String get _summary {
    final w = _white == null, b = _black == null;
    if (w && b) return 'Analysis — you move both sides, every move still graded.';
    if (w) return 'You play White; ${_nameOf(_black)} plays Black.';
    if (b) return 'You play Black; ${_nameOf(_white)} plays White.';
    return '${_nameOf(_white)} (White) vs ${_nameOf(_black)} (Black) — you watch.';
  }

  Future<void> _pickBotFor(bool white) async {
    final current = white ? _white : _black;
    final id = await pickBotFamily(context,
        current: current ?? widget.settings.personaId);
    if (id == null || !mounted) return; // dismissed
    setState(() => white ? _white = id : _black = id);
    // Start the load NOW, on selection, so a phone is not still pulling 3.5MB
    // of Maia weights (plus the WASM compile) when the first move is due. A
    // no-op for anything that is not a Maia.
    widget.game.warmUpMaia(id);
  }

  Widget _chip(String text, bool selected, VoidCallback onTap,
        ) =>
      ChoiceChip(
        label: Text(text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                color: selected ? const Color(0xFF81B64C) : Colors.white54)),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: const Color(0xFF1f1e1b),
        selectedColor: const Color(0xFF3a3733),
        showCheckmark: false,
      );

  Widget _sideRow(String label, bool white) {
    final id = white ? _white : _black;
    final isYou = id == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                  width: 52,
                  child: Text(label,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white70))),
              const SizedBox(width: 6),
              _chip('You', isYou,
                  () => setState(() => white ? _white = null : _black = null)),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _chip(
                    isYou ? 'Pick a bot…' : _nameOf(id),
                    !isYou,
                    () => _pickBotFor(white),
                  ),
                ),
              ),
            ],
          ),
          _maiaStatusLine(id),
        ],
      ),
    );
  }

  /// A Maia opponent's load state, live, under its row — a download bar while
  /// its weights arrive and its runtime compiles, and (the reason this is here)
  /// the actual FAILURE when it cannot run, so an unexplained Stockfish stand-in
  /// on a phone becomes a stated reason. Empty for a non-Maia, or a Maia that is
  /// idle or already loaded and silent.
  Widget _maiaStatusLine(String? id) {
    final p = id == null ? null : widget.game.personaFor(id);
    final band = p?.family == 'maia' ? p?.maiaBand : null;
    if (band == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: widget.game.maiaStatus,
      builder: (context, _) =>
          MaiaStatusLine(state: widget.game.maiaStatus.of(band), name: p!.name),
    );
  }

  /// Material [Icon]s, not a check glyph in a [Text]: an uncovered codepoint
  /// is a font download from fonts.gstatic.com on web.
  /// Time controls, offered only once Rated is ticked — a clock on a casual
  /// game is a different feature and #169 does not ask for one.
  static final _presets = [
    TimeControl.parse('3+2'),
    TimeControl.parse('5+0'),
    TimeControl.parse('10+0'),
    TimeControl.parse('15+10'),
  ];

  Widget _timeRow() => Padding(
        padding: const EdgeInsets.fromLTRB(34, 2, 8, 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _presets)
              ChoiceChip(
                label: Text(t.notation, style: const TextStyle(fontSize: 12)),
                selected: _time?.notation == t.notation,
                onSelected: (_) => setState(() => _time = t),
                showCheckmark: false,
              ),
            ChoiceChip(
              label: const Text('no clock', style: TextStyle(fontSize: 12)),
              selected: _time == null,
              onSelected: (_) => setState(() => _time = null),
              showCheckmark: false,
            ),
          ],
        ),
      );

  Widget _ratedRow() => InkWell(
        onTap: () => setState(() => _rated = !_rated),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_rated ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: _rated ? const Color(0xFF81B64C) : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rated game',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _rated
                                ? const Color(0xFF81B64C)
                                : Colors.white70)),
                    const SizedBox(height: 1),
                    const Text(
                        'Played blind, with the hint overlays off. Only rated '
                        'games move your rating, and a takeback still takes '
                        'one off it.',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _refuseBlundersRow() => InkWell(
        onTap: () => setState(() => _refuseBlunders = !_refuseBlunders),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  _refuseBlunders
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color: _refuseBlunders
                      ? const Color(0xFF81B64C)
                      : Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Refuse blunders',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _refuseBlunders
                                ? const Color(0xFF81B64C)
                                : Colors.white70)),
                    const SizedBox(height: 1),
                    const Text(
                        'A move that loses too much is rejected instead of '
                        'played — retry the position. Still collected as a '
                        'practice puzzle, and takes the game off your '
                        'rating like a takeback would.',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _fenField() => TextField(
        controller: _fen,
        style: const TextStyle(fontSize: 12.5, color: Colors.white70),
        cursorColor: const Color(0xFF81B64C),
        onChanged: (_) {
          if (_fenError != null) setState(() => _fenError = null);
        },
        decoration: InputDecoration(
          labelText: 'Start position (FEN) — optional',
          labelStyle: const TextStyle(fontSize: 12.5, color: Colors.white38),
          hintText: 'paste a FEN to play or analyse from it',
          hintStyle: const TextStyle(fontSize: 11.5, color: Colors.white24),
          errorText: _fenError,
          isDense: true,
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF3a3733))),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF81B64C))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // lift above the soft keyboard when the FEN field has focus
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New game',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _sideRow('White', true),
            _sideRow('Black', false),
            const SizedBox(height: 8),
            Text(_summary,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            if (_rateable) _ratedRow(),
            if (_rateable && _rated) _timeRow(),
            // Same predicate as _rateable, not because this is about rating,
            // but because it needs exactly the same shape: one human side to
            // refuse blunders FOR, one bot to be playing against. Bot-vs-bot
            // has no human move to check; analysis has no bot game to be in.
            if (_rateable) _refuseBlundersRow(),
            const SizedBox(height: 10),
            _fenField(),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final fen = _fen.text.trim();
                if (fen.isNotEmpty && !GameController.isPlayableFen(fen)) {
                  setState(() => _fenError = 'Not a valid FEN');
                  return;
                }
                // `_rateable` again, not just `_rated`/`_refuseBlunders`: the
                // switches are hidden when neither side is a bot, but a
                // player who ticks one and then changes a side leaves it
                // ticked behind the fold.
                final rated = _rated && _rateable;
                final refuseBlunders = _refuseBlunders && _rateable;
                if (rated) {
                  // The mode, applied to the settings the board actually
                  // reads. Persistent on purpose — these are ordinary
                  // switches the player can turn back on, and restoring them
                  // at game over would flip the board mid-recap. What stops
                  // that from quietly rating an assisted game is that
                  // GameController samples `botHintsUsed` at every human
                  // move, so turning one back on during the game excludes it.
                  widget.settings.blind = true;
                  widget.settings.showArrows = false;
                  widget.settings.showThreats = false;
                  widget.settings.showControl = false;
                }
                // Before newGame: setPlayers can itself restart the game (the
                // controller listens and calls newGame() on an opponent
                // change), and that restart is unrated. The explicit call has
                // to be the last one.
                widget.settings.setPlayers(white: _white, black: _black);
                widget.game
                    .newGame(
                        fromFen: fen.isEmpty ? null : fen,
                        rated: rated,
                        refuseBlunders: refuseBlunders,
                        timeControl: rated ? _time : null);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF81B64C),
                foregroundColor: const Color(0xFF161512),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Start',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
