import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../stores/backup.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';
import '../sync/sync_controller.dart';

// The app's lichess-green accent, matching the game-over recap button.
const Color _accent = Color(0xFF81B64C);

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _phrase = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    // Seed the field with a fresh suggestion the first time we show the setup
    // form (not in initState — it needs the provider).
    if (!sync.enabled && !_seeded) {
      _phrase.text = sync.suggestPhrase();
      _seeded = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync across devices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          const Text(
            'Your games and practice sync privately across your devices. '
            'The server stores only encrypted data it cannot read, and there '
            'are no accounts — a device joins by entering the same phrase.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          if (sync.enabled) _enabled(context, sync) else _setup(context, sync),
        ],
      ),
    );
  }

  // ---- setup (sync off) ----

  Widget _setup(BuildContext context, SyncController sync) {
    final advice = sync.advise(_phrase.text);
    final busy = sync.status.phase == SyncPhase.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Sync phrase',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 6),
        TextField(
          controller: _phrase,
          onChanged: (_) => setState(() {}),
          enabled: !busy,
          minLines: 1,
          maxLines: 2,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: 'Suggest a new phrase',
              icon: const Icon(Icons.casino_outlined),
              onPressed: busy
                  ? null
                  : () => setState(() => _phrase.text = sync.suggestPhrase()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(advice.strong ? Icons.check_circle_outline : Icons.info_outline,
                size: 15, color: advice.strong ? _accent : Colors.amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(advice.message,
                  style: TextStyle(
                      fontSize: 12,
                      color: advice.strong ? _accent : Colors.amber)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'This phrase is the encryption key — there is no reset. Save it in '
          'your password manager: lose it and the data is gone, leak it and '
          "it's readable.",
          style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white38),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: busy || _phrase.text.trim().isEmpty
              ? null
              : () => _enable(context, sync),
          child: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Turn on sync'),
        ),
      ],
    );
  }

  Future<void> _enable(BuildContext context, SyncController sync) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final reload = _reloader(context); // capture controllers before the await
    await sync.enable(_phrase.text);
    await reload(sync.status.lastPulled);
    if (sync.status.phase == SyncPhase.error) {
      messenger?.showSnackBar(
          SnackBar(content: Text(sync.status.message ?? 'Sync failed.')));
    }
  }

  // ---- enabled ----

  Widget _enabled(BuildContext context, SyncController sync) {
    final busy = sync.status.phase == SyncPhase.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: _accent),
            const SizedBox(width: 8),
            const Text('Sync is on',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Your sync phrase',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(sync.phrase ?? '',
                    style: const TextStyle(fontSize: 15, height: 1.3)),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sync.phrase ?? ''));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Phrase copied')));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Enter this phrase on your other devices to sync them.',
            style: TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(_statusIcon(sync.status.phase),
                size: 15, color: _statusColor(sync.status.phase)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_statusLine(sync.status),
                  style: TextStyle(
                      fontSize: 12.5, color: _statusColor(sync.status.phase))),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _accent),
          onPressed: busy ? null : () => _syncNow(context, sync),
          icon: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync, size: 18),
          label: Text(busy ? 'Syncing…' : 'Sync now'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : () => _disable(context, sync),
          child: const Text('Turn off sync on this device',
              style: TextStyle(color: Colors.white54)),
        ),
        const Text(
          'Turning off keeps the synced copy for your other devices; '
          're-enter the phrase to rejoin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.white30),
        ),
      ],
    );
  }

  Future<void> _syncNow(BuildContext context, SyncController sync) async {
    final reload = _reloader(context); // capture controllers before the await
    final counts = await sync.syncNow();
    await reload(counts);
  }

  Future<void> _disable(BuildContext context, SyncController sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off sync?'),
        content: const Text(
            'This device will stop syncing and forget the phrase. Your synced '
            'data stays safe for your other devices.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off')),
        ],
      ),
    );
    if (ok == true) {
      await sync.disable();
      if (mounted) setState(() => _seeded = false); // reseed the setup form
    }
  }

  /// Capture the Practice/Review controllers up front, then return a closure
  /// that reloads them if a pull actually brought anything in. A pull writes
  /// underneath both controllers, so — exactly as restore does — they must
  /// re-read or the tabs keep showing the pre-sync lists until restart. Reading
  /// the controllers before any await keeps `context` off the async gap.
  Future<void> Function(BackupCounts?) _reloader(BuildContext context) {
    final practice = context.read<PracticeController>();
    final review = context.read<ReviewController>();
    return (pulled) async {
      if (pulled == null || (pulled.games == 0 && pulled.practice == 0)) return;
      await practice.load();
      await review.loadGames();
    };
  }

  IconData _statusIcon(SyncPhase p) => switch (p) {
        SyncPhase.ok => Icons.check_circle_outline,
        SyncPhase.syncing => Icons.sync,
        SyncPhase.offline => Icons.cloud_off_outlined,
        SyncPhase.error => Icons.error_outline,
        _ => Icons.schedule,
      };

  Color _statusColor(SyncPhase p) => switch (p) {
        SyncPhase.ok => _accent,
        SyncPhase.error => Colors.redAccent,
        SyncPhase.offline => Colors.amber,
        _ => Colors.white54,
      };

  String _statusLine(SyncStatus s) {
    switch (s.phase) {
      case SyncPhase.syncing:
        return 'Syncing…';
      case SyncPhase.offline:
        return s.message ?? 'Offline.';
      case SyncPhase.error:
        return 'Error: ${s.message ?? 'sync failed'}';
      case SyncPhase.ok:
        final pulled = s.lastPulled;
        final when = s.lastSyncedAt == null ? '' : ' ${_ago(s.lastSyncedAt!)}';
        if (pulled != null && (pulled.games > 0 || pulled.practice > 0)) {
          return 'Synced$when · pulled ${pulled.games} games, '
              '${pulled.practice} puzzles.';
        }
        return 'Synced$when.';
      default:
        return 'On. Not synced yet.';
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
