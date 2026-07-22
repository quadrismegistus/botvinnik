// Import your games from chess.com by username (#166).
//
// Beside the lichess import rather than instead of it: the two accounts are
// different histories, and chess.com is a different fetch — archive-per-month,
// dozens of requests for a real history, so this dialog shows which month it is
// on and how fast it is going, and its Cancel stops the walk rather than only
// closing the box.
//
// What it does NOT do is seed practice. chess.com serves no per-move evals, so
// the games arrive UNGRADED (see brain/chesscomCore.ts): an archive, not a
// graded history. Accuracy, blunders and practice fill in when a background job
// analyses them (#170). Claiming a seeded queue here would be a lie.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brain/chesscom_import_api.dart';
import '../stores/review_controller.dart';

/// What the caller needs to say afterwards. Null when the dialog was cancelled
/// before anything was written, or failed — nothing was saved.
typedef CcImportSummary = ({int games, int skipped, bool cancelled});

/// Opens the dialog and returns what it imported, or null.
Future<CcImportSummary?> showChesscomImport(BuildContext context,
        {ChesscomImportApi? api}) =>
    showDialog<CcImportSummary>(
      context: context,
      builder: (_) => _ChesscomImportDialog(
        api: api,
        review: context.read<ReviewController>(),
      ),
    );

class _ChesscomImportDialog extends StatefulWidget {
  /// Injected by tests; otherwise read from the tree when the dialog opens —
  /// the same injection seam the lichess dialog uses, and the reason a test can
  /// drive the whole walk without a network or a JS host.
  final ChesscomImportApi? api;
  final ReviewController review;

  const _ChesscomImportDialog({required this.api, required this.review});

  @override
  State<_ChesscomImportDialog> createState() => _ChesscomImportDialogState();
}

class _ChesscomImportDialogState extends State<_ChesscomImportDialog> {
  final _name = TextEditingController();
  int _max = kDefaultMaxGames;
  String? _error;
  bool _busy = false;

  /// Flipped by the Cancel button while the walk is running; the api polls it
  /// between requests. Kept in the state rather than passed as a token so the
  /// button and the walk read the one flag.
  bool _cancelRequested = false;

  /// The live progress line, built from [CcImportProgress].
  String _stage = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _error = null;
      _stage = 'Reading chess.com…';
    });
    final api = widget.api ?? context.read<ChesscomImportApi>();
    try {
      // The archive is the dedupe key, and the Review tab may never have been
      // opened this session — so load it rather than trusting memory, or a
      // re-import would announce games it then overwrote.
      await widget.review.loadGames();
      final existing =
          widget.review.games.map((g) => g['id'] as String).toSet();

      final result = await api.importGames(
        username: _name.text,
        existingIds: existing,
        max: _max,
        isCancelled: () => _cancelRequested,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _stage = _progressLine(p));
        },
      );

      if (!mounted) return;
      setState(() => _stage = 'Saving ${result.games.length}…');
      for (final game in result.games) {
        await widget.review.db.saveGame(game);
      }
      await widget.review.loadGames();

      if (!mounted) return;
      if (result.games.isEmpty) {
        setState(() {
          _busy = false;
          _error = result.cancelled
              ? 'Cancelled — nothing imported yet.'
              : result.skipped > 0
                  ? 'Nothing new — all ${result.skipped} of those are already here.'
                  : 'No games found for "${result.username}".';
        });
        return;
      }
      Navigator.pop(context, (
        games: result.games.length,
        skipped: result.skipped,
        cancelled: result.cancelled,
      ));
    } on ChesscomImportException catch (e) {
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

  /// The progress line: which month, how many in, and the rate once it means
  /// something. ASCII plus the two allowed marks — no glyph that would be a
  /// webfont fetch.
  String _progressLine(CcImportProgress p) {
    if (_cancelRequested) return 'Cancelling…';
    if (p.monthsTotal == 0) return 'Reading chess.com…';
    final month = p.currentMonth.isEmpty ? '' : ' · ${p.currentMonth}';
    final rate =
        p.gamesPerMin >= 1 ? ' · ${p.gamesPerMin.toStringAsFixed(0)}/min' : '';
    return 'Month ${p.monthsDone}/${p.monthsTotal}$month'
        ' — ${p.gamesAdded} imported$rate';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title:
          const Text('Import from chess.com', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your chess.com games, archived. chess.com serves no move-by-move '
              'analysis, so these arrive without grades yet — no accuracy, '
              'blunders or practice positions until they are analysed.',
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
                labelText: 'chess.com username',
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
            // Wrap, not Row: at 375px with the text scaled up the label and the
            // dropdown do not fit on one line, and a Row would overflow.
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
              Text(_stage,
                  style:
                      const TextStyle(fontSize: 11.5, color: Colors.white38)),
            ],
          ],
        ),
      ),
      actions: [
        // While the walk runs this stops it; idle, it closes the dialog. One
        // button, because a second "close" during a live import is the thing a
        // user reaches for when they mean "stop".
        TextButton(
          onPressed: _busy
              ? (_cancelRequested
                  ? null
                  : () => setState(() => _cancelRequested = true))
              : () => Navigator.pop(context),
          child: Text(_busy ? 'Cancel import' : 'Cancel'),
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
