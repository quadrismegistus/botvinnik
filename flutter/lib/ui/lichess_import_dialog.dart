// Import your games from lichess by username (#134).
//
// Beside the PGN paste rather than instead of it: paste is how you bring in
// ONE game, from anywhere, including a game nobody analysed. This is how you
// bring in your own history, and it is a different thing — lichess's server
// analysis comes with it, so the games arrive graded and every mistake in
// them lands in Practice without the engine running once.
//
// The dialog does the whole job (fetch, save, seed) rather than handing a
// result back, because the fetch is the slow part and progress has to be
// visible while it happens.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/chess_api.dart';
import '../brain/lichess_import_api.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';

/// What the caller needs to say afterwards. Null when the dialog was
/// cancelled or failed — nothing was written.
typedef ImportSummary = ({int games, int puzzles, int skipped});

/// Opens the dialog and returns what it imported, or null.
Future<ImportSummary?> showLichessImport(BuildContext context,
        {LichessImportApi? api}) =>
    showDialog<ImportSummary>(
      context: context,
      builder: (_) => _LichessImportDialog(
        api: api,
        review: context.read<ReviewController>(),
        practice: context.read<PracticeController>(),
      ),
    );

class _LichessImportDialog extends StatefulWidget {
  /// Injected by tests; otherwise built from the bridge the widget tree
  /// already holds. Built here rather than provided at boot because nothing
  /// else in the app imports, and on native a second JsBridge would mean a
  /// second JavaScriptCore evaluating the whole bundle.
  final LichessImportApi? api;
  final ReviewController review;
  final PracticeController practice;

  const _LichessImportDialog({
    required this.api,
    required this.review,
    required this.practice,
  });

  @override
  State<_LichessImportDialog> createState() => _LichessImportDialogState();
}

class _LichessImportDialogState extends State<_LichessImportDialog> {
  final _name = TextEditingController();
  int _max = kDefaultMaxGames;
  String? _error;
  bool _busy = false;
  int _seen = 0;
  String _stage = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _seen = 0;
      _stage = 'Asking lichess…';
    });
    final api = widget.api ??
        LichessImportApi(context.read<ChessApi>().bridge);
    try {
      // The archive is the dedupe key, and the Review tab may never have been
      // opened in this session — so load it rather than trusting what is in
      // memory, or a re-import would announce games it then overwrote.
      await widget.review.loadGames();
      final existing =
          widget.review.games.map((g) => g['id'] as String).toSet();

      final result = await api.importGames(
        username: _name.text,
        existingIds: existing,
        // The collect FLOOR, not the user's practice threshold: the threshold
        // filters at serve time, so collecting everything above the floor is
        // what lets a later change to it apply to this history too.
        collectThreshold: kCollectMin,
        max: _max,
        onProgress: (n) {
          if (mounted) setState(() => _seen = n);
        },
      );

      if (!mounted) return;
      setState(() => _stage = 'Saving ${result.games.length}…');
      for (final game in result.games) {
        await widget.review.db.saveGame(game);
      }
      await widget.review.loadGames();

      // Practice items are deduped by position inside the controller, so the
      // honest count of what this import added is the difference — not the
      // number of candidates handed over.
      final before = widget.practice.items.length;
      for (final seed in result.practice) {
        await widget.practice.maybeCollect(seed.move, setupUci: seed.setupUci);
      }
      final puzzles = widget.practice.items.length - before;

      if (!mounted) return;
      if (result.games.isEmpty) {
        setState(() {
          _busy = false;
          _error = result.skipped > 0
              ? 'Nothing new — all ${result.skipped} of those are already here.'
              : 'No analysed games found for "${result.username}".';
        });
        return;
      }
      Navigator.pop(context, (
        games: result.games.length,
        puzzles: puzzles,
        skipped: result.skipped,
      ));
    } on LichessImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Import failed — $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title: const Text('Import from lichess', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your ANALYSED games, with the grades lichess already computed — '
              'labels, accuracy, best moves. Every mistake in them is added to '
              'Practice. Games the server never analysed are skipped.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _busy ? null : _run(),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
              cursorColor: const Color(0xFF81B64C),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'lichess username',
                labelStyle:
                    const TextStyle(fontSize: 12, color: Colors.white38),
                errorText: _error,
                errorMaxLines: 3,
                isDense: true,
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3a3733))),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF81B64C))),
              ),
            ),
            const SizedBox(height: 12),
            // Wrap, not Row: at 375px with the text scaled up the label and
            // the dropdown do not fit on one line, and a Row would overflow.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                const Text('Most recent',
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
                DropdownButton<int>(
                  value: _max,
                  isDense: true,
                  dropdownColor: const Color(0xFF1f1e1b),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                  underline: const SizedBox.shrink(),
                  onChanged:
                      _busy ? null : (v) => setState(() => _max = v ?? _max),
                  items: const [10, 50, 100, kMaxGames]
                      .map((n) => DropdownMenuItem(
                          value: n, child: Text('$n games')))
                      .toList(),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Color(0xFF2c2a26),
                  color: Color(0xFF81B64C)),
              const SizedBox(height: 6),
              Text(_seen > 0 ? 'Read $_seen games — grading…' : _stage,
                  style:
                      const TextStyle(fontSize: 11.5, color: Colors.white38)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF81B64C),
            foregroundColor: const Color(0xFF161512),
          ),
          child: Text(_busy ? 'Importing…' : 'Import'),
        ),
      ],
    );
  }
}
