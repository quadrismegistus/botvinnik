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
import '../engine/retro_engine.dart';
import '../stores/game_controller.dart';

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

  /// Where the group sits in the sheet. Averaged over [members] — the personas
  /// that SURVIVED the platform filter — so the sheet cannot come out in one
  /// order on the web and another on iOS for no reason a player can see.
  /// Averaged over the whole roster instead, Dala (1107) would take a place
  /// between Horizon and Squarefish on every platform and render nothing in it.
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
Future<String?> pickBot(BuildContext context, {String? current}) {
  final game = context.read<GameController>();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF262421),
    isScrollControlled: true,
    builder: (_) => RosterSheet(game: game, current: current),
  );
}

/// The sheet itself. Public only so a widget test can pump it without driving
/// a modal route.
class RosterSheet extends StatelessWidget {
  final GameController game;
  final String? current;
  const RosterSheet({super.key, required this.game, this.current});

  /// Where a member tile's text starts, so it lines up under its heading's
  /// label rather than under the heading's mark: 16 padding + a 32-wide
  /// CircleAvatar + the 12 gap.
  static const double _memberIndent = 60;

  @override
  Widget build(BuildContext context) {
    final groups = groupRoster(game.rosterPersonas);
    // Flattened once rather than indexed into with arithmetic per row: the
    // heading/member distinction is then a type, not an offset calculation.
    final rows = <Object>[
      for (final g in groups) ...[g, ...g.members]
    ];
    // Resolved once, outside the builder: `current` comes from settings and may
    // be a pre-rename id, which would match no tile and highlight nothing.
    final currentId = game.personaFor(current)?.id ?? current;
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
                Text(p.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.white38)),
                // Maia is the one persona family that reaches the network, and
                // the only place the app does at all. Say so before it is
                // chosen rather than during the pause it causes — the weights
                // are GPL-3.0 and deliberately not shipped with the app, so
                // this is a permanent property, not a first-run detail.
                if (p.maiaBand != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    // Not "a 3.5MB model, once": that is the weights alone and
                    // omits the ~3.3MB runtime, which a deploy re-fetches (see
                    // MaiaProgress.reassurance). "A short download" promises
                    // neither a size nor a frequency it cannot keep; "then
                    // plays offline" is the durable truth.
                    child: Text(
                      'a short download the first time — then plays offline',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF9a8f7a)),
                    ),
                  ),
              ],
            ),
            onTap: () => Navigator.pop(context, p.id),
          );
        },
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
