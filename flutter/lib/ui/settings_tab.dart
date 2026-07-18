// The Settings tab. Small on purpose — settings that belong to a specific
// flow (opponent, side) live in that flow's sheet; this is for the app-wide
// knobs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/practice_controller.dart';
import '../stores/settings_store.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final practice = context.watch<PracticeController>();
    final belowThreshold = practice.items.length - practice.servable.length;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
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
        ListTile(
          dense: true,
          title: const Text('Collected puzzles'),
          subtitle: Text(
            '${practice.items.length} total · ${practice.servable.length} above the bar · ${practice.due} due',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
        ),
      ],
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
