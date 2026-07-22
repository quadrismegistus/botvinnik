// A curated catalog of downloadable UCI engines (issue #183).
//
// Most entries point at an engine's OWN official release assets — we link and
// install, we do not host. The exception is an engine that ships no macOS build
// of its own (Patricia): for those we host a CI-compiled, ad-hoc-signed binary
// on the botvinnik-engines repo, still pinned by SHA-256, with sourceUrl kept on
// the upstream repo so the licence's source obligation stays satisfied there.
// Every build carries a pinned SHA-256 so the installer can refuse anything that
// does not match, and every entry its licence and source URL: good citizenship
// for the download, and what AGPL §13 will require for the Phase 2 server.

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

  /// Whether the engine actually implements `UCI_LimitStrength` + `UCI_Elo`,
  /// verified against its source. When false the UI offers NO rating cap: an
  /// engine that ignores `UCI_Elo` would otherwise show a slider that does
  /// nothing, so a "600" plays at full strength — the precise lie this removes.
  /// Most catalogued engines are full-strength-only; a cap is the exception.
  final bool capsElo;

  /// The advertised `UCI_Elo` spin range, meaningful only when [capsElo]. A cap
  /// slider spans exactly this. Engines that do cap tend to floor around 1225,
  /// so a slider starting lower would lie even for a supported engine.
  final int eloMin;
  final int eloMax;

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
    this.capsElo = false,
    this.eloMin = 0,
    this.eloMax = 0,
  });

  EngineBuild? buildFor(String? platformKey) =>
      platformKey == null ? null : builds[platformKey];
}

/// The catalog entry an installed engine came from, matched by id, or null for
/// a hand-added binary (whose id is a timestamp, never a catalog slug). This is
/// how the UI asks whether an installed engine can actually be capped.
EngineCatalogEntry? catalogEntryById(String? id) {
  if (id == null) return null;
  for (final e in kEngineCatalog) {
    if (e.id == id) return e;
  }
  return null;
}

/// The engines offered for one-tap download. Checksums are the upstream ones,
/// verified by hand against the release assets before pinning. `capsElo` is
/// likewise verified against each engine's source — only Velvet implements a
/// real strength limiter; the rest play full strength only.
const List<EngineCatalogEntry> kEngineCatalog = [
  EngineCatalogEntry(
    id: 'stormphrax',
    name: 'Stormphrax',
    description:
        'A top-tier open-source C++ NNUE engine by Ciekce — plays at full '
        'strength only; it has no built-in rating limiter.',
    author: 'Ciekce',
    license: 'GPL-3.0',
    sourceUrl: 'https://github.com/Ciekce/Stormphrax',
    elo: 3600,
    version: '8.0.0',
    builds: {
      // macOS ships Apple Silicon only (apple-m1) — no Intel-mac asset.
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/Ciekce/Stormphrax/releases/download/v8.0.0/stormphrax-8.0.0-apple-m1',
        sha256:
            '5e6078f102af5bdd69e1b38ae7843581717fb42f2d0fe8d75f20ef8d097b3207',
        sizeBytes: 57057112,
      ),
      // avx2-bmi2 (x86-64-v3): broadly-compatible modern x86, not the avx512 or
      // zen2 variants that fault on older/other CPUs.
      'linux-x64': EngineBuild(
        url:
            'https://github.com/Ciekce/Stormphrax/releases/download/v8.0.0/stormphrax-8.0.0-avx2-bmi2',
        sha256:
            '01aa7cfa6135a5ddd24ad80a85945b0b1c310d7f1f3fb41e3bea4951f38ef8f7',
        sizeBytes: 56785872,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/Ciekce/Stormphrax/releases/download/v8.0.0/stormphrax-8.0.0-avx2-bmi2.exe',
        sha256:
            'baf96b2a32c338f0bd3daa89f2fb6e7f6d0584e11843e52101d4b83128f8523c',
        sizeBytes: 57000448,
      ),
    },
  ),
  EngineCatalogEntry(
    id: 'viridithas',
    name: 'Viridithas',
    description:
        'A top-tier open-source NNUE engine by Cosmo Bobak — plays at full '
        'strength only; it has no built-in rating limiter.',
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
  EngineCatalogEntry(
    id: 'halogen',
    name: 'Halogen',
    description:
        'A strong open-source NNUE engine by Kieren Pearson — plays at full '
        'strength only; it has no built-in rating limiter.',
    author: 'Kieren Pearson',
    license: 'GPL-3.0',
    sourceUrl: 'https://github.com/KierenP/Halogen',
    elo: 3450,
    version: '16.0.0',
    builds: {
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/KierenP/Halogen/releases/download/v16/Halogen-16.0.0-macos-arm64-neon-dotprod',
        sha256:
            '374c1a5720d1ffc06809f3b6a08f4f80b43e1d3c026d6cb9bb8886b9d16aca82',
        sizeBytes: 19736680,
      ),
      // avx2, not the avx512/pext variants that only newer CPUs run.
      'macos-x64': EngineBuild(
        url:
            'https://github.com/KierenP/Halogen/releases/download/v16/Halogen-16.0.0-macos-x86_64-avx2',
        sha256:
            '2f6fe43945be3baf19bef2409b77f9e41b4edb50e965815486204d66a9715bbe',
        sizeBytes: 19615008,
      ),
      'linux-x64': EngineBuild(
        url:
            'https://github.com/KierenP/Halogen/releases/download/v16/Halogen-16.0.0-linux-x86_64-avx2',
        sha256:
            '26daae0d0c735319bde9b242b5a0855db396cf6737241f08a96e4e49e9bab942',
        sizeBytes: 26546464,
      ),
      'linux-arm64': EngineBuild(
        url:
            'https://github.com/KierenP/Halogen/releases/download/v16/Halogen-16.0.0-linux-arm64-neon-dotprod',
        sha256:
            '5e90bebe85766fb34cd6f37bafc97d57095947c74a9e0c544990d375a0ddedf5',
        sizeBytes: 26622768,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/KierenP/Halogen/releases/download/v16/Halogen-16.0.0-windows-x86_64-avx2.exe',
        sha256:
            'e780f98732d0161381406b51fc5446c237753b2615b86a88eb7c5ed2c2691d99',
        sizeBytes: 22377462,
      ),
    },
  ),
  EngineCatalogEntry(
    id: 'velvet',
    name: 'Velvet',
    description:
        'A strong open-source NNUE engine by mhonert — the one catalogued '
        'engine with a real strength limiter: dial it from 1225 to 3000.',
    author: 'mhonert',
    license: 'GPL-3.0',
    sourceUrl: 'https://github.com/mhonert/velvet-chess',
    elo: 3450,
    version: '8.1.1',
    capsElo: true,
    eloMin: 1225,
    eloMax: 3000,
    builds: {
      // Checksums are from the release's checksums.txt — the GitHub API exposes
      // no per-asset digest for this release.
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/mhonert/velvet-chess/releases/download/v8.1.1/velvet-v8.1.1-macOS-apple-silicon',
        sha256:
            '75af42bdfdef60f86385a5462ca4a0f4e66fdb5b4be3b1b208d22a30982f3d35',
        sizeBytes: 51663480,
      ),
      'macos-x64': EngineBuild(
        url:
            'https://github.com/mhonert/velvet-chess/releases/download/v8.1.1/velvet-v8.1.1-macOS-x86_64-avx2',
        sha256:
            'd125bc6494de1b0c522ba3e05f28b71ac280c4e52be3177f84abeef1f55855ca',
        sizeBytes: 51331056,
      ),
      'linux-x64': EngineBuild(
        url:
            'https://github.com/mhonert/velvet-chess/releases/download/v8.1.1/velvet-v8.1.1-x86_64-avx2',
        sha256:
            '33ead45675bb7fbe856c70c05a3a492e74ac01c54d359ae0d2e47b173452e3b4',
        sizeBytes: 51512480,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/mhonert/velvet-chess/releases/download/v8.1.1/velvet-v8.1.1-x86_64-avx2.exe',
        sha256:
            'b86fc64f30d76bad514934a71d473e15798e4f61dc85f183d81ff2a27c659a6b',
        sizeBytes: 51263488,
      ),
    },
  ),
  EngineCatalogEntry(
    id: 'reckless',
    name: 'Reckless',
    description:
        'A fast open-source Rust NNUE engine by codedeliveryservice — plays at '
        'full strength only; it has no built-in rating limiter.',
    author: 'codedeliveryservice',
    license: 'AGPL-3.0',
    sourceUrl: 'https://github.com/codedeliveryservice/Reckless',
    elo: 3400,
    version: '0.9.0',
    builds: {
      // macOS ships an Apple Silicon binary only; `reckless-macos` is
      // Mach-O arm64 (confirmed with `file`). No x86_64-mac asset is published.
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/codedeliveryservice/Reckless/releases/download/v0.9.0/reckless-macos',
        sha256:
            'b50eeea3519e7da0e583a255d9d9f86096c513384818e7f01b983c14026a6a0b',
        sizeBytes: 65329264,
      ),
      // avx2 (~x86-64-v3): the broadly-compatible modern-x86 build.
      'linux-x64': EngineBuild(
        url:
            'https://github.com/codedeliveryservice/Reckless/releases/download/v0.9.0/reckless-linux-avx2',
        sha256:
            '09ba1634faaffec55d237a7efecfb27d5152f6f1400f24dd63af9bde00a054f6',
        sizeBytes: 65004440,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/codedeliveryservice/Reckless/releases/download/v0.9.0/reckless-windows-avx2.exe',
        sha256:
            'b74ead5648cfa7a7a9f51d04566cf00f56dcf90dacd1252990906223bf1891b8',
        sizeBytes: 64664576,
      ),
    },
  ),
  EngineCatalogEntry(
    id: 'patricia',
    name: 'Patricia',
    description:
        'A deliberately aggressive open-source engine by Adam Kulju — it seeks '
        'sacrifices and attacks, and it dials all the way down from 3001 to 500.',
    author: 'Adam Kulju',
    license: 'MIT',
    sourceUrl: 'https://github.com/Adam-Kulju/Patricia',
    elo: 3400,
    version: '5',
    capsElo: true,
    eloMin: 500,
    eloMax: 3001,
    builds: {
      // No upstream macOS build, so we host a CI-compiled, ad-hoc-signed arm64
      // binary on botvinnik-engines (source of truth stays the upstream repo).
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/quadrismegistus/botvinnik-engines/releases/download/patricia-5/patricia-5-macos-arm64',
        sha256:
            'e48fbe22905ecc7fe4f0dd599ba842127f481ddeaf13c99a01d5b1689df7c5d9',
        sizeBytes: 3832992,
      ),
      // Linux/Windows: upstream's own x86-64-v3 builds, linked directly.
      'linux-x64': EngineBuild(
        url:
            'https://github.com/Adam-Kulju/Patricia/releases/download/5/patricia_v3',
        sha256:
            '29c382e24ff1310bdc8e16321d721ed62b1b8f247b016d7a14e24b2608fc936f',
        sizeBytes: 3825840,
      ),
      'windows-x64': EngineBuild(
        url:
            'https://github.com/Adam-Kulju/Patricia/releases/download/5/patricia_v3.exe',
        sha256:
            'd2d72fdee011781a9af3efe7bf5c0f71512257e7d4c93d85d391c1afcc2cf32c',
        sizeBytes: 4162560,
      ),
    },
  ),
];
