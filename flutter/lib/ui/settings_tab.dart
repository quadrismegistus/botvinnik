// The Settings tab. Small on purpose — settings that belong to a specific
// flow (opponent, side) live in that flow's sheet; this is for the app-wide
// knobs.

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show NormalMove, PieceKind, Side;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../engine/custom_engine_runner.dart';
import '../stores/backup.dart';
import '../stores/files.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';
import '../stores/settings_store.dart';
import '../sync/sync_controller.dart';
import 'about_section.dart';
import 'sync_screen.dart';
import 'board_theme.dart';
import 'engines_screen.dart';

class SettingsTab extends StatelessWidget {
  /// The file layer, injected so tests can drive a real backup through a
  /// recorder instead of a platform channel. See [TextFileSaver].
  final TextFileSaver saveFile;
  final TextFileReader readFile;

  const SettingsTab({
    super.key,
    this.saveFile = saveTextFile,
    this.readFile = readTextFile,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final practice = context.watch<PracticeController>();
    final belowThreshold = practice.items.length - practice.servable.length;
    // The Review tab loads the archive on first visit, so a count read before
    // that has ever happened would say "0 games" about a full archive. Left
    // unnumbered until it is known — the backup itself reads the database, not
    // this list, so the number is a label rather than the thing exported.
    final review = context.watch<ReviewController>();
    final games = review.loaded
        ? '${review.games.length} game${review.games.length == 1 ? '' : 's'}'
        : 'every game played';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const _SectionLabel('Board'),
        SwitchListTile(
          dense: true,
          title: const Text('Engine arrows'),
          subtitle: const Text(
            'The engine\'s best moves, fading by rank.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showArrows,
          onChanged: (v) => settings.showArrows = v,
        ),
        if (settings.showArrows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            child: Row(
              children: [
                const Text('Arrows shown',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                const Spacer(),
                // analysis is MultiPV-5, so five lines always exist
                DropdownButton<int>(
                  value: settings.arrowCount,
                  underline: const SizedBox(),
                  isDense: true,
                  items: const [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n',
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) settings.arrowCount = v;
                  },
                ),
              ],
            ),
          ),
        if (settings.showArrows)
          _OpacitySlider(
            label: 'Arrow opacity',
            value: settings.arrowOpacity,
            onChanged: (v) => settings.arrowOpacity = v,
          ),
        SwitchListTile(
          dense: true,
          title: const Text('Threat arrow'),
          subtitle: const Text(
            'What the opponent would do with a free move, when it wins material.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showThreats,
          onChanged: (v) => settings.showThreats = v,
        ),
        if (settings.showThreats)
          _OpacitySlider(
            label: 'Threat arrow opacity',
            value: settings.threatOpacity,
            onChanged: (v) => settings.threatOpacity = v,
          ),
        SwitchListTile(
          dense: true,
          title: const Text('Square control'),
          subtitle: const Text(
            'Tint squares each side safely controls — green yours, red theirs.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.showControl,
          onChanged: (v) => settings.showControl = v,
        ),
        if (settings.showControl)
          _OpacitySlider(
            label: 'Control tint opacity',
            value: settings.controlOpacity,
            onChanged: (v) => settings.controlOpacity = v,
          ),
        const _SectionLabel('Practice'),
        ListTile(
          dense: true,
          title: const Text('Practice mistakes losing at least'),
          subtitle: Text(
            'Everything ≥5% is collected; this filters which puzzles '
            'you actually drill.'
            '${belowThreshold > 0 ? ' ($belowThreshold collected below the current bar)' : ''}',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          trailing: DropdownButton<int>(
            value: settings.collectThreshold,
            underline: const SizedBox(),
            items: const [5, 10, 15, 20, 30]
                .map((v) =>
                    DropdownMenuItem(value: v, child: Text('$v% win chance')))
                .toList(),
            onChanged: (v) {
              if (v != null) settings.collectThreshold = v;
            },
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Ease in'),
          subtitle: const Text(
            'Start each session with easier puzzles, warming up before the '
            'hard ones — they all still come up. Off is strict due order.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          value: settings.easeIn,
          onChanged: (v) => settings.easeIn = v,
        ),
        ListTile(
          dense: true,
          title: const Text('Collected puzzles'),
          subtitle: Text(
            '${practice.items.length} total · ${practice.servable.length} above the bar · ${practice.due} due',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
        ),
        const _SectionLabel('Bot vs bot'),
        ListTile(
          dense: true,
          title: const Text('Move delay'),
          subtitle: Text(
            '${(settings.botDelayMs / 1000).toStringAsFixed(1)}s between moves '
            'when both sides are bots',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Slider(
            value: settings.botDelayMs.toDouble().clamp(0, 3000),
            min: 0,
            max: 3000,
            divisions: 30,
            label: '${(settings.botDelayMs / 1000).toStringAsFixed(1)}s',
            onChanged: (v) => settings.botDelayMs = v.round(),
          ),
        ),
        if (CustomEngineRunner.supported) ...[
          const _SectionLabel('Engines'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.terminal, size: 20),
            title: const Text('Custom engines'),
            subtitle: const Text(
              'Download a known engine, or add your own UCI binary — it joins '
              'the roster as an opponent.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EnginesScreen())),
          ),
        ],
        const _SectionLabel('Your data'),
        // A Builder so the iPad share sheet anchors to the row that was
        // tapped — the tab's own context is above the scroll view. Restore
        // needs none: an open panel has no popover to place.
        Builder(
          builder: (rowContext) => ListTile(
            dense: true,
            leading: const Icon(Icons.file_download_outlined, size: 20),
            title: const Text('Back up everything'),
            subtitle: Text(
              'Practice positions and the game archive, as one JSON file. '
              '${practice.items.length} puzzles · $games.',
              style: const TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            onTap: () => _export(rowContext),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.file_upload_outlined, size: 20),
          title: const Text('Restore from a backup'),
          // The merge rule stated where the decision is taken, because it is
          // the question anyone about to tap this has: does it wipe what is
          // already here? It does not — import only ever adds.
          subtitle: const Text(
            'Adds what is missing. Nothing here is deleted, and a puzzle you '
            'have practised more wins over the copy in the file.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          onTap: () => _import(context),
        ),
        Builder(
          builder: (context) {
            final on = context.watch<SyncController>().enabled;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.sync, size: 20),
              title: const Text('Sync across devices'),
              subtitle: Text(
                on
                    ? 'On. Games and practice sync privately to your other devices.'
                    : 'Off. Turn on private, encrypted sync — no account needed.',
                style: const TextStyle(fontSize: 11.5, color: Colors.white38),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncScreen())),
            );
          },
        ),
        const _SectionLabel('Board theme'),
        const _BoardColorSection(),
        const _SectionLabel('About'),
        const AboutSection(),
      ],
    );
  }

  // ---- backup (#138) ----

  /// The whole store as one file.
  ///
  /// Built from the DATABASE rather than from the two controllers, so what is
  /// exported is what is persisted: a puzzle collected seconds ago and a
  /// controller list that has not been reloaded since cannot disagree, and
  /// there is no ordering requirement on which tabs the user has visited.
  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final service = BackupService(context.read<ReviewController>().db);
    final origin = tapOrigin(context);
    try {
      final now = DateTime.now();
      final saved = await saveFile(
        filename: backupFilename(now),
        text: await service.exportJson(at: now),
        mimeType: 'application/json',
        origin: origin,
      );
      if (saved) {
        messenger?.showSnackBar(
            SnackBar(content: Text('Saved ${backupFilename(now)}')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not back up: $e')));
    }
  }

  /// Merge a backup file back in, then make both controllers re-read.
  ///
  /// The reload is not cosmetic: the import writes underneath them, so without
  /// it the Practice tab keeps serving the pre-import queue and the archive
  /// keeps showing the pre-import list until the app is restarted — which
  /// looks exactly like an import that did nothing.
  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final review = context.read<ReviewController>();
    final practice = context.read<PracticeController>();
    try {
      final text = await readFile(
        extension: 'json',
        mimeType: 'application/json',
        uti: 'public.json',
      );
      if (text == null) return; // cancelled
      final counts = await BackupService(review.db).importJson(text);
      await practice.load();
      await review.loadGames();
      messenger?.showSnackBar(SnackBar(
        content: Text(counts.practice == 0 && counts.games == 0
            ? 'Nothing new — everything in that file was already here.'
            : 'Restored ${counts.games} game${counts.games == 1 ? '' : 's'} '
                'and ${counts.practice} puzzle'
                '${counts.practice == 1 ? '' : 's'}.'),
      ));
    } on BackupFormatException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not restore: $e')));
    }
  }
}


/// A 0–1 opacity control. Shows the value so a setting can be described and
/// restored, not just dragged until it looks right.
class _OpacitySlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _OpacitySlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          SizedBox(
            width: 148,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              label: '${(value * 100).round()}%',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 38,
            child: Text('${(value * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white38,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// Square and highlight colors, with a live board sample — the real board is
/// on another tab, so the sample is what makes a change legible while you
/// are choosing it. Edits apply as you drag, and Cancel puts the color back.
class _BoardColorSection extends StatelessWidget {
  const _BoardColorSection();

  static const _sampleFen =
      'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              StaticChessboard(
                size: 132,
                fen: _sampleFen,
                lastMove: NormalMove.fromUci('e2e4'),
                orientation: Side.white,
                settings: staticBoardSettingsFor(s),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Swatch(
                      label: 'Light squares',
                      color: s.lightSquare,
                      onPick: (c) => s.lightSquare = c,
                    ),
                    _Swatch(
                      label: 'Dark squares',
                      color: s.darkSquare,
                      onPick: (c) => s.darkSquare = c,
                    ),
                    _Swatch(
                      label: 'Last move',
                      color: s.lastMoveColor,
                      withAlpha: true,
                      onPick: (c) => s.lastMoveColor = c,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Strip(
          label: 'Colors',
          count: kBoardPresets.length,
          builder: (i) {
            final p = kBoardPresets[i];
            return _Chip(
              label: p.name,
              selected: s.boardTexture.isEmpty &&
                  p.light.toARGB32() == s.lightSquare.toARGB32() &&
                  p.dark.toARGB32() == s.darkSquare.toARGB32(),
              onTap: () => s.applySquares(p.light, p.dark),
              child: Column(children: [
                Row(children: [_cell(p.light), _cell(p.dark)]),
                Row(children: [_cell(p.dark), _cell(p.light)]),
              ]),
            );
          },
        ),
        _Strip(
          label: 'Textures',
          count: kBoardTextures.length,
          builder: (i) {
            final t = kBoardTextures[i];
            final image = t.image;
            return _Chip(
              label: t.label,
              selected: s.boardTexture == t.name,
              onTap: () => s.boardTexture = t.name,
              // the texture previews as itself, scaled so the grain reads
              child: image == null
                  ? ColoredBox(color: t.scheme.darkSquare)
                  : Image(image: image, fit: BoxFit.cover),
            );
          },
        ),
        _Strip(
          label: 'Pieces',
          count: PieceSet.values.length,
          builder: (i) {
            final set = PieceSet.values[i];
            final scheme = schemeFor(s);
            // both colorways, each on the square that contrasts with it —
            // a white piece on a white board would preview as nothing
            return _Chip(
              label: set.label,
              selected: pieceSetFor(s) == set,
              onTap: () => s.pieceSet = set.name,
              child: Row(
                children: [
                  _knight(set, PieceKind.whiteKnight, scheme.darkSquare),
                  _knight(set, PieceKind.blackKnight, scheme.lightSquare),
                ],
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 4),
            child: TextButton(
              onPressed: s.resetBoardColors,
              child: const Text('Reset to default'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled horizontal row of choices. Everything here previews as the
/// thing it selects — squares as squares, textures as their image, piece
/// sets as a piece — so nothing has to be chosen by name alone.
class _Strip extends StatelessWidget {
  final String label;
  final int count;
  final Widget Function(int) builder;
  const _Strip({
    required this.label,
    required this.count,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(label,
              style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
        ),
        SizedBox(
          height: 94,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => builder(i),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF81B64C);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? accent : Colors.white24,
                  width: selected ? 2 : 1,
                ),
              ),
              child: child,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? accent : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _cell(Color c) => Container(width: 30, height: 30, color: c);

Widget _knight(PieceSet set, PieceKind kind, Color square) {
  final image = set.assets[kind];
  return Expanded(
    child: ColoredBox(
      color: square,
      child: image == null
          ? const SizedBox()
          : Padding(
              padding: const EdgeInsets.all(1),
              child: Image(image: image, fit: BoxFit.contain),
            ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  final String label;
  final Color color;
  final bool withAlpha;
  final ValueChanged<Color> onPick;
  const _Swatch({
    required this.label,
    required this.color,
    required this.onPick,
    this.withAlpha = false,
  });

  Future<void> _open(BuildContext context) async {
    final original = color;
    // the first drag frame clears any active texture (picking a colour means
    // a custom board), so Cancel has to put that back too
    final store = context.read<SettingsStore>();
    final originalTexture = store.boardTexture;
    final restored = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1f1e1b),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: original,
            onColorChanged: onPick, // live: the sample repaints as you drag
            enableAlpha: withAlpha,
            hexInputBar: true,
            portraitOnly: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (restored ?? true) {
      onPick(original);
      store.boardTexture = originalTexture;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // checker behind the chip so a translucent color reads as one
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF3a3733),
              ),
              child: Container(
                width: 26,
                height: 18,
                margin: const EdgeInsets.all(1),
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              color: Colors.white38,
              fontWeight: FontWeight.w600)),
    );
  }
}
