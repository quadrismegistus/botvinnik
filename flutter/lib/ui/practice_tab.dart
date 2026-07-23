// The Practice tab: one puzzle at a time — play the strong move on a live
// board. The attempt lands on the board immediately (optimistic) while the
// depth-14 check runs; hints escalate (text → origin square → reveal);
// pass/fail records into the Leitner schedule.
//
// Plus the collection browser (#137/#125/#49): the whole queue as a list, so
// the schedule you are being asked to trust is visible, and so you can throw
// items out of it. That second job is the load-bearing one. A blunder you took
// back stays collected (decided on #137 — you played it, and a takeback is a
// courtesy for the game, not a claim about your understanding), which makes
// delete the only way anything ever leaves. So the list is built for judgement
// over your own queue, not for inspection: every collected item is reachable
// here, including the ones the threshold will never serve.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/practice_controller.dart';
import '../stores/settings_store.dart';
import 'board_theme.dart';
import 'layout.dart';

class PracticeTab extends StatefulWidget {
  const PracticeTab({super.key});

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  ChessboardController? _controller;
  String _boardSig = '';

  /// Showing the collection instead of the drill. Pure view state: the served
  /// puzzle is untouched underneath, so closing the list puts you back on the
  /// board you left, mid-attempt if that is where you were.
  bool _browsing = false;

  /// The game-session serial this tab has reacted to. When the controller bumps
  /// it (a new "practise this game's mistakes" session), we drop out of the
  /// browser so the drill is what shows — the tab is a persistent IndexedStack
  /// child, so `_browsing` left true from a previous visit would otherwise land
  /// the session on the collection list (#197 nav).
  int _seenGameSerial = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// The shown position: puzzle fen, plus the attempt (or the optimistic
  /// pending move while the check runs).
  Position _position(Map<String, dynamic> item, String? appliedUci) {
    Position pos = Chess.fromSetup(Setup.parseFen(item['fen'] as String));
    if (appliedUci != null) {
      final m = NormalMove.fromUci(appliedUci);
      if (pos.isLegal(m)) pos = pos.playUnchecked(m);
    }
    return pos;
  }

  GameData _gameData(Position pos, String? appliedUci, {bool locked = false}) =>
      GameData(
        fen: pos.fen,
        lastMove: appliedUci == null ? null : NormalMove.fromUci(appliedUci),
        // [locked] is the punishment preview (#215): the board is narrating a
        // line, so no side is draggable until it stops.
        playerSide: locked || appliedUci != null
            ? PlayerSide.none
            : (pos.turn == Side.white ? PlayerSide.white : PlayerSide.black),
        validMoves: makeLegalMoves(pos),
        sideToMove: pos.turn,
        kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      );

  @override
  Widget build(BuildContext context) {
    final practice = context.watch<PracticeController>();
    final item = practice.current;

    // A new game session drops us back to the drill, wherever the tab was left.
    // Set directly (not via setState): we are already building and use it below.
    if (practice.gameSessionSerial != _seenGameSerial) {
      _seenGameSerial = practice.gameSessionSerial;
      _browsing = false;
    }

    // Nothing collected at all is the only state with nothing to browse.
    if (practice.items.isEmpty) return _empty(practice);
    // Nothing SERVABLE is not that state, and used to be told it was: items
    // below the collect threshold (everything ≥5% is collected, the setting
    // filters at serve time) left the tab saying "No puzzles yet" over a
    // collection that had plenty. The browser is the honest idle view — it
    // shows them, says why they are not being served, and lets you delete them.
    if (_browsing || item == null) return _collection(context, practice);
    return _puzzle(context, practice, item);
  }

  /// Nothing COLLECTED — the one state with no list to show. Anything else
  /// goes to the browser, which explains itself.
  ///
  /// The filtered branch survives because deleting the last item while a motif
  /// filter is on lands here with that filter still set, and the picker is
  /// drawn in the drill's action row and the browser's header, neither of
  /// which is on screen. Without the way out the tab would blame the
  /// collection for the filter's doing, and stay that way for the session.
  Widget _empty(PracticeController practice) {
    final motif = practice.motifFilter;
    if (motif == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No puzzles yet.\nMoves that lose ≥15% win chance are '
            'collected here automatically as you play.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, height: 1.4),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing to practise tagged $motif.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, height: 1.4),
            ),
            TextButton(
              onPressed: () => practice.setMotifFilter(null),
              child: const Text('Show all puzzles',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- the collection browser ----

  /// Everything collected, due first, narrowed by the active motif filter.
  ///
  /// Deliberately NOT `servable`: the sub-threshold items are exactly the ones
  /// a player wants to throw out, and delete is the only exit there is. Hiding
  /// them would make the list a view of the queue rather than of the
  /// collection, and leave the junk permanently unreachable.
  List<Map<String, dynamic>> _rows(PracticeController practice) {
    final motif = practice.motifFilter;
    final rows = practice.items
        .where((i) =>
            motif == null ||
            ((i['motifs'] as List?)?.cast<String>() ?? const [])
                .contains(motif))
        .toList();
    rows.sort((a, b) => _dueAt(a).compareTo(_dueAt(b)));
    return rows;
  }

  DateTime _dueAt(Map<String, dynamic> item) =>
      DateTime.tryParse(item['dueAt'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  Widget _collection(BuildContext context, PracticeController practice) {
    final settings = context.watch<SettingsStore>();
    final rows = _rows(practice);
    return Column(
      children: [
        _collectionHeader(context, practice),
        if (practice.current == null) _idleBanner(practice),
        // ListView.builder rather than a Column in a scroll view: it builds
        // only the rows in view. Every row carries a board, and a collection
        // has no upper bound — the position thumbnails are the expensive part,
        // which is why chessground's StaticChessboard defers its piece images
        // under a Scrollable in the first place.
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _collectionRow(context, practice, rows[i], settings),
          ),
        ),
      ],
    );
  }

  Widget _collectionHeader(BuildContext context, PracticeController practice) {
    final total = practice.items.length;
    final servable = practice.servable.length;
    final summary = total == servable
        ? '$total position${total == 1 ? '' : 's'} · ${practice.due} due'
        : '$total collected · $servable in the queue · ${practice.due} due';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
      color: const Color(0xFF262421),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              _motifMenu(practice),
              // Only when there is a drill to go back to. With nothing
              // servable the list IS the tab, and a close button would put you
              // on the empty state you just came from.
              if (practice.current != null)
                IconButton(
                  // arrow_back, not close: Icons.close is the failed-attempt
                  // mark in the rows below, and one glyph meaning both "your
                  // last try was wrong" and "leave this screen" in the same
                  // view is a misread waiting to happen.
                  tooltip: 'Back to the puzzle',
                  icon: const Icon(Icons.arrow_back,
                      size: 20, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => setState(() => _browsing = false),
                ),
            ],
          ),
          _masteryBar(practice),
        ],
      ),
    );
  }

  /// mastered / learning / fresh as one bar. Three segments sized by count,
  /// with the numbers written out underneath — the bar carries the shape of
  /// the collection at a glance, the label carries the fact.
  Widget _masteryBar(PracticeController practice) {
    final m = practice.mastery;
    final mastered = m['mastered'] ?? 0;
    final learning = m['learning'] ?? 0;
    final fresh = m['fresh'] ?? 0;
    if (mastered + learning + fresh == 0) return const SizedBox.shrink();
    // An empty band is omitted rather than handed flex: 0. Measured: flex: 0
    // does not assert and draws nothing either — this is for the reader, so
    // the widget tree says what the collection contains.
    Widget seg(int n, Color c) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: ColoredBox(color: c));
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                seg(mastered, const Color(0xFF81B64C)),
                seg(learning, const Color(0xFFF0C15C)),
                seg(fresh, const Color(0xFF3E3C38)),
              ]),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$mastered mastered · $learning learning · $fresh new',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Why the list is all you are getting: something is collected, but nothing
  /// can be served. Names the cause, and offers the way out of the one cause
  /// the player can undo in a tap.
  Widget _idleBanner(PracticeController practice) {
    final motif = practice.motifFilter;
    // A finished game session (#197): every scoped mistake has been drilled.
    // Say so, and offer the one way back to the full queue.
    final gameDone = practice.gameDoneNote;
    if (gameDone != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        color: const Color(0xFF1f1e1b),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: 15, color: Color(0xFF81B64C)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(gameDone,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            TextButton(
              onPressed: practice.exitGameSession,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32)),
              child: const Text('Practise all',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
      );
    }
    // A continued line that ran to its end (#143) leaves no puzzle on the board;
    // say why, then fall back to Next for the scheduler's next draw.
    final lineNote = practice.lineNote;
    if (lineNote != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: const Color(0xFF1f1e1b),
        child: Row(
          children: [
            Expanded(
              child: Text(lineNote,
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            TextButton(
              onPressed: practice.nextPuzzle,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32)),
              child: const Text('Next puzzle',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: const Color(0xFF1f1e1b),
      child: motif != null
          ? Row(
              children: [
                Expanded(
                  child: Text('Nothing to practise tagged $motif.',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => practice.setMotifFilter(null),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32)),
                  child: const Text('Show all puzzles',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ],
            )
          : Text(
              'Nothing to practise — everything collected is below the '
              '${practice.threshold}% drop you set for the queue. Lower it in '
              'Settings, or tap a position below to drill it anyway.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
    );
  }

  static const _kDifficultyColors = {
    'easy': Color(0xFF81B64C),
    'medium': Color(0xFFD09A3C),
    'hard': Color(0xFFCA3431),
  };

  Widget _difficultyChip(String difficulty) {
    final color = _kDifficultyColors[difficulty] ?? Colors.white38;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(difficulty,
          style: TextStyle(color: color, fontSize: 10, height: 1.4)),
    );
  }

  /// When this item comes up, in the terms a queue is actually read in.
  ///
  /// Signed both ways: a date makes you do the arithmetic, and "overdue by 3
  /// days" is the fact that decides whether the schedule is working. Under an
  /// hour either side is "due now" — box 0 is a ten-minute interval, so a
  /// minute-accurate countdown there is noise.
  String _dueLabel(DateTime due) {
    final mins = due.difference(DateTime.now()).inMinutes;
    if (mins.abs() < 60) return 'due now';
    final span = _span(mins.abs());
    return mins < 0 ? 'overdue by $span' : 'due in $span';
  }

  /// Rounded, and the unit chosen from the ROUNDED hours: truncating turns six
  /// hours into "5 hours" the instant the clock has moved a second past the
  /// timestamp, and switching on the raw minutes leaves a "48 hours" band just
  /// under two days.
  String _span(int minutes) {
    final hours = (minutes / 60).round();
    return hours < 48
        ? _plural(hours, 'hour')
        : _plural((minutes / 1440).round(), 'day');
  }

  String _plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

  /// The attempt record (#49), drawn as what is actually stored.
  ///
  /// A sparkline was the original suggestion, and it cannot be honest: the
  /// brain keeps `attempts`, `correct` and a `lastResult` that `recordResult`
  /// OVERWRITES (brain/practice.ts) — there is no per-attempt trail, so any
  /// sequence of pips would be inventing an order the app does not know. What
  /// is known is the ratio and the most recent verdict, so that is what this
  /// draws: a proportion bar plus the last result. A real trail is a schema
  /// change, not a rendering.
  Widget _attemptRecord(int attempts, int correct, String? last) {
    if (attempts == 0) return const SizedBox.shrink();
    final wrong = attempts - correct;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 26,
            height: 4,
            child: Row(children: [
              if (correct > 0)
                Expanded(
                    flex: correct,
                    child: const ColoredBox(color: Color(0xFF81B64C))),
              if (wrong > 0)
                Expanded(
                    flex: wrong,
                    child: const ColoredBox(color: Color(0xFFCA3431))),
            ]),
          ),
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              last == 'pass' ? Icons.check : Icons.close,
              size: 12,
              color: last == 'pass'
                  ? const Color(0xFF81B64C)
                  : const Color(0xFFCA3431),
            ),
          ),
      ],
    );
  }

  Widget _collectionRow(BuildContext context, PracticeController practice,
      Map<String, dynamic> item, SettingsStore settings) {
    final id = item['id'] as String;
    final fen = item['fen'] as String;
    final whiteToMove = fen.split(' ')[1] == 'w';
    final drop = (item['drop'] as num?)?.toDouble() ?? 0;
    final attempts = (item['attempts'] as num?)?.toInt() ?? 0;
    final correct = (item['correct'] as num?)?.toInt() ?? 0;
    final motifs = (item['motifs'] as List?)?.cast<String>() ?? const [];
    final queued = drop >= practice.threshold;

    final detail = StringBuffer('played ${item['playedSan']}')
      ..write(' · best ${item['bestSan']}');
    if (motifs.isNotEmpty) detail.write(' · ${motifs.join(', ')}');

    final status = queued
        ? _dueLabel(_dueAt(item))
        : 'not queued — under ${practice.threshold}%';
    final tried = attempts == 0
        ? 'never tried'
        : '$correct of $attempts correct';

    return InkWell(
      // Straight into the drill for the one you picked, closing the list —
      // browsing is how you find the position you actually wanted to work on.
      onTap: () {
        practice.serveItem(id);
        setState(() => _browsing = false);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StaticChessboard(
              size: 56,
              fen: fen,
              orientation: whiteToMove ? Side.white : Side.black,
              settings: staticBoardSettingsFor(settings),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${whiteToMove ? 'White' : 'Black'} to move — '
                          'lost ${drop.round()}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      _difficultyChip(practice.difficultyOf(item)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$status · $tried',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: queued
                                  ? Colors.white38
                                  : const Color(0xFF7A6A4A),
                              fontSize: 11),
                        ),
                      ),
                      _attemptRecord(
                          attempts, correct, item['lastResult'] as String?),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete this puzzle',
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.white38),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => _confirmDelete(context, practice, id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _puzzle(BuildContext context, PracticeController practice,
      Map<String, dynamic> item) {
    // While "watch what it costs" plays, the board shows the punishment line
    // (#215) instead of the attempt, and locks input until it stops.
    final previewFen =
        practice.refutePreviewing ? practice.refutePreviewFen : null;
    final appliedUci =
        previewFen != null ? null : (practice.attempt?.uci ?? practice.pendingUci);
    final pos = previewFen != null
        ? Chess.fromSetup(Setup.parseFen(previewFen))
        : _position(item, appliedUci);
    final sideToMove =
        (item['fen'] as String).split(' ')[1] == 'w' ? 'White' : 'Black';

    final sig = previewFen != null
        ? 'preview:$previewFen'
        : '${item['id']}-${appliedUci ?? ''}';
    _controller ??=
        ChessboardController(game: _gameData(pos, appliedUci, locked: previewFen != null));
    if (_boardSig != sig) {
      _boardSig = sig;
      _controller!
          .updatePosition(_gameData(pos, appliedUci, locked: previewFen != null));
    }

    final settings = context.watch<SettingsStore>();

    // The board is square, so on a desktop window full width means full-width
    // TALL — which overflowed the viewport by ~900px and pushed the action row
    // off the bottom. Same treatment as PlayTab: cap it when stacked, and put
    // it beside the furniture once there is room.
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget board(double size) => Chessboard(
              controller: _controller!,
              size: size,
              orientation: (item['fen'] as String).split(' ')[1] == 'w'
                  ? Side.white
                  : Side.black,
              onMove: (move, {viaDragAndDrop}) {
                // Locked while the engine plays a line continuation (#143) or
                // the punishment preview runs (#215), the same way an in-flight
                // check locks it.
                if (practice.continuing || practice.refutePreviewing) return;
                if (move is! NormalMove || !pos.isLegal(move)) return;
                final (_, san) = pos.makeSan(move);
                final after = pos.playUnchecked(move);
                practice.checkAttempt(move.uci, san, after.fen);
              },
              // The preview narrates the line on the board itself; the attempt's
              // hint/refutation arrows would be drawn on the wrong position.
              shapes: previewFen != null ? const <Shape>{} : _shapes(item, practice),
              settings: boardSettingsFor(settings),
            );

        if (constraints.maxWidth < kWideBreakpoint) {
          final size = stackedBoardSize(
              constraints.maxWidth, constraints.maxHeight, kPracticeChrome);
          return Column(
            children: [
              _gameScopeBanner(practice),
              Center(child: board(size)),
              _promptStrip(item, practice, sideToMove),
              _actionRow(context, practice),
            ],
          );
        }
        final size = wideBoardSize(
            constraints.maxWidth, constraints.maxHeight, settings.split);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            board(size),
            // Hint/Retry/Next belong directly under the prompt they answer.
            // A Spacer here pushed them to the far bottom-right of the pane,
            // half a screen from the sentence they respond to.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _gameScopeBanner(practice),
                  _promptStrip(item, practice, sideToMove),
                  _actionRow(context, practice),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// A running "practise this game's mistakes" session (#197) narrows the queue
  /// to one game's positions, and nothing else on the tab says so — the badge,
  /// the collection browser and the due count all still speak for the whole
  /// collection. This names the scope and offers the one way back to the full
  /// queue, the same shape as the motif filter's "Show all puzzles".
  Widget _gameScopeBanner(PracticeController practice) {
    if (!practice.inGameSession) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFF1f1e1b),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const Icon(Icons.history, size: 15, color: Color(0xFF81B64C)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text("Practising this game's mistakes",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          TextButton(
            onPressed: practice.exitGameSession,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            child: const Text('Practise all',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Set<Shape> _shapes(Map<String, dynamic> item, PracticeController practice) {
    final best = NormalMove.fromUci(item['bestUci'] as String);
    final shapes = <Shape>{};
    if (practice.revealBest) {
      shapes.add(Arrow(
          color: const Color(0xB33BAB4A), orig: best.from, dest: best.to));
    } else if (practice.hintTier >= 2) {
      shapes.add(Circle(color: const Color(0xB3D0B755), orig: best.from));
    }
    final refutation = practice.attempt?.refutationUci;
    if (refutation != null) {
      final r = NormalMove.fromUci(refutation);
      shapes.add(
          Arrow(color: const Color(0xB3CA3431), orig: r.from, dest: r.to));
    }
    return shapes;
  }

  /// Icon plus text. Replaces the ✓ / ✗ these lines used to start with: those
  /// glyphs are in no bundled font, so drawing them made Flutter web fetch
  /// Noto Sans Symbols from fonts.gstatic.com — on every graded attempt, and
  /// unservable offline. The icon font is already here and tree-shaken.
  Widget _verdict(IconData icon, Color color, String text, {TextStyle? style}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5, right: 6),
            child: Icon(icon, color: color, size: 15),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      );

  Widget _promptStrip(Map<String, dynamic> item, PracticeController practice,
      String sideToMove) {
    final attempt = practice.attempt;
    Widget content;
    if (practice.continuing) {
      content = const Text('Playing the reply…',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    } else if (practice.checking) {
      content = const Text('Checking…',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    } else if (attempt == null && practice.lineDepth > 0) {
      // A continued position (#143): a fresh target one move deeper, not the
      // collected blunder — so no "you lost X% here" subtitle.
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$sideToMove to move — continue the line',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const Text('find the strong move here too',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
    } else if (attempt == null) {
      final drop = (item['drop'] as num).toDouble();
      final motifs = (item['motifs'] as List?)?.cast<String>() ?? const [];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$sideToMove to move — find a strong move',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Text(
            'you lost ${drop.round()}% here with ${item['playedSan']}'
            '${practice.hintTier >= 1 && motifs.isNotEmpty ? ' · think: ${motifs.join(', ')}' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );
    } else if (attempt.pass) {
      content = _verdict(
        Icons.check_circle_outline,
        const Color(0xFF81B64C),
        '${attempt.san}'
        '${attempt.drop <= 0 ? ' — as strong as the best move' : ' — costs ${attempt.drop.round()}%, good enough'}'
        '${practice.revealBest && attempt.uci != item['bestUci'] ? ' · best was ${item['bestSan']}' : ''}',
        style: const TextStyle(
            color: Color(0xFF81B64C), fontWeight: FontWeight.w600),
      );
    } else {
      // The verdict, plus WHY it's bad when the refutation says it plainly
      // (#215): a mate or the piece it wins, on its own line under the drop.
      final punishment = attempt.punishment;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _verdict(
            Icons.cancel_outlined,
            const Color(0xFFCA3431),
            '${attempt.san} — drops ${attempt.drop.round()}% '
            '${practice.revealBest ? '· best was ${item['bestSan']}' : ''}',
            style: const TextStyle(
                color: Color(0xFFCA3431), fontWeight: FontWeight.w600),
          ),
          if (punishment != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 21),
              child: Text(punishment,
                  style: const TextStyle(
                      color: Color(0xFFE0908E), fontSize: 13, height: 1.3)),
            ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF262421),
      child: content,
    );
  }

  /// The motif picker: built from the motifs the player's own items actually
  /// carry, so every option serves something. Hidden entirely when there are
  /// none — an untagged collection gets a menu with one item saying "all",
  /// which is furniture pretending to be a feature.
  Widget _motifMenu(PracticeController practice) {
    final counts = practice.motifCounts;
    final active = practice.motifFilter;
    if (counts.isEmpty && active == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Practise one motif',
      icon: Icon(Icons.filter_list,
          size: 20,
          color: active == null ? Colors.white70 : const Color(0xFF81B64C)),
      padding: EdgeInsets.zero,
      // '' is the sentinel for "all", NOT null: PopupMenuButton cannot tell a
      // null-valued selection from a dismissal — it calls onCanceled and
      // returns before onSelected (popup_menu.dart, `if (newValue == null)`).
      // With value: null the "All puzzles" row was inert, and since the filter
      // lives on the controller and survives re-entering the tab, a filter with
      // items left in it could not be cleared for the rest of the session.
      onSelected: (v) => practice.setMotifFilter(v.isEmpty ? null : v),
      itemBuilder: (context) => [
        CheckedPopupMenuItem<String>(
          value: '',
          checked: active == null,
          child: Text('All puzzles (${practice.servable.length})'),
        ),
        for (final e in counts.entries)
          CheckedPopupMenuItem<String>(
            value: e.key,
            checked: active == e.key,
            child: Text('${e.key} (${e.value})'),
          ),
      ],
    );
  }

  /// Confirmed, not undoable.
  ///
  /// `remove` deletes the item and persists; nothing puts it back. The only
  /// route to the same puzzle is blundering in that exact position again, and
  /// that arrives through `addItem` as a fresh item — box 0, attempts cleared
  /// — so an "Undo" here would restore a different thing wearing the same
  /// name. A one-tap SnackBar undo that lies is worse than a dialog. The
  /// button also sits beside Next, which is the one people hit fast.
  Future<void> _confirmDelete(BuildContext context,
      PracticeController practice, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this puzzle?'),
        content: const Text(
          'It leaves your practice queue for good — this is the only way out, '
          'since a position you blundered stays collected even if you took '
          'the move back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFCA3431))),
          ),
        ],
      ),
    );
    if (ok == true) await practice.remove(id);
  }

  Widget _actionRow(BuildContext context, PracticeController practice) {
    final attempt = practice.attempt;
    final current = practice.current;
    final bestUci = current?['bestUci'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          // The word buttons scroll instead of competing for the width.
          // Measured, not assumed: with a plain Row and a Spacer, a failed
          // attempt (Retry + Show best) plus the picker, the delete and Next
          // overflows by 34px at 320 logical pixels under the real Roboto. It
          // fits at 375 — but a RenderFlex overflow is a runtime error that
          // neither the analyzer nor a green suite says anything about, and
          // the row only grows.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (attempt == null && practice.hintTier < 3)
                  TextButton(
                    onPressed: practice.hint,
                    child: Text(
                      practice.hintTier == 0
                          ? 'Hint'
                          : practice.hintTier == 1
                              ? 'Another hint'
                              : 'Show best',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                // pass or fail: retry to hunt the best, reveal if you haven't
                // found it (a "good enough" pass still has a better move to see)
                if (attempt != null)
                  TextButton(
                    onPressed: practice.retry,
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.white70)),
                  ),
                if (attempt != null &&
                    !practice.revealBest &&
                    attempt.uci != bestUci)
                  TextButton(
                    onPressed: practice.reveal,
                    child: const Text('Show best',
                        style: TextStyle(color: Colors.white70)),
                  ),
                // Watch the mistake get punished (#215): play the opponent's
                // refutation on the board. Off a FAIL with a line to show;
                // never reveals the best MOVE, only what the wrong one costs.
                if (attempt != null &&
                    !attempt.pass &&
                    attempt.refutationPv.isNotEmpty)
                  TextButton(
                    onPressed: practice.refutePreviewing
                        ? practice.stopRefutationPreview
                        : practice.startRefutationPreview,
                    child: Text(
                        practice.refutePreviewing
                            ? 'Stop'
                            : 'Watch what it costs',
                        style: const TextStyle(color: Color(0xFFE0908E))),
                  ),
                // Keep playing forward from a puzzle you passed (#143): the
                // engine answers and the position one move later becomes the
                // next target. Off a PASS only, and never mid-continuation.
                if (attempt != null && attempt.pass && !practice.continuing)
                  TextButton(
                    onPressed: practice.continueLine,
                    child: const Text('Continue the line',
                        style: TextStyle(color: Color(0xFF81B64C))),
                  ),
              ]),
            ),
          ),
          IconButton(
            tooltip: 'Browse your collection',
            icon: const Icon(Icons.format_list_bulleted,
                size: 20, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => setState(() => _browsing = true),
          ),
          _motifMenu(practice),
          if (current != null)
            IconButton(
              tooltip: 'Delete this puzzle',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.white70),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () =>
                  _confirmDelete(context, practice, current['id'] as String),
            ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: practice.nextPuzzle,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF81B64C),
              foregroundColor: const Color(0xFF161512),
            ),
            child: Text(attempt == null ? 'Skip' : 'Next',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
