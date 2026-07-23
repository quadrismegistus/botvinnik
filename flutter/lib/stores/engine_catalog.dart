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

/// One selectable playing style of an engine, chosen per game by sending a UCI
/// option before the search. The engine binary is shared across styles;
/// strength stays a separate UCI_Elo dial, so every style shares the engine's
/// [EngineCatalogEntry.elo] and dials over the same range. Two shapes:
///  - a STYLE FILE the engine loads (Rodent's `PersonalityFile value tal.txt`),
///    which also ships as a bundled [file] laid beside the binary on install;
///  - a plain OPTION toggle (BrainLearn's `MCTS value true`), no data file.
@immutable
class EnginePersonality {
  /// Display name of the style (e.g. `Tal`, `MCTS`).
  final String name;

  /// One-line description of how it plays, for the roster.
  final String blurb;

  /// A bundled data file to install beside the binary (Rodent's style file), or
  /// null for a style selected by a plain option (BrainLearn's MCTS toggle).
  final String? file;

  final String? _optionName;
  final String? _optionValue;
  final String? _key;

  /// A style backed by a loadable FILE (Rodent): `PersonalityFile value <file>`,
  /// with [file] bundled and copied beside the binary on install.
  const EnginePersonality.file(this.file, this.name, this.blurb)
      : _optionName = null,
        _optionValue = null,
        _key = null;

  /// A style selected by a plain UCI option (BrainLearn's `MCTS` toggle).
  const EnginePersonality.option(
      String key, this.name, this.blurb, String option, String value)
      : _key = key,
        _optionName = option,
        _optionValue = value,
        file = null;

  /// The persona-id suffix after `custom-<engine>~` (e.g. `tal`, `mcts`).
  String get key =>
      _key ??
      (file!.endsWith('.txt') ? file!.substring(0, file!.length - 4) : file!);

  /// The UCI option to send before each search, WITHOUT the leading
  /// `setoption name ` — e.g. `PersonalityFile value tal.txt` or `MCTS value true`.
  String get setoption =>
      file != null ? 'PersonalityFile value $file' : '$_optionName value $_optionValue';
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

  /// Named playing styles, when the engine is one that loads them (Rodent IV).
  /// Empty for an ordinary single-style engine. When present, one install of
  /// the shared binary becomes this many browsable opponents, each a style over
  /// the same strength dial. File-backed styles are bundled and laid out beside
  /// the binary on install (Rodent finds them relative to itself).
  final List<EnginePersonality> personalities;

  /// Extra files downloaded and placed beside the binary on install, keyed by
  /// the exact filename the engine expects (Arasan's NNUE net, which it loads
  /// from beside itself at runtime). Non-empty implies an own-dir install.
  final Map<String, EngineBuild> dataFiles;

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
    this.personalities = const [],
    this.dataFiles = const {},
  });

  /// This engine installs into its own directory (binary + data beside it) when
  /// something must sit next to the binary — downloaded data files (Arasan's
  /// net) or file-backed styles (Rodent). A plain-option style engine
  /// (BrainLearn's MCTS toggle) needs no dir and installs flat.
  bool get ownDir =>
      dataFiles.isNotEmpty || personalities.any((p) => p.file != null);

  /// The cap range rounded to whole hundreds, for a friendly 100-step slider —
  /// an engine whose floor is 1320 shows 1300. A picked value is mapped back
  /// into [eloMin]..[eloMax] by [clampElo] before it reaches the engine, so the
  /// label stays round while the engine gets a value it can actually honour.
  int get capSliderMin => (eloMin / 100).round() * 100;
  int get capSliderMax => (eloMax / 100).round() * 100;
  int clampElo(int shown) => shown.clamp(eloMin, eloMax);

  EngineBuild? buildFor(String? platformKey) =>
      platformKey == null ? null : builds[platformKey];
}

/// The families whose members are an engine's named styles (one binary, many
/// browsable personas) — Rodent, BrainLearn. Each equals the engine's catalog
/// id. Used by the pickers to group them like the retro sub-list.
Set<String> get styleFamilies =>
    {for (final e in kEngineCatalog) if (e.personalities.isNotEmpty) e.id};

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
  EngineCatalogEntry(
    id: 'rodent',
    name: 'Rodent IV',
    description:
        'A characterful engine by Pawel Koziol that plays in 36 named styles — '
        "from Tal's sacrifices to Petrosian's restraint — each dialable "
        'from 800 to 2800.',
    author: 'Pawel Koziol',
    license: 'GPL-3.0',
    sourceUrl: 'https://github.com/nescitus/rodent-iv',
    // Rodent IV is ~2600 at full strength; every style shares that and dials
    // down over the same UCI_Elo range — the style is character, not strength.
    elo: 2600,
    version: 'iv-0.33',
    capsElo: true,
    eloMin: 800,
    eloMax: 2800,
    builds: {
      // No upstream binaries at all; we host a CI-compiled, ad-hoc-signed arm64
      // build on botvinnik-engines. The style files ship bundled (see pubspec).
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/quadrismegistus/botvinnik-engines/releases/download/rodent-iv-0.33-ge8d84c8c8c18/rodent-iv-0.33-ge8d84c8c8c18-macos-arm64',
        sha256:
            'fb843ab6d0ccace7a49873fc44c6126f9e40b1611dc770d7260c4f924a79e6d5',
        sizeBytes: 280416,
      ),
    },
    personalities: [
      EnginePersonality.file('tal.txt', 'Tal', 'The Magician of Riga — relentless sacrifices and chaos.'),
      EnginePersonality.file('petrosian.txt', 'Petrosian', 'Defensive artistry; closed positions and exchange sacs.'),
      EnginePersonality.file('botvinnik.txt', 'Botvinnik', 'Balanced and structural; cares for the pawns.'),
      EnginePersonality.file('fischer.txt', 'Fischer', 'Attacking and uncompromising; raises mobility for both sides.'),
      EnginePersonality.file('kasparov.txt', 'Kasparov', 'Dynamic aggression and attacking initiative.'),
      EnginePersonality.file('karpov.txt', 'Karpov', 'Positional restraint and the slow squeeze.'),
      EnginePersonality.file('morphy.txt', 'Morphy', 'Rapid development and open-game attacks.'),
      EnginePersonality.file('anderssen.txt', 'Anderssen', 'Romantic-era attacker who sacrifices for the initiative.'),
      EnginePersonality.file('alekhine.txt', 'Alekhine', 'Aggressive and active, in love with the bishops.'),
      EnginePersonality.file('nimzowitsch.txt', 'Nimzowitsch', 'Hypermodern: blockade, overprotection, restraint.'),
      EnginePersonality.file('lasker.txt', 'Lasker', 'A practical fighter who plays the position, not the book.'),
      EnginePersonality.file('steinitz.txt', 'Steinitz', 'Accepts cramped positions and sacrifices; solid with pawns.'),
      EnginePersonality.file('tarrasch.txt', 'Tarrasch', 'Classical: mobility, bishops, the open game.'),
      EnginePersonality.file('reti.txt', 'Réti', 'Hypermodern; disregards classical placement, solid pawns.'),
      EnginePersonality.file('rubinstein.txt', 'Rubinstein', 'Classical technique with an endgame lean.'),
      EnginePersonality.file('spassky.txt', 'Spassky', 'Universal and defensive; grabs space and guards pawns.'),
      EnginePersonality.file('kortchnoi.txt', 'Kortchnoi', 'Combative — grabs material and defends it.'),
      EnginePersonality.file('larsen.txt', 'Larsen', 'Tricky and provocative, after Nimzowitsch.'),
      EnginePersonality.file('marshall.txt', 'Marshall', 'Swindles and attacking gambits — after Frank Marshall.'),
      EnginePersonality.file('anand.txt', 'Anand', 'Quick and universal — a homage to Vishy Anand.'),
      EnginePersonality.file('topalov.txt', 'Topalov', 'Sharp and forcing, with active pieces.'),
      EnginePersonality.file('bosboom.txt', 'Bosboom', "Wild and inventive, a blitz attacker's spirit."),
      EnginePersonality.file('pawnsacker.txt', 'Pawnsacker', 'Holds pawns lightly — gives them up for play.'),
      EnginePersonality.file('spitfire.txt', 'Spitfire', 'Fast and fierce — attack at all costs.'),
      EnginePersonality.file('strangler.txt', 'Strangler', 'Squeezes the life out of the position.'),
      EnginePersonality.file('swapper.txt', 'Swapper', 'Trades pieces and heads for a draw.'),
      EnginePersonality.file('defender.txt', 'Defender', 'Solid and defensive above all.'),
      EnginePersonality.file('partisan.txt', 'Partisan', 'Stealthy openings, then a sudden attack.'),
      EnginePersonality.file('dynamic.txt', 'Dynamic', 'An attacker with the bishops, willing to sacrifice.'),
      EnginePersonality.file('preston.txt', 'Preston', 'A materialistic, moderate attacker.'),
      EnginePersonality.file('cloe.txt', 'Cloe', 'Likes closed positions.'),
      EnginePersonality.file('deborah.txt', 'Deborah', 'Defensive, and fond of the bishops.'),
      EnginePersonality.file('pedrita.txt', 'Pedrita', 'Pawns, defence, restraint.'),
      EnginePersonality.file('amanda.txt', 'Amanda', 'Attacker first, mobility second.'),
      EnginePersonality.file('grumpy.txt', 'Grumpy', 'Contrary and hard to please.'),
      EnginePersonality.file('ampere.txt', 'Ampère', 'Brisk and energetic, always for activity.'),
    ],
  ),
  EngineCatalogEntry(
    id: 'arasan',
    name: 'Arasan',
    description:
        'An independent engine by Jon Dart, developed since 1994 — its own '
        'evaluation, not a Stockfish derivative, so it plays with a different '
        'grain. Dials from 1000 to 3450.',
    author: 'Jon Dart',
    license: 'MIT',
    sourceUrl: 'https://github.com/jdart1/arasan-chess',
    elo: 3450,
    version: 'gc7d86c8',
    capsElo: true,
    eloMin: 1000,
    eloMax: 3450,
    builds: {
      // No upstream macOS build (distributed off-GitHub); we host a CI-signed
      // arm64 build. Arasan loads its net from beside the binary at runtime.
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/quadrismegistus/botvinnik-engines/releases/download/arasan-gc7d86c8/arasan-gc7d86c8-macos-arm64',
        sha256:
            '65999e8ccae8e3f1cb596f007e33b519c8c1622150431580305033ad0fe85c84',
        sizeBytes: 856384,
      ),
    },
    dataFiles: {
      // The NNUE net, laid beside the binary under the exact name the build
      // compiled in (it loads `arasanv8-20260622.nnue` from its own dir).
      'arasanv8-20260622.nnue': EngineBuild(
        url:
            'https://github.com/quadrismegistus/botvinnik-engines/releases/download/arasan-gc7d86c8/arasanv8-20260622.nnue',
        sha256:
            'b42f9e13a37debb4af425d2ca74b5edff1d8034a616806bccdb67b79530201ac',
        sizeBytes: 25024576,
      ),
    },
  ),
  EngineCatalogEntry(
    id: 'brainlearn',
    name: 'BrainLearn',
    description:
        'A Stockfish fork by amchess with a toggleable Monte-Carlo search — '
        'play it in the classic alpha-beta style, or in a more exploratory '
        'MCTS mode. Dials from 1320 to 3190.',
    author: 'amchess',
    license: 'GPL-3.0',
    sourceUrl: 'https://github.com/amchess/BrainLearn',
    elo: 3400,
    version: 'gc9fe18fc',
    capsElo: true,
    eloMin: 1320,
    eloMax: 3190,
    builds: {
      'macos-arm64': EngineBuild(
        url:
            'https://github.com/quadrismegistus/botvinnik-engines/releases/download/brainlearn-gc9fe18fc/brainlearn-gc9fe18fc-macos-arm64',
        sha256:
            'd90bfb25440770a5b0ace1671514691f9c68dceee17776454e3aa3046af5c3b4',
        sizeBytes: 79443376,
      ),
    },
    // Two "styles" that flip its search mode — no data file, just a UCI option.
    personalities: [
      EnginePersonality.option('classic', 'Classic',
          'Alpha-beta search — cold, exact, Stockfish-style calculation.',
          'MCTS', 'false'),
      EnginePersonality.option('mcts', 'MCTS',
          'Monte-Carlo tree search — a more exploratory, AlphaZero-ish feel.',
          'MCTS', 'true'),
    ],
  ),
];
