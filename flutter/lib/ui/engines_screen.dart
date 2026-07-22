// The Engines manager (issue #183, desktop only): download a catalogued engine
// with one tap, or add any UCI binary already on the machine by path. Pushed
// from Settings rather than living in a tab — it is configuration, and it is
// desktop-only, so it does not belong in the primary nav.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/engine_installer.dart';
import '../stores/custom_engine.dart';
import '../stores/engine_catalog.dart';

class EnginesScreen extends StatefulWidget {
  const EnginesScreen({super.key});

  @override
  State<EnginesScreen> createState() => _EnginesScreenState();
}

class _EnginesScreenState extends State<EnginesScreen> {
  /// Catalog id → (bytesReceived, bytesTotal) while a download is in flight.
  final Map<String, (int, int)> _downloading = {};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomEngineStore>();
    final catalogIds = {for (final e in kEngineCatalog) e.id};
    // Manually-added engines only; a catalog engine already shows in its own
    // section, with install state, so listing it here too would double it.
    final yours =
        store.engines.where((e) => !catalogIds.contains(e.id)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      appBar: AppBar(
        title: const Text('Engines'),
        backgroundColor: const Color(0xFF1f1e1b),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _Label('Download an engine'),
          for (final entry in kEngineCatalog) _CatalogTile(
            entry: entry,
            installedEngine: _installed(store, entry.id),
            progress: _downloading[entry.id],
            onDownload: () => _download(store, entry),
            onRemove: () => _remove(store, entry),
            onEdit: (e) => _addOrEdit(store, e),
          ),
          const _Label('Your engines'),
          if (yours.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Text('Nothing added by hand yet.',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
            ),
          for (final e in yours)
            ListTile(
              dense: true,
              leading: const Icon(Icons.terminal, size: 20),
              title: Text('${e.name}  ·  ${e.elo}'),
              subtitle: Text(
                e.limitElo ? '${e.path} · capped to ${e.elo}' : e.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.white38),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Remove',
                onPressed: () => store.remove(e.id),
              ),
              onTap: () => _addOrEdit(store, e),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 20),
            title: const Text('Add an engine by path…'),
            subtitle: const Text(
              'Any UCI binary already on this machine.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            onTap: () => _addOrEdit(store, null),
          ),
        ],
      ),
    );
  }

  CustomEngine? _installed(CustomEngineStore store, String catalogId) {
    for (final e in store.engines) {
      if (e.id == catalogId) return e;
    }
    return null;
  }

  Future<void> _download(
      CustomEngineStore store, EngineCatalogEntry entry) async {
    final build = entry.buildFor(EngineInstaller.platformKey);
    if (build == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final hasStyles = entry.personalities.isNotEmpty;
    setState(() => _downloading[entry.id] = (0, build.sizeBytes));
    try {
      final path = await EngineInstaller.install(
        entry.id,
        build,
        ownDir: hasStyles,
        onProgress: (r, t) {
          if (mounted) setState(() => _downloading[entry.id] = (r, t));
        },
      );
      if (hasStyles) {
        // Lay the bundled style files beside the binary (Rodent reads them
        // relative to itself). basic.ini marks the home dir; the rest are the
        // styles the catalog offers. Read here (cross-platform rootBundle),
        // written by the io installer.
        final names = ['basic.ini', for (final p in entry.personalities) p.file];
        final files = <String, List<int>>{};
        for (final n in names) {
          final d = await rootBundle.load('assets/${entry.id}/personalities/$n');
          files[n] = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
        }
        await EngineInstaller.writeStyleFiles(entry.id, files);
      }
      await store.upsert(CustomEngine(
        id: entry.id,
        name: entry.name,
        path: path,
        elo: entry.elo,
      ));
      messenger.showSnackBar(SnackBar(content: Text('Installed ${entry.name}')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not install ${entry.name}: $e')));
    } finally {
      if (mounted) setState(() => _downloading.remove(entry.id));
    }
  }

  Future<void> _remove(
      CustomEngineStore store, EngineCatalogEntry entry) async {
    await store.remove(entry.id);
    await EngineInstaller.uninstall(entry.id,
        ownDir: entry.personalities.isNotEmpty);
  }

  Future<void> _addOrEdit(
      CustomEngineStore store, CustomEngine? existing) async {
    final result = await showDialog<CustomEngine>(
      context: context,
      builder: (_) => EngineFormDialog(existing: existing),
    );
    if (result != null) await store.upsert(result);
  }
}

class _CatalogTile extends StatelessWidget {
  final EngineCatalogEntry entry;

  /// The store entry once downloaded, or null. Non-null means installed, and
  /// carries the editable strength (rating / UCI_Elo cap / move time).
  final CustomEngine? installedEngine;
  final (int, int)? progress;
  final VoidCallback onDownload;
  final VoidCallback onRemove;
  final void Function(CustomEngine) onEdit;

  const _CatalogTile({
    required this.entry,
    required this.installedEngine,
    required this.progress,
    required this.onDownload,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final build = entry.buildFor(EngineInstaller.platformKey);
    final installed = installedEngine;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.terminal, size: 20),
      title: Text('${entry.name}  ·  ${entry.elo}'),
      isThreeLine: true,
      // Once installed, the row opens the strength editor — the one place to
      // cap a superhuman engine's Elo or change its move time.
      onTap: installed == null ? null : () => onEdit(installed),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.description,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
          if (installed != null) ...[
            const SizedBox(height: 3),
            Text(
              !entry.capsElo
                  ? 'Installed · full strength (no rating cap)'
                  : installed.limitElo
                      ? 'Playing at ${installed.elo} — tap to change'
                      : 'Full strength — tap to cap its rating',
              style: const TextStyle(fontSize: 11, color: Color(0xFF81B64C)),
            ),
          ],
          const SizedBox(height: 3),
          // Licence + a link to source: citizenship for the local install, and
          // the anchor AGPL §13 will need for the Phase 2 server.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${entry.license} · ',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white38)),
              InkWell(
                onTap: () => launchUrl(Uri.parse(entry.sourceUrl),
                    mode: LaunchMode.externalApplication),
                child: const Text('source',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF81B64C),
                        decoration: TextDecoration.underline)),
              ),
              Text('  · v${entry.version}',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ],
      ),
      trailing: _trailing(context, build),
    );
  }

  Widget _trailing(BuildContext context, EngineBuild? build) {
    if (progress != null) {
      final (received, total) = progress!;
      final frac = total > 0 ? received / total : null;
      return SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: frac,
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF81B64C)),
            ),
            const SizedBox(height: 3),
            Text(
              frac != null ? '${(frac * 100).round()}%' : 'downloading…',
              style: const TextStyle(fontSize: 10.5, color: Colors.white54),
            ),
          ],
        ),
      );
    }
    if (installedEngine != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: Color(0xFF81B64C)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      );
    }
    if (build == null) {
      return const Text('no build\nfor this Mac',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 10.5, color: Colors.white38));
    }
    return FilledButton.tonal(
      onPressed: onDownload,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Text('Get · ${(build.sizeBytes / 1048576).round()}MB'),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                color: Colors.white38,
                fontWeight: FontWeight.w600)),
      );
}

/// Add or edit a hand-added engine — name, binary path, rating, move time, and
/// the optional UCI_Elo cap. Returns the [CustomEngine] to save, or null.
class EngineFormDialog extends StatefulWidget {
  final CustomEngine? existing;
  const EngineFormDialog({super.key, this.existing});

  @override
  State<EngineFormDialog> createState() => _EngineFormDialogState();
}

class _EngineFormDialogState extends State<EngineFormDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _path =
      TextEditingController(text: widget.existing?.path ?? '');
  late int _elo = widget.existing?.elo ?? 1500;
  late int _movetime = widget.existing?.movetimeMs ?? 1000;
  late bool _limitElo = widget.existing?.limitElo ?? false;

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _path.text.trim().isNotEmpty;

  void _save() {
    // A catalogued engine verified NOT to support UCI_Elo can never be capped,
    // whatever a stale saved flag says — force it off so the label can't lie.
    final catalog = catalogEntryById(widget.existing?.id);
    final canCap = catalog == null || catalog.capsElo;
    Navigator.pop(
      context,
      CustomEngine(
        id: widget.existing?.id ?? CustomEngineStore.newId(),
        name: _name.text.trim(),
        path: _path.text.trim(),
        elo: _elo,
        movetimeMs: _movetime,
        limitElo: canCap && _limitElo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // What the catalog knows about THIS engine's strength limiter, if it is a
    // catalogued one. A hand-added binary (catalog == null) is an unknown, so
    // it keeps the hedged toggle; a catalogued engine gets the verified truth.
    final catalog = catalogEntryById(widget.existing?.id);
    final knownNoCap = catalog != null && !catalog.capsElo;
    final capsElo = catalog != null && catalog.capsElo;
    final ratingMin = capsElo ? catalog.eloMin : 500;
    final ratingMax = capsElo ? catalog.eloMax : 3500;

    return AlertDialog(
      backgroundColor: const Color(0xFF1f1e1b),
      title: Text(widget.existing == null ? 'Add engine' : 'Edit engine',
          style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'Viridithas'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'Engine binary (full path)',
                hintText: '/usr/local/bin/viridithas',
              ),
              keyboardType: TextInputType.url,
              inputFormatters: [
                FilteringTextInputFormatter.singleLineFormatter
              ],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Rating', style: TextStyle(color: Colors.white70)),
                const Spacer(),
                Text(knownNoCap ? '$_elo · full strength' : '$_elo',
                    style: const TextStyle(color: Color(0xFF81B64C))),
              ],
            ),
            // A rating slider only where the rating means something: a fixed
            // full-strength rating is not user-editable (editing it would just
            // mislabel a superhuman engine), so it is shown read-only above.
            if (!knownNoCap)
              Slider(
                value: _elo
                    .toDouble()
                    .clamp(ratingMin.toDouble(), ratingMax.toDouble()),
                min: ratingMin.toDouble(),
                max: ratingMax.toDouble(),
                divisions: ((ratingMax - ratingMin) / 100).round(),
                label: '$_elo',
                onChanged: (v) => setState(() => _elo = v.round()),
              ),
            if (knownNoCap)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'This engine has no rating limiter — it always plays at full '
                  'strength.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              )
            else
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cap strength to the rating',
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  capsElo
                      ? 'Sends UCI_Elo — this engine dials from $ratingMin to '
                          '$ratingMax.'
                      : 'Sends UCI_Elo. Only works if the engine supports it — '
                          'full strength otherwise.',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
                value: _limitElo,
                onChanged: (v) => setState(() => _limitElo = v),
              ),
            Row(
              children: [
                const Text('Move time',
                    style: TextStyle(color: Colors.white70)),
                const Spacer(),
                DropdownButton<int>(
                  value: _movetime,
                  underline: const SizedBox(),
                  items: const [100, 250, 500, 1000, 2000, 5000]
                      .map((ms) => DropdownMenuItem(
                            value: ms,
                            child: Text(ms < 1000
                                ? '${ms}ms'
                                : '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)}s'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _movetime = v ?? _movetime),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
