// botvinnik mobile — standard three-tab shell: Play | Practice | Review.
// The Play tab's app bar carries the opponent (tap to change), undo and
// new-game; Practice wears its due-count badge on the tab itself.
//
// Boot order matters: brain.js (JS runtime) → native Stockfish → arbiter →
// settings/db → controllers. The engine singleton does not survive Dart hot
// restarts — cold-start the app after touching engine code.

import 'package:dartchess/dartchess.dart';
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
import 'ui/keyboard.dart';
import 'ui/layout.dart';
import 'ui/lines_pane.dart';
import 'ui/lines_tree_pane.dart';
import 'ui/move_list.dart';
import 'ui/new_game_sheet.dart';
import 'ui/practice_tab.dart';
import 'ui/roster_picker.dart';
import 'ui/settings_tab.dart';
import 'ui/splash.dart';
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
      // naming it explicitly is what makes the web build use the BUNDLED
      // Roboto (see pubspec) instead of fetching it from fonts.gstatic.com
      fontFamily: 'Roboto',
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
  // a hang anywhere in boot would otherwise show a spinner forever; the
  // FutureBuilder already renders errors
  late final Future<_Booted> _boot = _start().timeout(
    const Duration(seconds: 75), // engine readiness alone allows 45
    onTimeout: () => throw StateError('boot timed out'),
  );

  /// Which tab is up. Owned here rather than in [AppShell] because the
  /// keyboard layer sits above the shell (it must, to hold focus) and has to
  /// know whether the board it drives is actually on screen. [AppShell] is the
  /// only writer, and it setStates on every write, so no listener is needed.
  final ValueNotifier<int> _tab = ValueNotifier(0);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<_Booted> _start() async {
    initDatabaseFactory(); // web: sqlite3 WASM; native: no-op
    final bridge = await JsBridge.load();
    // Started, NOT awaited. On the web the engine is a 7MB WASM download plus
    // a UCI handshake, and awaiting it here put all of that in front of the
    // first frame: 17.3MB before anything was drawn, measured at 16s on fast
    // 4G and 46s on slow. The board does not need the engine to appear — the
    // arbiter queues searches until it answers — so the splash now lifts on
    // brain + settings + db, and the engine arrives behind it.
    final arbiter = SearchArbiter(startEngine());
    final settings = await SettingsStore.load();
    final db = await AppDb.open();
    final classTable = ClassTable(GradingApi(bridge).classTable());
    final practice = PracticeController(
        db, PracticeApi(bridge), GradingApi(bridge), arbiter)
      ..settings = settings;
    await practice.load();
    dismissSplash(); // web: hand over from the HTML splash (no-op elsewhere)
    return _Booted(bridge, arbiter, settings, classTable, db, practice);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Booted>(
      future: _boot,
      builder: (context, snap) {
        if (snap.hasError) {
          dismissSplash(); // never leave the splash covering an error
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
            home: Builder(
              builder: (context) => KeyboardControls(
                game: context.read<GameController>(),
                enabled: () => _tab.value == 0,
                child: AppShell(tab: _tab),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  /// The selected tab, held above us so the keyboard layer can read it.
  final ValueNotifier<int> tab;
  const AppShell({super.key, required this.tab});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int get _tab => widget.tab.value;
  set _tab(int i) => widget.tab.value = i;

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
          for (var i = 0; i < kTabCount; i++)
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

  /// Keep in step with [destinations] below; the loop that builds the stack
  /// reads this rather than a literal.
  static const int kTabCount = 4;

  Widget _tabAt(int i) => switch (i) {
        0 => const PlayTab(),
        1 => const PracticeTab(),
        2 => const GamesListBody(),
        3 => const SettingsTab(),
        _ => throw RangeError.index(i, null, 'tab'),
      };

  PreferredSizeWidget _appBar(BuildContext context) {
    switch (_tab) {
      case 1:
        final practice = context.watch<PracticeController>();
        return AppBar(
          title: Text(
            'Practice'
            // words, not ✓ and 🔥: neither glyph is in Roboto, so the title
            // alone pulled Noto Sans Symbols (and an emoji font) from
            // fonts.gstatic.com the moment you solved one
            '${practice.sessionSolved > 0 ? ' · ${practice.sessionSolved} solved' : ''}'
            '${practice.sessionStreak > 1 ? ' · streak ${practice.sessionStreak}' : ''}',
            style: const TextStyle(fontSize: 16),
          ),
        );
      case 2:
        // the review renders inside this tab rather than as a pushed route,
        // so there is no route to pop — the way back to the list is here
        final review = context.watch<ReviewController>();
        final game = review.current;
        if (game == null) {
          return AppBar(
              title: const Text('Games', style: TextStyle(fontSize: 16)));
        }
        return AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to games',
            onPressed: review.close,
          ),
          title: Text('${game['result']} · ${game['botPersona'] ?? 'game'}',
              style: const TextStyle(fontSize: 15)),
        );
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
              onPressed: game.canUndo ? game.undo : null,
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: game.canRedo ? game.redo : null,
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
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
            // only where there is plausibly a keyboard; on a phone it is noise
            if (MediaQuery.sizeOf(context).width >= _PlayTabState._wideBreakpoint)
              IconButton(
                onPressed: () => showKeyboardHelp(context),
                icon: const Icon(Icons.keyboard_outlined),
                tooltip: 'Keyboard shortcuts',
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

/// The drag handle between board and panels. Wide enough to grab, drawn
/// narrow, and it shows a resize cursor so it looks like what it is.
class _SplitHandle extends StatefulWidget {
  final void Function(double dx) onDrag;
  const _SplitHandle({required this.onDrag});

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 2,
              color: _hot ? const Color(0xFF81B64C) : Colors.white12,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayTabState extends State<PlayTab> {
  /// Phone: one panel at a time — there is no room to stack and the bar is
  /// the only way back.
  int _view = 0;



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
  static const double _wideBreakpoint = kWideBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          // The board is square and was taking the full width, which is right
          // on a phone — where height is plentiful — and overflows a desktop
          // window that is narrow AND short. Cap it by what is left after the
          // strip, the view bar and enough panel to be worth showing.
          final board =
              narrowBoardSize(constraints.maxWidth, constraints.maxHeight);
          return Column(
            children: [
              Center(child: SizedBox(width: board, child: const BoardPane())),
              const GradeStrip(),
              _viewRow(),
              Expanded(child: _panel()),
            ],
          );
        }
        // leave room for the grade strip under the board. The floor applies
        // to the WIDTH share only — flooring the height too would overflow a
        // window dragged short.
        final settings = context.watch<SettingsStore>();
        final boardSize = wideBoardSize(
            constraints.maxWidth, constraints.maxHeight, settings.split);
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
            _SplitHandle(
              onDrag: (dx) => settings.split =
                  settings.split + dx / constraints.maxWidth,
            ),
            Expanded(
              child: Column(
                children: [
                  _viewRow(multi: true),
                  Expanded(child: _stackedPanel()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The selected panels, in bar order. Headed once more than one is up,
  /// because otherwise a stack of unlabelled cards is a puzzle.
  Set<int> _panels(BuildContext context) => context.watch<SettingsStore>().panels;

  Widget _stackedPanel() {
    final game = context.watch<GameController>();
    final shown = _panels(context).toList()..sort();
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
          for (final i in shown) ...[
            if (shown.length > 1) _panelHeader(i),
            _paneAt(i),
          ],
        ],
      ),
    );
  }

  Widget _panelHeader(int i) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
        child: Row(
          children: [
            Icon(_tabs[i].$1, size: 13, color: Colors.white38),
            const SizedBox(width: 6),
            Text(_tabs[i].$2.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: Colors.white38,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: Colors.white24,
              visualDensity: VisualDensity.compact,
              tooltip: 'Hide ${_tabs[i].$2}',
              onPressed: () => context.read<SettingsStore>().togglePanel(i),
            ),
          ],
        ),
      );

  Widget _paneAt(int i) => switch (i) {
        0 => const InsightCard(),
        1 => const LinesPane(),
        2 => const LinesTreePane(),
        3 => const WinChart(),
        4 => const MoveListPane(),
        _ => const BookPane(),
      };

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
          _paneAt(_view),
        ],
      ),
    );
  }

  static const List<(IconData, String)> _tabs = [
    (Icons.lightbulb_outline, 'Insights'),
    (Icons.manage_search, 'Lines'),
    (Icons.account_tree_outlined, 'Tree'),
    (Icons.show_chart, 'Chart'),
    (Icons.list_alt, 'Moves'),
    (Icons.menu_book_outlined, 'Book'),
  ];

  /// [multi] makes the bar inclusive: tapping toggles a panel rather than
  /// replacing the selection. The last one cannot be turned off — an empty
  /// right-hand column would just look broken.
  Widget _viewRow({bool multi = false}) {
    const tabs = _tabs;
    return Container(
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () {
                  if (multi) {
                    context.read<SettingsStore>().togglePanel(i);
                  } else {
                    setState(() => _view = i);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      Icon(tabs[i].$1,
                          size: 16,
                          color: (multi ? _panels(context).contains(i) : _view == i)
                              ? const Color(0xFF81B64C)
                              : Colors.white38),
                      Text(tabs[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: (multi ? _panels(context).contains(i) : _view == i)
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
