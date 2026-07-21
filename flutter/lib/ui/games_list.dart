// The Review tab: stored games, newest first — result, opponent, accuracy,
// blunder/mistake counts. Tap to review — which opens IN THIS TAB, replacing
// the list, so the shell and its bottom tabs stay on screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/backup.dart';
import '../stores/files.dart';
import '../stores/game_controller.dart';
import '../brain/lichess_import_api.dart';
import '../stores/pgn_import.dart';
import '../stores/review_controller.dart';
import 'lichess_import_dialog.dart';
import 'review_screen.dart';

/// A human win over a bot, and how it was won. [clean] draws the solid crown;
/// otherwise it is the outline and [detail] names the help.
typedef WinCrown = ({bool clean, String detail});

/// The crowns distinction, ported from the Svelte archive: a result alone
/// teaches you to farm easy wins, so the row says HOW the game was won.
///
/// Clean means all three: no takebacks, no engine stand-in, and the hint
/// overlays off. Anything else is a win with help, itemised — the honest
/// counterpart to the stand-in badge, which already admits when the opponent
/// was not the one on the card.
///
/// An ABSENT `botHintsUsed` is "hints unknown", NOT clean. Every game archived
/// before the field started being written lacks it, and awarding those the
/// solid crown would credit them with a discipline nobody recorded. `false` —
/// which the save path now writes explicitly for every bot game — is the only
/// thing that means "known clean". Issue #144.
WinCrown? winCrown(Map<String, dynamic> g) {
  if (g[kImportedKey] == true) return null; // no "you" in an imported game
  final botColor = g['botColor'] as String?;
  if (g['botElo'] == null || botColor == null) return null; // solo analysis
  // Two bots playing each other: playerColor defaults to 'w' in that case, so
  // the record looks like a human White game and the result would read as a
  // human win. Nobody played it.
  if (g['botBothSides'] == true) return null;
  final humanWon = g['result'] == (botColor == 'b' ? '1-0' : '0-1');
  if (!humanWon) return null;

  final help = <String>[];
  final undos = (g['botUndos'] as num?)?.toInt() ?? 0;
  if (undos > 0) help.add('$undos takeback${undos == 1 ? '' : 's'}');
  if (g['botFallback'] == true) help.add('engine stand-in');
  final hints = g['botHintsUsed'];
  if (hints == true) help.add('hint overlays');
  if (hints == null) help.add('hints unknown (pre-tracking)');

  return help.isEmpty
      ? (clean: true, detail: 'Won clean — blind, no takebacks')
      : (clean: false, detail: 'Won with help — ${help.join(', ')}');
}

class GamesListBody extends StatefulWidget {
  /// How a PGN leaves the app. Defaults to the real platform write; a test
  /// hands in a recorder, which is what makes the filename and the exported
  /// bytes assertable at all.
  final TextFileSaver saveFile;

  /// The lichess importer. Null means "build the real one from the bridge
  /// when the dialog opens" — the same injection seam as [saveFile], and the
  /// reason a test can drive the whole import without a network or a JS host.
  final LichessImportApi? importApi;

  const GamesListBody({super.key, this.saveFile = saveTextFile, this.importApi});

  @override
  State<GamesListBody> createState() => _GamesListBodyState();
}

class _GamesListBodyState extends State<GamesListBody> {
  // no initState load: the tab is built lazily on first visit and the shell's
  // tab handler already calls loadGames() on every visit, including that one

  @override
  Widget build(BuildContext context) {
    final review = context.watch<ReviewController>();
    // a game under review replaces the list within this tab, so the shell —
    // and the bottom tabs — stay put
    if (review.current != null) return const ReviewBody();
    if (!review.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _importBar(context),
        const Divider(height: 1, color: Color(0xFF2c2a26)),
        Expanded(
          child: review.games.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'No games yet — finish one, or import your lichess '
                      'history above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                )
              // Lazy by construction: ListView.separated builds only the rows
              // in view, which is the guard the Svelte archive had to hand-roll
              // (it virtualised because "thousands of imported games would
              // otherwise become thousands of DOM rows"). What is NOT lazy is
              // the data behind it — ReviewController holds every stored game,
              // moves and all, decoded in memory. See the import dialog's game
              // cap.
              : ListView.separated(
                  itemCount: review.games.length,
                  separatorBuilder: (_, i) =>
                      const Divider(height: 1, color: Color(0xFF2c2a26)),
                  itemBuilder: (context, i) =>
                      _row(context, review, review.games[i]),
                ),
        ),
      ],
    );
  }

  /// The import affordance, in the tab the imported games land in.
  ///
  /// Here rather than only in the wide-window Game menu (which is where the
  /// PGN paste lives) because that menu does not exist on a phone, and
  /// because "where are my games" and "bring my games in" are the same
  /// thought.
  Widget _importBar(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: TextButton.icon(
            onPressed: () => _importFromLichess(context),
            icon: const Icon(Icons.cloud_download_outlined, size: 17),
            label: const Text('Import from lichess',
                style: TextStyle(fontSize: 12.5)),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
        ),
      );

  Future<void> _importFromLichess(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final summary = await showLichessImport(context, api: widget.importApi);
    if (summary == null) return; // cancelled, or it reported its own error
    final games = '${summary.games} game${summary.games == 1 ? '' : 's'}';
    final puzzles = summary.puzzles == 0
        ? 'no new practice positions'
        : '${summary.puzzles} practice position'
            '${summary.puzzles == 1 ? '' : 's'}';
    messenger?.showSnackBar(SnackBar(
      content: Text('Imported $games · $puzzles'
          '${summary.skipped > 0 ? ' · ${summary.skipped} skipped' : ''}'),
    ));
  }

  /// Hand one game's PGN to the platform.
  ///
  /// The string is not built here — game_controller has written a full PGN
  /// onto every record since the archive existed. All this decides is the
  /// filename, and the names in it are the ones the row shows: an imported
  /// game keeps the players its own headers named, and a played one is
  /// You-vs-the-persona, with the persona's CURRENT name for the same reason
  /// the row uses it rather than the stored id.
  Future<void> _exportPgn(
    BuildContext context,
    Map<String, dynamic> g, {
    required String pgn,
    required bool imported,
    required String personaName,
    required bool youAreWhite,
  }) async {
    final filename = pgnFilename(
      white: imported
          ? g['white'] as String?
          : (youAreWhite ? 'You' : personaName),
      black: imported
          ? g['black'] as String?
          : (youAreWhite ? personaName : 'You'),
      endedAt: g['endedAt'] as String? ?? '',
    );
    // Captured before the await — the row can be gone by the time a share
    // sheet closes, and a dead context cannot find a messenger.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final origin = tapOrigin(context);
    try {
      final saved = await widget.saveFile(
        filename: filename,
        text: pgn,
        mimeType: 'application/x-chess-pgn',
        origin: origin,
      );
      // Silence on false is deliberate: the user cancelled, and telling them
      // so is telling them what they just did.
      if (saved) {
        messenger?.showSnackBar(SnackBar(content: Text('Saved $filename')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    }
  }

  Widget _row(BuildContext context, ReviewController review,
      Map<String, dynamic> g) {
    final result = g['result'] as String? ?? '*';
    final botColor = g['botColor'] as String?;
    final youAreWhite = botColor == 'b';
    final won = result == (youAreWhite ? '1-0' : '0-1');
    final lost = result == (youAreWhite ? '0-1' : '1-0');
    final verdict = won ? 'Won' : (lost ? 'Lost' : 'Draw');
    final color = won
        ? const Color(0xFF81B64C)
        : (lost ? const Color(0xFFCA3431) : Colors.white54);

    // 'lichess' | 'chesscom' — a game fetched from your account (#134),
    // which is NOT the same thing as a pasted PGN: there is a "you" in it
    // (the mapper set botColor to the OPPONENT's colour, so Won/Lost and the
    // accuracy column both mean what they say), and the opponent has a name
    // rather than a persona id.
    final source = g['source'] as String?;
    final storedId = g['botPersona'] as String?;
    // The NAME, not the stored id. Two reasons: the archive used to read
    // "vs squarefish-1200", and after the rename the same opponent appeared
    // under two different slugs depending on when the game was played.
    final personaId =
        context.read<GameController>().personaFor(storedId)?.name ??
            storedId ??
            'bot';
    final endedAt = g['endedAt'] as String? ?? '';
    final when = endedAt.length >= 16
        ? endedAt.substring(0, 16).replaceFirst('T', ' ')
        : endedAt;
    final youAcc = (youAreWhite ? g['whiteAccuracy'] : g['blackAccuracy']);
    final counts = ((g['labelCounts'] as Map?)?[youAreWhite ? 'w' : 'b']
            as Map?)
        ?.cast<String, dynamic>();
    final blunders = (counts?['blunder'] as num?)?.toInt() ?? 0;
    final mistakes = (counts?['mistake'] as num?)?.toInt() ?? 0;

    // A pasted PGN has no "you" in it, so Won/Lost and "vs <bot>" are both
    // meaningless — show the raw result and whoever the PGN said was playing.
    // A fetched game whose importer is not one of the players (nothing
    // produces one today, but the mapper can return that) is in the same boat.
    final imported = g[kImportedKey] == true || (source != null && botColor == null);
    // Who you actually played. Falling through to the persona name would put
    // "vs bot" on every imported game, since no persona is stored on one.
    final opponent = source == null
        ? 'vs $personaId'
        : 'vs ${(youAreWhite ? g['black'] : g['white']) as String? ?? 'unknown'}';
    final crown = winCrown(g);
    // Every archived record has carried a full PGN since the save path was
    // written; until now it had no way out of the app (#138). Games saved by
    // a build older than that field have none, and the button is simply not
    // drawn for them rather than exporting an empty file.
    final pgn = g['pgn'] as String?;

    return ListTile(
      dense: true,
      // Material's three-line spacing for the row that now has three lines.
      // Not load-bearing — a ListTile grows to fit its subtitle either way
      // (measured at 375px: 68px tall without this, 76 with) — so it is the
      // padding convention, not a fix for a spill.
      isThreeLine: crown != null,
      title: Row(children: [
        Text(imported ? result : verdict,
            style: TextStyle(
                color: imported ? Colors.white54 : color,
                fontWeight: FontWeight.w700)),
        if (crown != null) ...[
          const SizedBox(width: 5),
          // an Icon, not a glyph: U+265B is in no bundled font, so a Text of it
          // is a webfont FETCH on the web build (and tofu with no network)
          Icon(crown.clean ? Icons.emoji_events : Icons.emoji_events_outlined,
              size: 15,
              color: crown.clean ? const Color(0xFFD4A017) : Colors.white38),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: Text(imported ? importedTitle(g) : opponent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
        if (youAcc != null && !imported)
          Text('${(youAcc as num).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$when · ${g['moveCount']} moves'
            // where it came from, since the grades on an imported game are
            // that server's and not this app's engine
            '${source != null ? ' · $source' : ''}'
            '${blunders > 0 ? ' · $blunders ??' : ''}'
            '${mistakes > 0 ? ' · $mistakes ?' : ''}',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          // spelled out rather than left to a tooltip: the crown is the
          // scannable mark, this is what it MEANS, and on a phone a tooltip is
          // a long-press — the gesture this row already spends on delete
          if (crown != null)
            Text(crown.detail,
                style: TextStyle(
                    fontSize: 11,
                    color: crown.clean
                        ? const Color(0xFFD4A017)
                        : Colors.white38)),
        ],
      ),
      // The download button the Svelte archive had on every row, as a
      // Material icon rather than that version's glyph. Sized
      // and padded down to 40x40 rather than the stock 48: the whole row is
      // itself a tap target that opens the review, so the two want a visible
      // gap, and a taller trailing would grow the row it sits in.
      trailing: pgn == null || pgn.isEmpty
          ? null
          // A Builder so the share sheet's popover anchors to the BUTTON
          // rather than to whatever render object sits above the row.
          : Builder(
              builder: (btnContext) => IconButton(
                icon: const Icon(Icons.file_download_outlined, size: 19),
                color: Colors.white38,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 40),
                tooltip: 'Export PGN',
                onPressed: () => _exportPgn(
                  btnContext,
                  g,
                  pgn: pgn,
                  imported: imported,
                  personaName: personaId,
                  youAreWhite: youAreWhite,
                ),
              ),
            ),
      // opens in place, inside this tab — pushing a route would cover the
      // shell and take the bottom tabs with it
      onTap: () => review.open(g),
      onLongPress: () => showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Delete game?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                review.deleteGame(g['id'] as String);
                Navigator.pop(dctx);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
