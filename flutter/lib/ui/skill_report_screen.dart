// The skill report (#268): the player's own axes — keeping a won game,
// defending a worse one, the endgame, and the clock — beside the same axes
// pooled from 56M lichess games at the player's own band. brain/report.ts
// computes every number; this file only asks for them, gates on sample size,
// and says what it is looking at.
//
// HONESTY RULES, load-bearing and non-negotiable (see report.ts's own header
// for why): the peer tables pool MOVES, not players, so nothing here ever
// says "percentile" — only mean-vs-mean, worded "the typical N (class)". An
// axis renders a comparison only once the player's own sample clears a floor;
// below it the card says how few moves it has rather than guessing past them.
// A band/class with no peer cell says so instead of inventing one.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../brain/report_api.dart';
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

  @override
  void initState() {
    super.initState();
    _band = _defaultBand();
    _load();
  }

  /// The same source pickBot reads for its "near your level" marker
  /// (roster_picker.dart): read, not refit. This screen does not force a
  /// rating fit just to seed a dropdown default — when there is no estimate
  /// yet (fewer than the estimator's minimum rated games), 1500 is the stand-
  /// in, not a guess dressed up as one.
  int _defaultBand() {
    final elo = context.read<PlayerRatingStore>().rating?.elo;
    if (elo == null) return 1500;
    final rounded = (elo / 100).round() * 100;
    return rounded.clamp(kSkillReportBands.first, kSkillReportBands.last);
  }

  Future<void> _load() async {
    final raw = await widget.loadTables();
    if (!mounted) return;
    setState(() {
      _tables = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _computeUser();
      _computePeer();
      _loading = false;
    });
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
      body: _loading ? const Center(child: CircularProgressIndicator()) : _body(),
    );
  }

  Widget _body() {
    final user = _user!;
    final peer = _peer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        _header(),
        const SizedBox(height: 14),
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
    return axis == null ? null : (axis as Map).cast<String, dynamic>();
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
                    child: peer == null
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
