// The About section of Settings: the in-app half of GPL-3.0 compliance.
//
// The App Store posture (issue #76) rests on good-faith compliance — the
// source public and linked from inside the app, and the licence text and
// third-party notices travelling with the binary. This surfaces both: a link
// to the repo, and the bundled `LICENSE` / `THIRD-PARTY-NOTICES.md` shown
// verbatim and offline (they have to be available with no network, not only
// via the source link). The bundled copies are kept in sync with the repo-root
// originals by `stage-legal.sh`, guarded in CI.

import 'package:flutter/material.dart';

import 'layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const _repo = 'https://github.com/quadrismegistus/botvinnik';
  static const _subtle = TextStyle(fontSize: 11.5, color: Colors.white38);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => ListTile(
            dense: true,
            title: const Text('botvinnik'),
            subtitle: Text(
              snap.hasData
                  ? 'version ${snap.data!.version} (${snap.data!.buildNumber})'
                  : 'a chess trainer that explains itself',
              style: _subtle,
            ),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.code, size: 20, color: Colors.white54),
          title: const Text('Source code'),
          subtitle: const Text(
            'github.com/quadrismegistus/botvinnik — this app is free software',
            style: _subtle,
          ),
          trailing:
              const Icon(Icons.open_in_new, size: 16, color: Colors.white38),
          onTap: () => launchUrl(Uri.parse(_repo),
              mode: LaunchMode.externalApplication),
        ),
        ListTile(
          dense: true,
          leading:
              const Icon(Icons.gavel_outlined, size: 20, color: Colors.white54),
          title: const Text('License'),
          subtitle: const Text('GNU General Public License v3.0 or later',
              style: _subtle),
          onTap: () => _openLegal(context, 'License', 'assets/legal/LICENSE'),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.list_alt_outlined,
              size: 20, color: Colors.white54),
          title: const Text('Third-party notices'),
          subtitle: const Text('the engines and libraries this is built on',
              style: _subtle),
          onTap: () => _openLegal(context, 'Third-party notices',
              'assets/legal/THIRD-PARTY-NOTICES.md'),
        ),
      ],
    );
  }

  void _openLegal(BuildContext context, String title, String asset) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LegalTextScreen(title: title, asset: asset),
    ));
  }
}

/// A bundled licence/notice file, shown verbatim and scrollable. Reads from the
/// asset bundle, so it works with no network — which is the point: the licence
/// has to be available offline, not only via the source link.
class LegalTextScreen extends StatelessWidget {
  const LegalTextScreen({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: insetAppBar(context, AppBar(title: Text(title))),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString(asset),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snap.data!,
              style: const TextStyle(
                  fontSize: 12, height: 1.4, fontFamily: 'monospace'),
            ),
          );
        },
      ),
    );
  }
}
