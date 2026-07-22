// The Custom engines settings section: list the player's added UCI engines,
// and add / edit / remove them. Desktop only (a browser cannot run a binary),
// so the caller gates it on CustomEngineRunner.supported.
//
// The binary is a typed path for now — simple, and it works on an unsandboxed
// desktop build. A native file picker (which also grants a sandbox security
// scope) is the obvious follow-up.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../stores/custom_engine.dart';

class CustomEnginesSection extends StatelessWidget {
  const CustomEnginesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomEngineStore>();
    return Column(
      children: [
        for (final e in store.engines)
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
            onTap: () => _edit(context, store, e),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add, size: 20),
          title: const Text('Add an engine…'),
          subtitle: const Text(
            'Any UCI engine binary — it joins the roster as an opponent.',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          onTap: () => _edit(context, store, null),
        ),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, CustomEngineStore store, CustomEngine? existing) async {
    final result = await showDialog<CustomEngine>(
      context: context,
      builder: (_) => _EngineDialog(existing: existing),
    );
    if (result != null) await store.upsert(result);
  }
}

class _EngineDialog extends StatefulWidget {
  final CustomEngine? existing;
  const _EngineDialog({this.existing});

  @override
  State<_EngineDialog> createState() => _EngineDialogState();
}

class _EngineDialogState extends State<_EngineDialog> {
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

  bool get _valid => _name.text.trim().isNotEmpty && _path.text.trim().isNotEmpty;

  void _save() {
    Navigator.pop(
      context,
      CustomEngine(
        id: widget.existing?.id ?? CustomEngineStore.newId(),
        name: _name.text.trim(),
        path: _path.text.trim(),
        elo: _elo,
        movetimeMs: _movetime,
        limitElo: _limitElo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              // A path can be long; wrap and allow paste of an absolute path.
              decoration: const InputDecoration(
                labelText: 'Engine binary (full path)',
                hintText: '/usr/local/bin/viridithas',
              ),
              keyboardType: TextInputType.url,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Rating', style: TextStyle(color: Colors.white70)),
                const Spacer(),
                Text('$_elo',
                    style: const TextStyle(color: Color(0xFF81B64C))),
              ],
            ),
            Slider(
              value: _elo.toDouble().clamp(500, 3500),
              min: 500,
              max: 3500,
              divisions: 30,
              label: '$_elo',
              onChanged: (v) => setState(() => _elo = v.round()),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Cap strength to the rating',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Sends UCI_Elo. Only works if the engine supports it — full '
                'strength otherwise.',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              value: _limitElo,
              onChanged: (v) => setState(() => _limitElo = v),
            ),
            Row(
              children: [
                const Text('Move time', style: TextStyle(color: Colors.white70)),
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
