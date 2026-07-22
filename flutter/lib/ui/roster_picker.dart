// Bot picker: a modal sheet listing the roster grouped by family, each group
// sorted by elo and the groups themselves ordered by their members' average
// elo — gentlest family first (#136). `pickBot` RETURNS the chosen id
// (Navigator result); the New Game sheet decides what to do with it. It sets
// nothing itself.
//
// The filter below is the honest edge of the port: a family appears here only
// once _pickBotMove can actually play it. Everything else in the roster would
// silently fall back to Stockfish, which is a different opponent wearing the
// persona's name. GameController still HAS that fallback, for ids that arrive
// without passing through this sheet — the point of the filter is that nobody
// is ever offered one on purpose.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/types.dart';
import '../engine/garbo_engine.dart';
import '../engine/maia_engine.dart';
import '../engine/maia_weights.dart';
import '../engine/retro_engine.dart';
import '../stores/bot_record_store.dart';
import '../stores/game_controller.dart';
import '../stores/player_rating_store.dart';

// Three families are platform-conditional rather than simply present, and each
// answers for ITSELF — the platforms are not enumerated here on purpose,
// because they have already moved once (Garbo and Maia are native now, not
// web-only) and a list in this file would have gone stale silently. Listing a
// family where it cannot play would be the exact substitution this filter
// exists to prevent.
//
// Dala is on no branch at all: it needs the lc0 sidecar and #45 was never
// implemented, so it renders nowhere.
final _playableFamilies = {
  'squarefish',
  'stockfish',
  'horizon',
  if (RetroEngine.supported) 'retro',
  if (GarboEngine.supported) 'garbo',
  if (MaiaEngine.supported) 'maia',
};

/// One family's personas, as a group renders: members ascending by elo, and
/// the group's own place in the sheet set by [averageElo].
///
/// A group exists only because personas put it there, which is what keeps a
/// family this platform cannot play from leaving an empty heading behind:
/// there is no list of families anywhere for the roster to drift from.
class RosterGroup {
  final String family;

  /// Ascending by elo. Owned by this group: [groupRoster] sorts it in place
  /// before handing it over.
  final List<Persona> members;
  const RosterGroup(this.family, this.members);

  /// Where the group sits in the sheet: its members' average elo.
  ///
  /// A note on what this does NOT guard against, because the issue and an
  /// earlier version of this comment both got it wrong. The filter is
  /// family-granular — every persona of a family shares its family — so a
  /// surviving family keeps ALL its members either way, and its average is
  /// identical whether computed before or after filtering. Averaging "too
  /// early" cannot reorder anything.
  ///
  /// The real failure is GROUPING before filtering: that builds a heading for
  /// a family this platform cannot play and then empties it, leaving a Dala
  /// heading with nothing under it. [groupRoster] filters as it groups, so the
  /// empty heading is unconstructable rather than guarded against.
  double get averageElo =>
      members.fold<int>(0, (sum, p) => sum + p.elo) / members.length;

  /// 'squarefish' -> 'Squarefish'. Derived rather than looked up: a map would
  /// be a second table of family strings to fall out of step with
  /// `brain/bots.ts`, and every family's personas are already named with this
  /// exact capitalisation ("Squarefish 900", "Maia II", "Garbo 2011").
  String get label => family[0].toUpperCase() + family.substring(1);
}

/// Group [personas] by family for the sheet: drop what this platform cannot
/// play, sort each family by elo, and order the families by average elo.
///
/// [playable] is injectable so a test can simulate a platform other than the
/// one it runs on — the filter is the whole reason the averages are computed
/// here rather than over the roster.
List<RosterGroup> groupRoster(Iterable<Persona> personas,
    {Set<String>? playable}) {
  final filter = playable ?? _playableFamilies;
  final byFamily = <String, List<Persona>>{};
  for (final p in personas) {
    if (!filter.contains(p.family)) continue;
    (byFamily[p.family] ??= <Persona>[]).add(p);
  }
  final groups = [
    for (final e in byFamily.entries)
      RosterGroup(e.key, e.value..sort((a, b) => a.elo.compareTo(b.elo)))
  ];
  // Family name breaks a tie so the sheet is stable rather than dependent on
  // whatever order the roster happened to arrive in.
  groups.sort((a, b) {
    final byElo = a.averageElo.compareTo(b.averageElo);
    return byElo != 0 ? byElo : a.family.compareTo(b.family);
  });
  return groups;
}

/// Pick a bot. Returns the chosen persona id, or null if dismissed — it no
/// longer mutates global state, because "who plays this side" is now a choice
/// the New Game sheet assembles, not a persistent setting the picker commits.
///
/// The records are read from disk BEFORE the sheet is shown rather than watched
/// from inside it: the archive is small (app_db.dart) and awaiting one read
/// keeps the sheet a pure function of its inputs, so the widget tests can pump
/// it with a records map directly instead of standing up a store. The player's
/// own rating is read as-is, NOT refreshed — the game-over recap refits it, and
/// that is the flow right before this one (finish a game, open New Game, pick),
/// so it is warm exactly when the "near your level" marker matters; when it is
/// null (fewer than the estimator's minimum rated games) the marker stays off,
/// which is honest rather than guessed.
Future<String?> pickBot(BuildContext context, {String? current}) async {
  final game = context.read<GameController>();
  final store = context.read<BotRecordStore>();
  final playerElo = context.read<PlayerRatingStore>().rating?.elo;
  await store.refresh(game.personaFor);
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => RosterSheet(
      game: game,
      current: current,
      records: store.records,
      playerElo: playerElo,
    ),
  );
}

/// The sheet itself. Public only so a widget test can pump it without driving
/// a modal route.
class RosterSheet extends StatefulWidget {
  final GameController game;
  final String? current;

  /// The platform filter, injectable for the same reason [groupRoster]'s is:
  /// CI is Linux, where Maia is not playable, so a test that leaned on the
  /// host's answer would assert nothing there and say so nowhere.
  final Set<String>? playable;

  /// Per-persona human W-L-D from the archive, keyed by resolved persona id
  /// (see [BotRecordStore]). Passed in rather than watched so the sheet stays a
  /// pure function of its inputs; empty means "no record line", which is what
  /// the existing tests that omit it get.
  final Map<String, BotRecord> records;

  /// The player's own estimated rating, or null when the archive has not fit
  /// one yet. A persona within [_nearYouElo] of it is marked as being around
  /// the player's level.
  final int? playerElo;

  const RosterSheet({
    super.key,
    required this.game,
    this.current,
    this.playable,
    this.records = const {},
    this.playerElo,
  });

  @override
  State<RosterSheet> createState() => _RosterSheetState();
}

class _RosterSheetState extends State<RosterSheet> {
  /// Where a member tile's text starts, so it lines up under its heading's
  /// label rather than under the heading's mark: 16 padding + a 32-wide
  /// CircleAvatar + the 12 gap.
  static const double _memberIndent = 60;

  /// How close a persona's elo has to be to the player's for the row to read as
  /// being around their level. The Svelte version's "≈ you" badge; ~100 is a
  /// little under half the gap between adjacent squarefish rungs, so it marks a
  /// small handful rather than a whole family.
  static const int _nearYouElo = 100;

  @override
  void initState() {
    super.initState();
    // Two things, and only one of them is about this sheet.
    //
    // [refresh] is: the marks below are a claim about the disk, so the disk is
    // what they are read from, every time the sheet opens.
    //
    // [prefetch] is the app's (#130), and this is not where it belongs —
    // boot is. It is here because opening the opponent list is the first
    // moment this file knows Maia is on screen, and somebody browsing the
    // roster is precisely the person about to need a band. It is not the only
    // trigger: MaiaEngine starts it again once a band has loaded, so a player
    // who never opens this sheet still fills the cache by playing one Maia
    // game. Returns immediately, skips what is already cached, runs at most
    // once per launch, and does nothing at all on the web.
    // Gated like the boot trigger. MaiaEngine.supported is macOS/iOS only, but
    // the conditional export keys on dart.library.js_interop, so Android
    // resolves the _io implementation and would fetch three unusable 3.5MB
    // nets — for a family the picker has already filtered out.
    if (MaiaEngine.supported) {
      MaiaWeights.refresh();
      MaiaWeights.prefetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<int>?>(
      // So a band that lands while the sheet is open stops asking to be
      // downloaded — the prefetch this sheet just started can finish under it.
      valueListenable: MaiaWeights.cached,
      builder: (context, cached, _) => _sheet(cached),
    );
  }

  Widget _sheet(Set<int>? cached) {
    final game = widget.game;
    final groups = groupRoster(game.rosterPersonas, playable: widget.playable);
    // Flattened once rather than indexed into with arithmetic per row: the
    // heading/member distinction is then a type, not an offset calculation.
    final rows = <Object>[
      for (final g in groups) ...[g, ...g.members]
    ];
    // Resolved once, outside the builder: `current` comes from settings and may
    // be a pre-rename id, which would match no tile and highlight nothing.
    final currentId = game.personaFor(widget.current)?.id ?? widget.current;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => ListView.builder(
        controller: scroll,
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          if (row is RosterGroup) return _heading(row, first: i == 0);
          final p = row as Persona;
          final selected = p.id == currentId;
          final recordNote = _recordNote(p);
          return ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: const Color(0xFF3a3733),
            // No leading mark on the row: the heading above it carries the
            // family's icon and colour now, so repeating it per row would say
            // the same thing twice within a group that cannot contain anything
            // else. The tile is indented instead, which is what makes a row
            // read as belonging to the heading.
            contentPadding:
                const EdgeInsets.only(left: _memberIndent, right: 16),
            title: Text('${p.name}  ·  ${p.elo}',
                style: const TextStyle(fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The actionable new line first: on a 32-bot roster, "you are
                // 3W 1L 0D here" is what tells a player where to go next, so it
                // reads above the blurb rather than below it.
                ?recordNote,
                Text(p.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.white38)),
                if (p.maiaBand != null) _maiaNote(p.maiaBand!, cached),
              ],
            ),
            onTap: () => Navigator.pop(context, p.id),
          );
        },
      ),
    );
  }

  /// The player's line against this persona: their W-L-D record, and whether
  /// the bot is around their own strength. Null when there is neither — a
  /// persona the player has never finished a game against, and not near their
  /// level, adds no line.
  ///
  /// The two facts share one line because they answer the same question — "is
  /// this a good next opponent" — and a dense sheet cannot afford a row each.
  /// The separator is a middle dot `·`, and the marker is the plain words "near
  /// your level": an "≈" is in none of the three bundled Roboto faces, so a
  /// Text carrying one makes Flutter web fetch a font from fonts.gstatic.com.
  Widget? _recordNote(Persona p) {
    final rec = widget.records[p.id] ?? const BotRecord();
    final nearYou = widget.playerElo != null &&
        (p.elo - widget.playerElo!).abs() <= _nearYouElo;
    if (rec.played == 0 && !nearYou) return null;
    final parts = <String>[
      if (rec.played > 0) '${rec.won}W ${rec.lost}L ${rec.drawn}D',
      if (nearYou) 'near your level',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 1),
      child: Text(
        parts.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xFFbfae7a)),
      ),
    );
  }

  /// What a Maia row says about its weights, which is the one thing on this
  /// sheet that can differ between two personas with the same blurb.
  ///
  /// Maia is the only family that reaches the network, and the only place the
  /// app does at all — the nets are GPL-3.0 and deliberately fetched rather
  /// than shipped (#30, #130), so this is a permanent property rather than a
  /// first-run detail. Three states, because there are genuinely three:
  ///
  ///   cached      — the file is under Application Support; this persona plays
  ///                 with the network off.
  ///   not cached  — it is not, and choosing it now means waiting. This is the
  ///                 case the sheet used to hide, and the commonest way a
  ///                 persona quietly becomes Stockfish instead (#117).
  ///   unknown     — the web, where the weights live in the worker's IndexedDB
  ///                 and Dart cannot see them. Says what it always said.
  ///
  /// Material [Icon]s, never a Unicode arrow or cloud: those live in no
  /// bundled font, so drawing one makes Flutter web fetch a font from
  /// fonts.gstatic.com — a third-party request the offline build cannot serve.
  Widget _maiaNote(int band, Set<int>? cached) {
    final ready = cached?.contains(band);
    final (IconData icon, String text, Color color) = switch (ready) {
      true => (
          Icons.offline_pin_outlined,
          'downloaded — plays offline',
          const Color(0xFF7f9a72),
        ),
      false => (
          Icons.file_download_outlined,
          'needs a short download — then plays offline',
          const Color(0xFF9a8f7a),
        ),
      // Not "a 3.5MB model, once": that is the weights alone and omits the
      // ~3.3MB runtime, which a deploy re-fetches (see
      // MaiaProgress.reassurance). "A short download" promises neither a size
      // nor a frequency it cannot keep; "then plays offline" is the durable
      // truth.
      null => (
          Icons.file_download_outlined,
          'a short download the first time — then plays offline',
          const Color(0xFF9a8f7a),
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          // Expanded, because these lines wrap on a narrow phone and a Row
          // that overflows is a runtime error the analyzer cannot see.
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// A family heading. The label is [RosterGroup.label] alone: the issue's
  /// other candidate, a strength range like "Squarefish · 600-1700", is worth
  /// having only if the families' overlapping ranges actually read badly once
  /// this ships, and it is not needed to make the grouping legible.
  ///
  /// [Expanded] round the text so a long family name ellipsises rather than
  /// overflowing the Row on a narrow phone — a RenderFlex overflow is a
  /// runtime error the analyzer cannot see.
  Widget _heading(RosterGroup g, {required bool first}) => Padding(
        padding: EdgeInsets.fromLTRB(16, first ? 12 : 20, 16, 6),
        child: Row(
          children: [
            _familyMark(g.family),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                g.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                  color: Color(0xFF9a9089),
                ),
              ),
            ),
          ],
        ),
      );

  /// Material Icons rather than the Unicode glyphs these used to be (▦ ◆ ◓).
  /// Those live in no bundled font, so drawing them made Flutter web fetch
  /// Noto Sans Symbols 2 from fonts.gstatic.com the moment this sheet opened —
  /// a third-party request, and one the offline build could not serve. The
  /// icon font is already bundled and tree-shaken, so these cost ~nothing.
  /// Takes the family string rather than a Persona: it is now drawn once per
  /// GROUP, where no single persona is the one to hand it. `brain/familyParity`
  /// reads this function's body for the family literals, so the declaration has
  /// to keep starting `Widget _familyMark`.
  Widget _familyMark(String family) {
    final (icon, color) = switch (family) {
      'squarefish' => (Icons.grid_view, const Color(0xFFd0b755)),
      'stockfish' => (Icons.diamond_outlined, const Color(0xFF5b8bb0)),
      // a sun resting on the horizon — the same idea as the web avatar: this
      // engine cannot see past its own exchanges
      'horizon' => (Icons.wb_twilight, const Color(0xFFc4783f)),
      // a valve, for the machines that had them
      'retro' => (Icons.memory, const Color(0xFF9a7bb0)),
      // hand-written JavaScript, so: braces
      'garbo' => (Icons.data_object, const Color(0xFF6f9e8a)),
      // a net trained on people
      'maia' => (Icons.psychology_outlined, const Color(0xFFb06f8a)),
      _ => (Icons.circle, Colors.white38),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFF1b1a17),
      child: Icon(icon, color: color, size: 17),
    );
  }
}
