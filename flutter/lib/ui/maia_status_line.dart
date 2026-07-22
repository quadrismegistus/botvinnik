// One line of Maia load state, for the New Game sheet and the roster picker.
//
// A bar while the weights download and the runtime compiles, a quiet "ready"
// once it can play, and — the reason this widget exists — the actual FAILURE
// with its reason when it cannot, so a Stockfish stand-in on a phone stops
// being a silent mystery. Idle renders nothing.

import 'package:flutter/material.dart';

import '../stores/maia_status.dart';

class MaiaStatusLine extends StatelessWidget {
  final MaiaBandState state;
  final String name;
  const MaiaStatusLine({super.key, required this.state, required this.name});

  static const _green = Color(0xFF81B64C);
  static const _amber = Color(0xFFE0A030);

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case MaiaPhase.idle:
      case MaiaPhase.ready:
        // Ready is the normal, silent state — a chosen bot that can play needs
        // no annotation. Idle likewise: nothing has been asked of it yet.
        return const SizedBox.shrink();

      case MaiaPhase.downloading:
      case MaiaPhase.starting:
        final p = state.progress!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(58, 4, 8, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.describe(name),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  // A real bar when the server gave a length, indeterminate
                  // (the compile) otherwise.
                  value: p.fraction,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(_green),
                ),
              ),
            ],
          ),
        );

      case MaiaPhase.failed:
        final raw = (state.error ?? '').toLowerCase();
        // The one failure with a real explanation and no fix on this device:
        // mobile Safari's WebAssembly memory ceiling, which ort-web hits as
        // "out of memory" / "no available backend". Say what it means and where
        // Maia does run, rather than dumping the raw error at a player.
        final outOfMemory = raw.contains('out of memory') ||
            raw.contains('no available backend');
        final text = outOfMemory
            ? 'This browser ran out of memory for $name’s neural net — mobile '
                'Safari caps it. Playing as a Stockfish stand-in; the desktop '
                'site runs the real Maia.'
            : 'Couldn’t load $name’s neural net — playing as a Stockfish '
                'stand-in.\n${state.error}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(58, 4, 8, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 5),
                child: Icon(Icons.error_outline, size: 13, color: _amber),
              ),
              Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 11.5, color: _amber)),
              ),
            ],
          ),
        );
    }
  }
}
