// botvinnik mobile — standard three-tab shell: Play | Practice | Review.
// The Play tab's app bar carries the opponent (tap to change), undo and
// new-game; Practice wears its due-count badge on the tab itself.
//
// Boot order matters: brain.js (JS runtime) → native Stockfish → arbiter →
// settings/db → controllers. The engine singleton does not survive Dart hot
// restarts — cold-start the app after touching engine code.

import 'package:dartchess/dartchess.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'brain/bot_api.dart';
import 'brain/chess_api.dart';
import 'brain/grading_api.dart';
import 'brain/js_bridge.dart';
import 'brain/practice_api.dart';
import 'db/app_db.dart';
import 'db/db_init.dart';
import 'engine/arbiter.dart';
import 'engine/engine_factory.dart';
import 'stores/book_store.dart';
import 'stores/game_controller.dart';
import 'stores/practice_controller.dart';
import 'stores/review_controller.dart';
import 'stores/settings_store.dart';
import 'ui/board_pane.dart';
import 'ui/book_pane.dart';
import 'ui/games_list.dart';
import 'ui/grade_strip.dart';
import 'ui/insight_card.dart';
import 'ui/lines_pane.dart';
import 'ui/lines_tree_pane.dart';
import 'ui/move_list.dart';
import 'ui/new_game_sheet.dart';
import 'ui/practice_tab.dart';
import 'ui/roster_picker.dart';
import 'ui/settings_tab.dart';
import 'ui/win_chart.dart';

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
/// MaterialApp — pushed routes (review) must see the providers.
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
  final PracticeController practice;
  _Booted(this.bridge, this.arbiter, this.settings, this.classTable, this.db,
      this.practice);
}

class _BootGateState extends State<BootGate> {
  late final Future<_Booted> _boot = _start();

  Future<_Booted> _start() async {
    initDatabaseFactory(); // web: sqlite3 WASM; native: no-op
    final bridge = await JsBridge.load();
    final engine = await startEngine();
    final arbiter = SearchArbiter(engine);
    final settings = await SettingsStore.load();
    final db = await AppDb.open();
    final classTable = ClassTable(GradingApi(bridge).classTable());
    final practice = PracticeController(
        db, PracticeApi(bridge), GradingApi(bridge), arbiter)
      ..settings = settings;
    await practice.load();
    return _Booted(bridge, arbiter, settings, classTable, db, practice);
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
            ChangeNotifierProvider.value(value: booted.practice),
            ChangeNotifierProvider(
              create: (_) => GameController(
                booted.arbiter,
                BotApi(booted.bridge),
                GradingApi(booted.bridge),
                booted.settings,
                booted.db,
                booted.practice,
                ChessApi(booted.bridge),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => ReviewController(booted.db),
            ),
            ChangeNotifierProvider(create: (_) => BookStore()),
            Provider(create: (_) => ChessApi(booted.bridge)),
          ],
          child: MaterialApp(
            title: 'botvinnik',
            theme: _theme(),
            home: const AppShell(),
          ),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  /// Tabs are built on first visit and kept alive after that. IndexedStack
  /// would otherwise build all four at boot — which on web means Settings'
  /// preview strips fetch every board texture and piece set before you have
  /// even seen the board (2.4MB gzipped of the first load).
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final practice = context.watch<PracticeController>();
    return Scaffold(
      appBar: _appBar(context),
      body: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < 4; i++)
            if (_visited.contains(i)) _tabAt(i) else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        backgroundColor: const Color(0xFF1f1e1b),
        indicatorColor: const Color(0xFF3a3733),
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            _visited.add(i);
          });
          if (i == 1 && practice.current == null) practice.startSession();
          if (i == 2) context.read<ReviewController>().loadGames();
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Play',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: practice.due > 0,
              label: Text('${practice.due}'),
              child: const Icon(Icons.fitness_center_outlined),
            ),
            selectedIcon: const Icon(Icons.fitness_center),
            label: 'Practice',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Review',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _tabAt(int i) => switch (i) {
        0 => const PlayTab(),
        1 => const PracticeTab(),
        2 => const GamesListBody(),
        _ => const SettingsTab(),
      };

  PreferredSizeWidget _appBar(BuildContext context) {
    switch (_tab) {
      case 1:
        final practice = context.watch<PracticeController>();
        return AppBar(
          title: Text(
            'Practice'
            '${practice.sessionSolved > 0 ? ' · ✓${practice.sessionSolved}' : ''}'
            '${practice.sessionStreak > 1 ? ' · 🔥${practice.sessionStreak}' : ''}',
            style: const TextStyle(fontSize: 16),
          ),
        );
      case 2:
        return AppBar(title: const Text('Games', style: TextStyle(fontSize: 16)));
      case 3:
        return AppBar(
            title: const Text('Settings', style: TextStyle(fontSize: 16)));
      default:
        final game = context.watch<GameController>();
        return AppBar(
          titleSpacing: 8,
          title: InkWell(
            onTap: () => showRosterPicker(context),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      game.botEnabled
                          ? Icons.smart_toy_outlined
                          : Icons.biotech_outlined,
                      size: 18,
                      color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                      game.botEnabled
                          ? (game.persona?.name ?? 'Opponent')
                          : 'Analysis',
                      style: const TextStyle(fontSize: 15)),
                  const Icon(Icons.arrow_drop_down, color: Colors.white54),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed:
                  game.moves.isEmpty || game.botThinking ? null : game.undo,
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: () {
                final s = context.read<SettingsStore>();
                s.blind = !s.blind;
              },
              icon: Icon(game.blind
                  ? Icons.visibility_off
                  : Icons.visibility_outlined),
              color: game.blind ? const Color(0xFF81B64C) : null,
              tooltip: game.blind
                  ? 'Blind mode on — no engine help'
                  : 'Blind mode off',
            ),
            IconButton(
              onPressed: () => showNewGameSheet(context),
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'New game',
            ),
          ],
        );
    }
  }
}

/// Debug-only: play a few scripted player moves so the whole pipeline can be
/// verified headlessly on the simulator. Flip to false for human play.
const bool kSelfTest = false;

class PlayTab extends StatefulWidget {
  const PlayTab({super.key});

  @override
  State<PlayTab> createState() => _PlayTabState();
}

class _PlayTabState extends State<PlayTab> {
  int _view = 0; // 0 insights, 1 moves

  @override
  void initState() {
    super.initState();
    if (kSelfTest) _selfTest();
  }

  Future<void> _selfTest() async {
    final game = context.read<GameController>();
    for (final uci in ['e2e4', 'd2d4', 'g1f3']) {
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
  }

  /// Phone: board on top, panel scrolling beneath it. Desktop: the board
  /// can't just take the full width — it would push everything off the
  /// bottom — so it sits left, capped to the window height, panel alongside.
  static const double _wideBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return Column(
            children: [
              const BoardPane(),
              const GradeStrip(),
              _viewRow(),
              Expanded(child: _panel()),
            ],
          );
        }
        // leave room for the grade strip under the board. The floor applies
        // to the WIDTH share only — flooring the height too would overflow a
        // window dragged short.
        final boardSize = math.min(
          math.max(240.0, constraints.maxWidth * 0.58),
          math.max(120.0, constraints.maxHeight - 56),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: boardSize,
              child: const SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [BoardPane(), GradeStrip()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [_viewRow(), Expanded(child: _panel())],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _panel() {
    final game = context.watch<GameController>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (game.gameOver)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(game.statusLine,
                  style: const TextStyle(
                      color: Color(0xFF81B64C), fontWeight: FontWeight.w600)),
            ),
          switch (_view) {
            0 => const InsightCard(),
            1 => const LinesPane(),
            2 => const LinesTreePane(),
            3 => const WinChart(),
            4 => const MoveListPane(),
            _ => const BookPane(),
          },
        ],
      ),
    );
  }

  Widget _viewRow() {
    const tabs = [
      (Icons.lightbulb_outline, 'Insights'),
      (Icons.manage_search, 'Lines'),
      (Icons.account_tree_outlined, 'Tree'),
      (Icons.show_chart, 'Chart'),
      (Icons.list_alt, 'Moves'),
      (Icons.menu_book_outlined, 'Book'),
    ];
    return Container(
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _view = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      Icon(tabs[i].$1,
                          size: 16,
                          color: _view == i
                              ? const Color(0xFF81B64C)
                              : Colors.white38),
                      Text(tabs[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: _view == i
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
