// botvinnik mobile — M1: the playable vertical slice.
// Shell (phone-first): board pinned top, grade strip, icon tabs, scrolling
// content pane, fixed bottom action bar.
//
// Boot order matters: brain.js (JS runtime) → native Stockfish → arbiter →
// settings → GameController. The engine singleton does not survive Dart hot
// restarts — cold-start the app after touching engine code.

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'brain/bot_api.dart';
import 'brain/chess_api.dart';
import 'brain/grading_api.dart';
import 'brain/js_bridge.dart';
import 'db/app_db.dart';
import 'engine/arbiter.dart';
import 'engine/search_engine.dart';
import 'stores/game_controller.dart';
import 'stores/review_controller.dart';
import 'stores/settings_store.dart';
import 'ui/action_bar.dart';
import 'ui/board_pane.dart';
import 'ui/games_list.dart';
import 'ui/review_screen.dart';
import 'ui/grade_strip.dart';
import 'ui/insight_card.dart';
import 'ui/move_list.dart';

void main() {
  runApp(const BootGate());
}

ThemeData _theme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF81B64C),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF161512),
    );

/// Async boot: JS brain + native engine + db, then the provider tree ABOVE
/// MaterialApp — pushed routes (archive, review) must see the providers.
class BootGate extends StatefulWidget {
  const BootGate({super.key});

  @override
  State<BootGate> createState() => _BootGateState();
}

class _Booted {
  final JsBridge bridge;
  final SearchArbiter arbiter;
  final SettingsStore settings;
  final ClassTable classTable;
  final AppDb db;
  _Booted(this.bridge, this.arbiter, this.settings, this.classTable, this.db);
}

class _BootGateState extends State<BootGate> {
  late final Future<_Booted> _boot = _start();

  Future<_Booted> _start() async {
    final bridge = await JsBridge.load();
    final engine = await SearchEngine.start();
    final arbiter = SearchArbiter(engine);
    final settings = await SettingsStore.load();
    final db = await AppDb.open();
    final classTable = ClassTable(GradingApi(bridge).classTable());
    return _Booted(bridge, arbiter, settings, classTable, db);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Booted>(
      future: _boot,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            theme: _theme(),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('boot failed: ${snap.error}',
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
          );
        }
        final booted = snap.data;
        if (booted == null) {
          return MaterialApp(
            theme: _theme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return MultiProvider(
          providers: [
            Provider.value(value: booted.classTable),
            ChangeNotifierProvider.value(value: booted.settings),
            ChangeNotifierProvider(
              create: (_) => GameController(
                booted.arbiter,
                BotApi(booted.bridge),
                GradingApi(booted.bridge),
                booted.settings,
                booted.db,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => ReviewController(booted.db),
            ),
            Provider(create: (_) => ChessApi(booted.bridge)),
          ],
          child: MaterialApp(
            title: 'botvinnik',
            theme: _theme(),
            home: const GameScreen(),
          ),
        );
      },
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Debug-only: play a few scripted player moves so the whole pipeline
/// (bot reply, grading, backfill, insight card) can be verified headlessly
/// on the simulator — then force-save and walk into the archive + review
/// screens. Flip to false for human play.
const bool kSelfTest = false;

class _GameScreenState extends State<GameScreen> {
  int _tab = 0; // 0 insights, 1 moves

  @override
  void initState() {
    super.initState();
    if (kSelfTest) _selfTest();
  }

  Future<void> _selfTest() async {
    final game = context.read<GameController>();
    for (final uci in ['e2e4', 'd2d4', 'g1f3']) {
      // wait for our turn
      while (!game.isPlayerTurn || game.botThinking) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || game.gameOver) return;
      var move = NormalMove.fromUci(uci);
      if (!game.position.isLegal(move)) {
        final legal = game.position.legalMoves.entries
            .where((e) => e.value.squares.isNotEmpty)
            .firstOrNull;
        if (legal == null) return;
        move = NormalMove(from: legal.key, to: legal.value.squares.first);
      }
      final (_, san) = game.position.makeSan(move);
      game.playerMove(move, san);
    }
    // let backfills land, then archive and walk the review flow
    await Future.delayed(const Duration(seconds: 8));
    if (!mounted) return;
    await game.debugForceSave();
    if (!mounted) return;
    final review = context.read<ReviewController>();
    await review.loadGames();
    if (!mounted || review.games.isEmpty) return;
    if (!mounted) return;
    Navigator.push(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(builder: (_) => const GamesListScreen()),
    );
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    review.open(review.games.first);
    Navigator.push(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(builder: (_) => const ReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameController>();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const BoardPane(),
            const GradeStrip(),
            _tabRow(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (game.gameOver)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                        child: Text(game.statusLine,
                            style: const TextStyle(
                                color: Color(0xFF81B64C),
                                fontWeight: FontWeight.w600)),
                      ),
                    if (_tab == 0) const InsightCard() else const MoveListPane(),
                  ],
                ),
              ),
            ),
            const ActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _tabRow() {
    const tabs = [
      (Icons.lightbulb_outline, 'Insights'),
      (Icons.list_alt, 'Moves'),
    ];
    return Container(
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    children: [
                      Icon(tabs[i].$1,
                          size: 18,
                          color: _tab == i
                              ? const Color(0xFF81B64C)
                              : Colors.white38),
                      Text(tabs[i].$2,
                          style: TextStyle(
                              fontSize: 10,
                              color: _tab == i
                                  ? const Color(0xFF81B64C)
                                  : Colors.white38)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
