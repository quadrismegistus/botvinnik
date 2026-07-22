// A curated catalog of downloadable UCI engines (issue #183).
//
// Each entry points at an engine's OWN official release assets — we link and
// install, we do not host or redistribute the binary — with a pinned SHA-256
// per platform so the installer can refuse anything that does not match what
// was vetted. Every entry carries its licence and source URL: good citizenship
// for the local download here, and exactly what AGPL §13 will require for any
// engine offered from the Phase 2 server.

import 'package:flutter/foundation.dart';

@immutable
class EngineBuild {
  /// The upstream release asset, downloaded on demand.
  final String url;

  /// Lowercase hex SHA-256 of the asset. The install is aborted on a mismatch —
  /// the trust anchor for downloading an executable.
  final String sha256;

  final int sizeBytes;

  const EngineBuild({
    required this.url,
    required this.sha256,
    this.sizeBytes = 0,
  });
}

@immutable
class EngineCatalogEntry {
  final String id;
  final String name;
  final String description;
  final String author;

  /// SPDX identifier, shown to the player and (Phase 2) the anchor for the
  /// §13 source offer.
  final String license;
  final String sourceUrl;

  /// Approximate full-strength rating, for display and as the default when the
  /// player caps it with UCI_Elo.
  final int elo;
  final String version;

  /// Platform key → build. Keys: `macos-arm64`, `macos-x64`, `linux-x64`,
  /// `linux-arm64`, `windows-x64`. A missing key means no prebuilt binary is
  /// published for that platform (so it is offered nowhere it cannot run).
  final Map<String, EngineBuild> builds;

  const EngineCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.license,
    required this.sourceUrl,
    required this.elo,
    required this.version,
    required this.builds,
  });

  EngineBuild? buildFor(String? platformKey) =>
      platformKey == null ? null : builds[platformKey];
}

/// The engines offered for one-tap download. Checksums are the upstream ones,
/// verified by hand against the release assets page before pinning.
const List<EngineCatalogEntry> kEngineCatalog = [
  EngineCatalogEntry(
    id: 'viridithas',
    name: 'Viridithas',
    description:
        'A top-tier open-source NNUE engine by Cosmo Bobak — far above human '
        'strength at full power; cap it with a rating to make it playable.',
    author: 'Cosmo Bobak',
    license: 'AGPL-3.0',
    sourceUrl: 'https://github.com/cosmobobak/viridithas',
    elo: 3500,
    version: '20.0.0',
    builds: {
      // macOS ships Apple Silicon only for v20 — there is no Intel-mac asset.
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/cosmobobak/viridithas/releases/download/v20.0.0/viridithas-20-macos-aarch64',
        sha256:
            '9ab84379f0241d94f926666eef8385ab032c585bb3055f27a3fbae423b75fd41',
        sizeBytes: 56911872,
      ),
      // x86-64-v3 (AVX2+BMI2): the broadly-compatible modern-x86 build, not the
      // v4 (AVX-512) one that only newer CPUs run.
      'linux-x64': EngineBuild(
        url:
            'https://github.com/cosmobobak/viridithas/releases/download/v20.0.0/viridithas-20-linux-x86-64-v3',
        sha256:
            'eb53de2fde546f3ba294407e3e8986dc3859bb1818f2ef4cf2fd85d077779973',
        sizeBytes: 57800608,
      ),
      'linux-arm64': EngineBuild(
        url:
            'https://github.com/cosmobobak/viridithas/releases/download/v20.0.0/viridithas-20-linux-aarch64-generic',
        sha256:
            'd8870b63517c7033754728b53130a0749cbc96d46d83fbbb2b4a448191044ea9',
        sizeBytes: 56430832,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/cosmobobak/viridithas/releases/download/v20.0.0/viridithas-20-win-x86-64-v3.exe',
        sha256:
            'c7fa86b2b46fe1c34b0ea3715ad3b4a61d3d984ec63d50b1d6b4f187332fbc51',
        sizeBytes: 56549376,
      ),
    },
  ),
];
