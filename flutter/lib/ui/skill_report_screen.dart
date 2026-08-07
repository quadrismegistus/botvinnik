// The skill report (#268): the player's own axes — tactics, keeping a won
// game, defending a worse one, the endgame, and the clock — beside the same
// axes pooled from 56M lichess games at the player's own band (tactics
// instead compares against Maia-3's per-position estimate: the dumps carry
// no best lines, so that axis has no table to read). brain/report.ts and
// reportTactics.ts compute every number; this file only asks for them, gates
// on sample size, and says what it is looking at.
//
// HONESTY RULES, load-bearing and non-negotiable (see report.ts's own header
// for why): the peer tables pool MOVES, not players, so nothing here ever
// says "percentile" — only mean-vs-mean, worded "the typical N (class)". An
// axis renders a comparison only once the player's own sample clears a floor;
// below it the card says how few moves it has rather than guessing past them.
// A band/class with no peer cell says so instead of inventing one.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../brain/report_api.dart';
import '../stores/maia_tactics_sweep.dart';
import '../stores/player_rating_store.dart';
import '../stores/review_controller.dart';

/// The peer table's bands (flutter/assets/peer-tables.json), 800 to 2600.
const List<int> kSkillReportBands = [
  800,
  900,
  1000,
  1100,
  1200,
  1300,
  1400,
  1500,
  1600,
  1700,
  1800,
  1900,
  2000,
  2100,
  2200,
  2300,
  2400,
  2500,
  2600,
];

const List<String> kSkillReportTimeClasses = ['blitz', 'rapid', 'classical'];

/// Sample floors below which a comparison is noise, not a verdict (#268
/// contract). The eval floor gates each of the three eval cards on the
/// player's own move count; the time floors gate the clock card the same way,
/// with the panic/calm row needing its own (smaller) floor on top, since it
/// is a rarer bucket than "any clocked move".
const int kEvalFloor = 50;
const int kClockedFloor = 100;
const int kPanicFloor = 20;

/// The tactics card's floor is on POSITIONS, not moves — tactical positions
/// are maybe one move in twenty, so demanding [kEvalFloor] of them would keep
/// the card dark for months. 30 found/missed shots is where a rate stops
/// being three coin flips in a trenchcoat.
const int kTacticsFloor = 30;

class SkillReportScreen extends StatefulWidget {
  /// How the peer tables are read. Defaults to the real bundled asset; a test
  /// swaps this for a Future that resolves with no real file I/O — the same
  /// injection seam as GamesListBody's `saveFile`/`importApi`
  /// (ui/games_list.dart), and for the same reason: a widget test's fake
  /// clock cannot drive a genuine `rootBundle.loadString` disk read to
  /// completion (see skill_report_test.dart's `_pump`).
  final Future<String> Function() loadTables;

  SkillReportScreen({super.key, Future<String> Function()? loadTables})
      : loadTables = loadTables ??
            (() => rootBundle.loadString('assets/peer-tables.json'));

  @override
  State<SkillReportScreen> createState() => _SkillReportScreenState();
}

class _SkillReportScreenState extends State<SkillReportScreen> {
  int _band = 1500;
  String _timeClass = 'blitz';

  Map<String, dynamic>? _tables;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _peer;
  bool _loading = true;

  /// Why the report could not load, or null. The failure screen renders this
  /// with a Retry — a permanent spinner is indistinguishable from a hang.
  String? _error;

  @override
  void initState() {
    super.initState();
    _band = _defaultBand();
    _load();
  }

  /// The same source pickBot reads for its "near your level" marker
  /// (roster_picker.dart) — but REFRESHED first, in [_load]: the store's only
  /// other refresh site is the game-over recap, so on the ordinary path
  /// (launch app, open Games, tap the report) `rating` is still null and
  /// every player would default to 1500 regardless of strength (#293
  /// review). When even a refresh yields no estimate (fewer than the
  /// estimator's minimum rated games), 1500 is the stand-in, not a guess
  /// dressed up as one.
  int _defaultBand() {
    final elo = context.read<PlayerRatingStore>().rating?.elo;
    if (elo == null) return 1500;
    // FLOOR, not round: the pipeline's bandFor floors, so the 1500 cell
    // holds players rated 1500–1599. Rounding defaulted half of all ratings
    // into the neighbouring population (#293 review).
    final floored = (elo ~/ 100) * 100;
    return floored.clamp(kSkillReportBands.first, kSkillReportBands.last);
  }

  Future<void> _load() async {
    // One catch covers the asset read, the JSON decode and the bridge walk:
    // any of them failing used to strand the screen on a spinner forever —
    // reachable on web with nothing corrupt, by opening the report offline
    // before the 624KB table asset was ever fetched (#293 review).
    // The rating refresh gets its own guard: no estimate (or a fit that
    // throws) is a default-band situation, never a failed report.
    try {
      await context.read<PlayerRatingStore>().refresh();
    } catch (_) {/* the 1500 stand-in covers it */}
    if (!mounted) return;
    try {
      final band = _defaultBand();
      final raw = await widget.loadTables();
      if (!mounted) return;
      final tables = (jsonDecode(raw) as Map).cast<String, dynamic>();
      // The envelope pins which brain computed it; a mismatch means the two
      // sides of every comparison were produced by different win-chance code
      // — refuse, never silently mix (#293 review: the field was written and
      // nothing ever read it).
      final built = (tables['brainVersion'] as num?)?.toInt();
      final running = context.read<ReportApi>().brainVersion();
      if (built != running) {
        throw StateError(
            'peer tables were built by brain v$built; this app runs v$running');
      }
      setState(() {
        _band = band;
        _tables = tables;
        _computeUser();
        _computePeer();
        _loading = false;
        _error = null;
      });
      // The tactics card's peer half: start (or resume) the Maia sweep over
      // the archive's tactical positions. Fire-and-forget — the card renders
      // its progress from the store as answers land.
      unawaited(context.read<MaiaTacticsSweep>().ensureStarted());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Projects the archive down to the report contract's fields once per call
  /// — see [reportGameProjection] for why the whole stored shape never
  /// crosses the bridge — and asks the brain to walk it. Depends only on
  /// [_timeClass]: the population a game falls into (won/lost/endgame/panic)
  /// is decided move-by-move inside that walk, not by which band is selected.
  void _computeUser() {
    final games = context.read<ReviewController>().games;
    final projected = [for (final g in games) reportGameProjection(g)];
    _user = context.read<ReportApi>().skillReportUser(projected, _timeClass);
    // The tactics selection is NOT computed here: the selector costs ~0.5ms
    // of synchronous bridge time per stored ply, which on a real archive is
    // SECONDS of platform-thread freeze (#294 review, measured 19s at 500
    // games). MaiaTacticsSweep walks it one game per call in the background
    // and publishes the merged result; the card reads that.
  }

  /// The peer cell for the current band × class, or null when the table has
  /// none — [_tables] is loaded exactly once ([_load]) and reused for every
  /// dropdown change from here on.
  void _computePeer() {
    final tables = _tables;
    _peer = tables == null
        ? null
        : context
            .read<ReportApi>()
            .skillReportPeer(tables, _band, _timeClass);
  }

  void _onBandChanged(int? band) {
    if (band == null || band == _band) return;
    setState(() {
      _band = band;
      _computePeer();
    });
  }

  void _onTimeClassChanged(String? cls) {
    if (cls == null || cls == _timeClass) return;
    setState(() {
      _timeClass = cls;
      _computeUser();
      _computePeer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skill report')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not load the report: $_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white38, height: 1.4),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _load();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _body(),
    );
  }

  Widget _body() {
    final user = _user!;
    final peer = _peer;
    // watch, not read: the card redraws as the sweep's answers land.
    final sweep = context.watch<MaiaTacticsSweep>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        _header(),
        const SizedBox(height: 14),
        _TacticsCard(
          sweep: sweep,
          band: _band,
          timeClass: _timeClass,
        ),
        _EvalAxisCard(
          title: 'Keeping a won game',
          user: (user['winning'] as Map).cast<String, dynamic>(),
          peer: _peerAxis(peer, 'winning'),
          band: _band,
          timeClass: _timeClass,
        ),
        _EvalAxisCard(
          title: 'Defence when worse',
          user: (user['losing'] as Map).cast<String, dynamic>(),
          peer: _peerAxis(peer, 'losing'),
          band: _band,
          timeClass: _timeClass,
        ),
        _EvalAxisCard(
          title: 'Endgame',
          user: (user['endgame'] as Map).cast<String, dynamic>(),
          peer: _peerAxis(peer, 'endgame'),
          band: _band,
          timeClass: _timeClass,
        ),
        _TimeAxisCard(
          user: (user['time'] as Map).cast<String, dynamic>(),
          peer: peer == null ? null : (peer['time'] as Map).cast<String, dynamic>(),
          band: _band,
          timeClass: _timeClass,
        ),
        const SizedBox(height: 10),
        _footer(user),
      ],
    );
  }

  Map<String, dynamic>? _peerAxis(Map<String, dynamic>? peer, String key) {
    if (peer == null) return null;
    final axis = peer[key];
    if (axis == null) return null;
    final cast = (axis as Map).cast<String, dynamic>();
    // The SAME floor the user side answers to (#293 review: the README
    // promised floors on every cell and the code gated only the user's n —
    // 800/classical rendered a panic rate from 58 peer moves as "Typical").
    // A too-thin peer axis renders as "no baseline", never as a confident
    // number.
    final n = (cast['n'] as num?)?.toInt() ?? 0;
    return n < kEvalFloor ? null : cast;
  }

  Widget _header() => Row(
        children: [
          const Text('Band', style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(width: 6),
          DropdownButton<int>(
            value: _band,
            isDense: true,
            dropdownColor: const Color(0xFF1f1e1b),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
            underline: const SizedBox.shrink(),
            onChanged: _onBandChanged,
            items: [
              for (final b in kSkillReportBands)
                DropdownMenuItem(value: b, child: Text('$b')),
            ],
          ),
          const SizedBox(width: 20),
          const Text('Time class',
              style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(width: 6),
          DropdownButton<String>(
            value: _timeClass,
            isDense: true,
            dropdownColor: const Color(0xFF1f1e1b),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
            underline: const SizedBox.shrink(),
            onChanged: _onTimeClassChanged,
            items: [
              for (final c in kSkillReportTimeClasses)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
          ),
        ],
      );

  /// The population line (honesty rule c) and the provenance line (rule e).
  /// Both read straight off what the brain and the table actually said —
  /// nothing here is a constant.
  Widget _footer(Map<String, dynamic> user) {
    final games = (user['games'] as Map).cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Computed from ${games['considered']} games · excluded: '
            '${games['humanless']} no human side, ${games['otherClass']} '
            'other time class, ${games['noClass']} no time control.',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Text(_provenance(_tables?['source'] as String?),
              style: const TextStyle(fontSize: 11, color: Colors.white30)),
        ],
      ),
    );
  }

  /// "lichess_db_standard_rated_2026-07" → "Peer baseline: lichess open
  /// database, July 2026." Falls back to the raw source string, and then to
  /// no date at all, rather than fabricate a month the table did not give.
  String _provenance(String? source) {
    if (source == null) return 'Peer baseline: lichess open database.';
    final m = RegExp(r'(\d{4})-(\d{2})$').firstMatch(source);
    if (m == null) return 'Peer baseline: lichess open database ($source).';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final year = m.group(1)!;
    final month = int.parse(m.group(2)!);
    return 'Peer baseline: lichess open database, ${months[month - 1]} $year.';
  }
}

/// The shared card shell — insight_card.dart's `_CardShell` colours, a title
/// on top of whatever the axis has to say.
class _AxisShell extends StatelessWidget {
  final String title;
  final Widget child;
  const _AxisShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF262421),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

Widget _notEnoughText(String unit, int n) => Text(
      'Not enough $unit in this slice yet — $n so far.',
      style: const TextStyle(fontSize: 12, color: Colors.white38),
    );

/// "Tactics": of the positions where the engine's move carried a tactical
/// motif, how often the player PLAYED that move — beside Maia-3's estimate of
/// how often a typical player at the selected band finds the same shots, on
/// these SAME positions (reportTactics.ts selects; MaiaTacticsSweep answers).
///
/// The peer column here is MODEL-DERIVED, unlike every other card's, and is
/// badged as such — "Maia's typical N", never "typical N (class)", never a
/// percentile. Where Maia cannot run (iPhone Safari's WASM ceiling) the card
/// says so and stands absolute-only; while the sweep is still working it
/// shows progress, not a mean over whatever happened to be swept first.
class _TacticsCard extends StatelessWidget {
  final MaiaTacticsSweep sweep;
  final int band;
  final String timeClass;

  const _TacticsCard({
    required this.sweep,
    required this.band,
    required this.timeClass,
  });

  @override
  Widget build(BuildContext context) {
    // Everything on this card comes from the sweep — selection, user numbers,
    // peer curves alike (#294 review: two sources for "which positions is
    // this axis made of" is how a stuck state becomes permanent).
    final tactics = sweep.tactics;
    if (tactics == null) {
      return _AxisShell(
        title: 'Tactics',
        child: Text(
          sweep.maiaUsable
              ? 'Reading your games…'
              : 'Reading your games… (no Maia baseline on this device)',
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
      );
    }
    final by = ((tactics['byClass'] as Map)[timeClass] as Map)
        .cast<String, dynamic>();
    final n = (by['n'] as num?)?.toInt() ?? 0;
    // The exclusion counts render in EVERY state — below the floor they ARE
    // the explanation for why the slice is thin (#294 review: "not enough
    // positions" while 200 games sat excluded said nothing).
    final ungraded = (by['noTopGames'] as num?)?.toInt() ?? 0;
    final assisted = (by['assistedGames'] as num?)?.toInt() ?? 0;
    return _AxisShell(
      title: 'Tactics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n < kTacticsFloor)
            _notEnoughText('tactical positions', n)
          else
            _comparison(tactics, n, (by['found'] as num?)?.toInt() ?? 0),
          if (ungraded > 0) ...[
            const SizedBox(height: 6),
            Text(
              // "without top-move records", not "not yet graded": lichess-
              // analysed imports are labelled and will never be regraded
              // under current rules (#297) — "yet" would be a promise.
              'Excludes $ungraded $timeClass games without top-move records.',
              style: const TextStyle(fontSize: 11, color: Colors.white30),
            ),
          ],
          if (assisted > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Excludes $assisted $timeClass games with assistance '
              '(hints, takebacks, or refusals).',
              style: const TextStyle(fontSize: 11, color: Colors.white30),
            ),
          ],
        ],
      ),
    );
  }

  /// The slice's cache keys, occurrences included: the user side counts a
  /// repeated position every time it was faced, so the peer mean must weight
  /// it the same way.
  List<String> _sliceKeys(Map<String, dynamic> tactics) => [
        for (final p in (tactics['positions'] as List))
          if ((p as Map)['cls'] == timeClass) p['key'] as String,
      ];

  Widget _comparison(Map<String, dynamic> tactics, int n, int found) {
    final userRate = found / n;
    final keys = _sliceKeys(tactics);
    final covered = sweep.coveredOf(keys);
    // The refusal of a partial mean lives in ONE place — peerFoundRate
    // answers null until every key is covered; the card only narrates the
    // progress that explains the null.
    final peerRate = sweep.peerFoundRate(keys, band);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _rateColumn('You', userRate, '$found of $n found')),
            const SizedBox(width: 12),
            Expanded(child: _peerColumn(keys.length, covered, peerRate)),
          ],
        ),
        // maiaUsable gates the verdict too: a seeded-but-unusable state must
        // not say "not available on this device" in one column and quote
        // Maia in the sentence below it (#294 review).
        if (peerRate != null && sweep.maiaUsable) ...[
          const SizedBox(height: 6),
          Text(_verdict(userRate, peerRate),
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ],
    );
  }

  /// Whole percents, honest at the edges: 199 of 200 is "99%", never the
  /// false absolute "100%" that toStringAsFixed(0) prints (#294 review) —
  /// 0% and 100% are reserved for exactly none and exactly all.
  static String _pct(double rate) {
    if (rate <= 0) return '0%';
    if (rate >= 1) return '100%';
    final rounded = (rate * 100).round();
    if (rounded <= 0) return '<1%';
    if (rounded >= 100) return '>99%';
    return '$rounded%';
  }

  Widget _rateColumn(String label, double rate, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          Text(_pct(rate),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      );

  Widget _peerColumn(int total, int covered, double? peerRate) {
    final label = "Maia's typical $band";
    if (!sweep.maiaUsable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          const Text('not available on this device',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      );
    }
    if (peerRate == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          Text('analysing your positions… $covered of $total',
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      );
    }
    // The estimate IS class-sliced (these are the slice's own positions)
    // even though Maia's rung is not — say which positions, so switching
    // classes changing the number reads as the feature it is.
    return _rateColumn(label, peerRate, 'model estimate, these $timeClass positions');
  }

  /// Model-attributed wording, never a percentile: this is Maia's expected
  /// find-rate on the very positions the player faced, and the sentence says
  /// whose estimate it is every time.
  String _verdict(double userRate, double peerRate) {
    final diff = userRate - peerRate;
    if (diff.abs() < 0.02) {
      return "you find these about as often as Maia's typical $band";
    }
    return diff > 0
        ? "you find these shots more often than Maia's typical $band"
        : "you find these shots less often than Maia's typical $band";
  }
}

/// "Keeping a won game" / "Defence when worse" / "Endgame": the brain's
/// `{n, mean, blunderRate}` shape, user beside peer, with a one-line verdict
/// comparing the two means. Below the sample floor the comparison is withheld
/// outright — the floor is on the USER'S n; the peer table pools millions of
/// moves and is never the scarce side of this comparison.
class _EvalAxisCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> user;
  final Map<String, dynamic>? peer;
  final int band;
  final String timeClass;

  const _EvalAxisCard({
    required this.title,
    required this.user,
    required this.peer,
    required this.band,
    required this.timeClass,
  });

  @override
  Widget build(BuildContext context) {
    final n = (user['n'] as num?)?.toInt() ?? 0;
    return _AxisShell(
      title: title,
      child: n < kEvalFloor ? _notEnoughText('moves', n) : _comparison(),
    );
  }

  Widget _comparison() {
    final userMean = (user['mean'] as num?)?.toDouble();
    final userRate = (user['blunderRate'] as num?)?.toDouble();
    final peerMean = (peer?['mean'] as num?)?.toDouble();
    final peerRate = (peer?['blunderRate'] as num?)?.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _statColumn('You', userMean, userRate)),
            const SizedBox(width: 12),
            Expanded(
              child: peer == null
                  ? _noBaseline()
                  : _statColumn(
                      'Typical $band ($timeClass)', peerMean, peerRate),
            ),
          ],
        ),
        if (peer != null && userMean != null && peerMean != null) ...[
          const SizedBox(height: 6),
          Text(_verdict(userMean, peerMean),
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ],
    );
  }

  Widget _statColumn(String label, double? mean, double? rate) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          Text(mean == null ? '—' : '${mean.toStringAsFixed(1)} pts/move',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(
              rate == null
                  ? '—'
                  : '${(rate * 100).toStringAsFixed(1)}% blunder rate',
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      );

  Widget _noBaseline() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Typical $band ($timeClass)',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          const Text('no baseline for this band/class',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      );

  /// "you leak less/more than the typical N (class)" — never a percentile,
  /// only this mean against that mean. `mean` is the win-chance points given
  /// away per move, so a SMALLER number is the better one.
  String _verdict(double userMean, double peerMean) {
    final diff = userMean - peerMean;
    if (diff.abs() < 0.05) {
      return 'about the same as the typical $band ($timeClass)';
    }
    return diff < 0
        ? 'you leak less than the typical $band ($timeClass)'
        : 'you leak more than the typical $band ($timeClass)';
  }
}

/// "Clock discipline": under-2s move share, and panic-vs-calm blunder rates,
/// user beside peer. Two floors, not one — [kClockedFloor] gates the whole
/// card (there is nothing to say about clock use with barely any clocked
/// moves), and [kPanicFloor] additionally gates the panic/calm row, which
/// draws from a narrower slice (moves under 30s or over 60s) than "any
/// clocked move" and can starve well after the card itself clears its floor.
class _TimeAxisCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic>? peer;
  final int band;
  final String timeClass;

  const _TimeAxisCard({
    required this.user,
    required this.peer,
    required this.band,
    required this.timeClass,
  });

  @override
  Widget build(BuildContext context) {
    final clocked = (user['clockedMoves'] as num?)?.toInt() ?? 0;
    return _AxisShell(
      title: 'Clock discipline',
      child: clocked < kClockedFloor
          ? _notEnoughText('clocked moves', clocked)
          : _body(),
    );
  }

  Widget _body() {
    final userUnder2s = (user['under2sShare'] as num?)?.toDouble();
    final peerUnder2s = (peer?['under2sShare'] as num?)?.toDouble();
    final userPanic = (user['panic'] as Map).cast<String, dynamic>();
    final userCalm = (user['calm'] as Map).cast<String, dynamic>();
    final peerPanic = peer == null ? null : (peer!['panic'] as Map).cast<String, dynamic>();
    final peerCalm = peer == null ? null : (peer!['calm'] as Map).cast<String, dynamic>();
    final panicN = (userPanic['n'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _line('You: moves under 2s',
                  userUnder2s == null ? '—' : '${(userUnder2s * 100).toStringAsFixed(1)}%'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _line(
                'Typical $band ($timeClass)',
                peer == null
                    ? 'no baseline for this band/class'
                    : (peerUnder2s == null
                        ? '—'
                        : '${(peerUnder2s * 100).toStringAsFixed(1)}%'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (panicN < kPanicFloor)
          _notEnoughText('panic-clock moves', panicN)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Blunder rate under time pressure',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _pressureColumn('You', userPanic, userCalm)),
                  const SizedBox(width: 12),
                  Expanded(
                    // The peer's panic bucket answers to the same floor the
                    // user's does (#293 review): a sparse classical cell held
                    // panic n=58, and a rate off 58 moves is noise wearing a
                    // "Typical" label.
                    child: peer == null ||
                            ((peerPanic?['n'] as num?)?.toInt() ?? 0) <
                                kPanicFloor
                        ? _line('Typical $band ($timeClass)',
                            'no baseline for this band/class')
                        : _pressureColumn(
                            'Typical $band ($timeClass)', peerPanic!, peerCalm!),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _line(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 2),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _pressureColumn(
      String label, Map<String, dynamic> panic, Map<String, dynamic> calm) {
    final pRate = (panic['pBlunder'] as num?)?.toDouble();
    final cRate = (calm['pBlunder'] as num?)?.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
        const SizedBox(height: 2),
        Text('panic ${pRate == null ? '—' : '${(pRate * 100).toStringAsFixed(1)}%'}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        Text('calm ${cRate == null ? '—' : '${(cRate * 100).toStringAsFixed(1)}%'}',
            style: const TextStyle(fontSize: 13, color: Colors.white54)),
      ],
    );
  }
}
