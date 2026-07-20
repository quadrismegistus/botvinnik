// Paste a PGN to bring a game into the archive.
//
// Paste rather than file-upload: a PGN is copied off lichess or chess.com as
// text, and a file picker would be a new dependency on every platform for the
// rarer half of the job. Upload can follow if it is ever asked for.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/review_controller.dart';

Future<void> showPgnImport(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => _PgnImportDialog(review: context.read<ReviewController>()),
    );

class _PgnImportDialog extends StatefulWidget {
  final ReviewController review;
  const _PgnImportDialog({required this.review});

  @override
  State<_PgnImportDialog> createState() => _PgnImportDialogState();
}

class _PgnImportDialogState extends State<_PgnImportDialog> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final pgn = _text.text.trim();
    if (pgn.isEmpty) {
      setState(() => _error = 'Paste a PGN first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.review.importPgn(pgn);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context); // the review opens on the imported game
      return;
    }
    setState(() {
      _busy = false;
      _error = 'No legal moves in that PGN';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title: const Text('Import PGN', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a game. It is archived and opens in Review — imports carry '
              'no engine grades, since nothing has analysed them.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(fontSize: 12.5, color: Colors.white70),
              cursorColor: const Color(0xFF81B64C),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: '[Event "..."]\n\n1. e4 e5 2. Nf3 ...',
                hintStyle:
                    const TextStyle(fontSize: 11.5, color: Colors.white24),
                errorText: _error,
                isDense: true,
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3a3733))),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF81B64C))),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
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
