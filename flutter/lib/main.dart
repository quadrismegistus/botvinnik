// botvinnik mobile — standard three-tab shell: Play | Practice | Review.
// The Play tab's app bar carries the opponent (tap to change), undo and
// new-game; Practice wears its due-count badge on the tab itself.
//
// Boot order matters: brain.js (JS runtime) → native Stockfish → arbiter →
// settings/db → controllers. The engine singleton does not survive Dart hot
// restarts — cold-start the app after touching engine code.

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'brain/bot_api.dart';
import 'brain/chess_api.dart';
import 'brain/lichess_import_api.dart';
import 'brain/explorer_api.dart';
import 'brain/grading_api.dart';
import 'brain/js_bridge.dart';
import 'brain/practice_api.dart';
import 'brain/rating_api.dart';
import 'db/app_db.dart';
import 'db/db_init.dart';
import 'engine/arbiter.dart';
import 'engine/maia_engine.dart';
import 'engine/maia_weights.dart';
import 'engine/engine_factory.dart';
import 'stores/book_store.dart';
import 'stores/game_controller.dart';
import 'stores/pgn_import.dart';
import 'stores/player_rating_store.dart';
import 'stores/practice_controller.dart';
import 'stores/review_controller.dart';
import 'stores/settings_store.dart';
import 'ui/board_pane.dart';
import 'ui/clock_display.dart';
import 'stores/chess_clock.dart';
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
import 'ui/pgn_import_dialog.dart';
import 'ui/player_plate.dart';
import 'ui/player_rating_card.dart';
import 'ui/practice_tab.dart';
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
      // NOT what stops the gstatic fetch — that is the `fonts:` block in
      // pubspec, which puts a family named Roboto in the FontManifest;
      // canvaskit/fonts.dart gates the download on that alone. Drop the
      // pubspec entry and the download returns however this line reads.
      //
      // What this line does do: override Typography's per-platform families,
      // so macOS and iOS use Roboto rather than the system face. Deliberate —
      // one typeface across every target — but it is a real change on those
      // two, not a web-only fix.
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
    // Which engine the roster's labels are calibrated against — before any bot
    // can be asked for a move. Web runs the lite-single WASM build the wasm
    // table was measured on; everywhere else is a real Stockfish 18, over FFI
    // on iOS and a spawned process on macOS, which is the native table. The
    // brain defaults to wasm, so without this line native Squares play at a
    // strength that was never measured for them (#104).
    BotApi(bridge).setSubstrate(kIsWeb ? 'wasm' : 'native');
    // Started, NOT awaited. On the web the engine is a 7MB WASM download plus
    // a UCI handshake, and awaiting it here put all of that in front of the
    // first frame: 17.3MB before anything was drawn, measured at 16s on fast
    // 4G and 46s on slow. The board does not need the engine to appear — the
    // arbiter queues searches until it answers — so the splash now lifts on
    // brain + settings + db, and the engine arrives behind it.
    final arbiter = SearchArbiter(startEngine());
    final settings = await SettingsStore.load();
    final db = await AppDb.open();
    final grading = GradingApi(bridge);
    // Fire and forget: three 3.5MB bands, cached to a file that survives
    // relaunch, so one connected session closes the offline gap for every Maia
    // persona. A no-op on web by design (#30 — not 10MB unasked to a browser),
    // idempotent, and it never opens an ORT session, so a failure here cannot
    // retire a band the player has not chosen yet.
    // Guarded: MaiaEngine.supported is macOS/iOS only, and the roster filters
    // Maia out elsewhere — so on Android this was three unusable 3.5MB
    // downloads at first boot.
    if (MaiaEngine.supported) unawaited(MaiaWeights.prefetch());

    final classTable =
        ClassTable(grading.classTable(), labelOrder: grading.labelOrder());
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
            // Not refreshed at boot: the fit reads the whole archive over the
            // bridge, and the only screen that shows it (the game-over recap)
            // asks for it when it mounts. Boot pays nothing.
            ChangeNotifierProvider(
              create: (_) =>
                  PlayerRatingStore(booted.db, RatingApi(booted.bridge)),
            ),
            ChangeNotifierProvider(create: (_) => BookStore()),
            Provider(create: (_) => ChessApi(booted.bridge)),
            Provider(create: (_) => LichessImportApi(booted.bridge)),
            Provider(create: (_) => ExplorerApi(booted.bridge)),
          ],
          child: MaterialApp(
            title: 'botvinnik',
            theme: _theme(),
            home: Builder(
              builder: (context) => KeyboardControls(
                game: context.read<GameController>(),
                review: context.read<ReviewController>(),
                practice: context.read<PracticeController>(),
                settings: context.read<SettingsStore>(),
                currentTab: () => _tab.value,
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
    final body = IndexedStack(
      index: _tab,
      children: [
        for (var i = 0; i < kTabCount; i++)
          if (_visited.contains(i)) _tabAt(i) else const SizedBox.shrink(),
      ],
    );

    // On a wide window the tabs move to a side rail and the bottom bar goes
    // away — the board is height-bound in the split view, so the ~64px the
    // bar was taking is height the board can actually grow into. The +96
    // clears the rail's own width, so the Play pane stays above its wide
    // breakpoint once the rail is in the row with it.
    if (_wideShell(context)) {
      return Scaffold(
        appBar: _appBar(context),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              backgroundColor: const Color(0xFF1f1e1b),
              indicatorColor: const Color(0xFF3a3733),
              destinations: [
                for (final d in _navItems(practice))
                  NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(context),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        backgroundColor: const Color(0xFF1f1e1b),
        indicatorColor: const Color(0xFF3a3733),
        onDestinationSelected: _select,
        destinations: [
          for (final d in _navItems(practice))
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }

  void _select(int i) {
    final practice = context.read<PracticeController>();
    setState(() {
      _tab = i;
      _visited.add(i);
    });
    if (i == 1 && practice.current == null) practice.startSession();
    if (i == 2) context.read<ReviewController>().loadGames();
  }

  /// The four tabs, defined once so the bottom bar and the side rail can't
  /// drift. Only Practice carries a badge — its due count.
  List<({Widget icon, Widget selectedIcon, String label})> _navItems(
          PracticeController practice) =>
      [
        (
          icon: const Icon(Icons.sports_esports_outlined),
          selectedIcon: const Icon(Icons.sports_esports),
          label: 'Play',
        ),
        (
          icon: Badge(
            isLabelVisible: practice.due > 0,
            label: Text('${practice.due}'),
            child: const Icon(Icons.fitness_center_outlined),
          ),
          selectedIcon: const Icon(Icons.fitness_center),
          label: 'Practice',
        ),
        (
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history),
          label: 'Review',
        ),
        (
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: 'Settings',
        ),
      ];

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

  /// A window wide enough for the desktop shell: the side rail instead of a
  /// bottom bar, and the menu bar in the app bar. The +96 clears the rail's own
  /// width so the Play pane stays above its wide breakpoint.
  bool _wideShell(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= kWideBreakpoint + 96;

  /// The wide-window menu bar. Everything in it is reachable elsewhere, but on
  /// a desktop-sized window a menu is where people look — and it is the only
  /// home for the panel toggles that isn't the view bar itself. In-app rather
  /// than a native PlatformMenuBar, because the wide layout runs on the web
  /// too, where a native menu bar does not exist.
  Widget _menuBar(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final game = context.watch<GameController>();
    const label = TextStyle(fontSize: 13, color: Colors.white70);
    return MenuBar(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      children: [
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: () => showNewGameSheet(context),
              child: const Text('New game…'),
            ),
            MenuItemButton(
              onPressed: () async {
                // land on the game it just imported
                if (await showPgnImport(context) && mounted) _select(2);
              },
              child: const Text('Import PGN…'),
            ),
          ],
          child: const Text('Game', style: label),
        ),
        SubmenuButton(
          menuChildren: [
            for (final i in _PlayTabState._paneOrder)
              CheckboxMenuButton(
                value: settings.panels.contains(i),
                onChanged: (_) => settings.togglePanel(i),
                child: Text(_PlayTabState._tabs[i].$2),
              ),
            const Divider(height: 1),
            MenuItemButton(
              onPressed: game.toggleFlip,
              child: const Text('Flip board'),
            ),
            CheckboxMenuButton(
              value: settings.blind,
              onChanged: (_) => settings.blind = !settings.blind,
              child: const Text('Blind mode'),
            ),
          ],
          child: const Text('View', style: label),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: () => showKeyboardHelp(context),
              child: const Text('Keyboard shortcuts'),
            ),
          ],
          child: const Text('Help', style: label),
        ),
      ],
    );
  }

  /// The keyboard-shortcuts button, only where a keyboard is plausible (a wide
  /// viewport). Shown on the tabs that have bindings — the sheet now documents
  /// all of them, so it is no longer Play-only.
  List<Widget> _keyboardHelp(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _PlayTabState._wideBreakpoint
          ? [
              IconButton(
                onPressed: () => showKeyboardHelp(context),
                icon: const Icon(Icons.keyboard_outlined),
                tooltip: 'Keyboard shortcuts',
              )
            ]
          : const [];

  /// Resigning is a permanent entry on the record and there is no undo for it,
  /// so it asks. A mis-tapped flag in the app bar, next to undo, would be a
  /// loss the player did not play.
  Future<void> _confirmResign(BuildContext context, GameController game) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262421),
        title: const Text('Resign this game?'),
        content: const Text(
            'It is archived as a loss and counts toward your rating. '
            'Walking away instead leaves the game unfinished, and an '
            'unfinished game counts for nothing.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep playing')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFCA3431),
                foregroundColor: Colors.white),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (ok == true) game.resign();
  }

  /// The app bar, with room made for the macOS traffic lights.
  ///
  /// The window has no titlebar of its own (fullSizeContentView), so the
  /// close/minimise/zoom buttons float over this bar's leading edge. Applying
  /// the inset in ONE place means a new branch below cannot forget it — the
  /// failure mode is a back button sitting underneath the close button, which
  /// is the kind of thing that only shows up on the one platform nobody is
  /// looking at.
  PreferredSizeWidget _appBar(BuildContext context) {
    final bar = _appBarFor(context);
    if (bar is! AppBar) return bar;
    return insetAppBar(context, bar);
  }

  PreferredSizeWidget _appBarFor(BuildContext context) {
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
          actions: _keyboardHelp(context),
        );
      case 2:
        // the review renders inside this tab rather than as a pushed route,
        // so there is no route to pop — the way back to the list is here
        final review = context.watch<ReviewController>();
        final game = review.current;
        if (game == null) {
          return AppBar(
            title: const Text('Games', style: TextStyle(fontSize: 16)),
            actions: [
              IconButton(
                onPressed: () => showPgnImport(context),
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Import PGN',
              ),
              ..._keyboardHelp(context),
            ],
          );
        }
        return AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to games',
            onPressed: review.close,
          ),
          title: Text(
              '${game['result']} · '
              '${game[kImportedKey] == true ? importedTitle(game) : _opponentName(context, game)}',
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis),
          actions: _keyboardHelp(context),
        );
      case 3:
        return AppBar(
            title: const Text('Settings', style: TextStyle(fontSize: 16)));
      default:
        final game = context.watch<GameController>();
        return AppBar(
          titleSpacing: 12,
          // Just the identity now — the opponent moved to the New Game sheet
          // (who you play is a game-start choice, not a title). Robot for the
          // app's bot motif; the name in lower case, as it's written.
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The app's own mark, not a generic robot. player_plate keeps
              // Icons.smart_toy_outlined for a bot OPPONENT — a different
              // meaning, deliberately left alone.
              const ImageIcon(AssetImage('assets/roboknight.png'),
                  size: 20, color: Color(0xFF81B64C)),
              // The wordmark is dropped on a phone: the mark alone is identity
              // enough, and the row shares the bar with resign/undo/redo/blind,
              // which overran the title on a narrow screen.
              if (_wideShell(context)) ...[
                const SizedBox(width: 8),
                const Text('botvinnik',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 18),
                _menuBar(context),
              ] else if (MediaQuery.sizeOf(context).width >=
                  _PlayTabState._wideBreakpoint) ...[
                const SizedBox(width: 18),
                _menuBar(context),
              ],
            ],
          ),
          actions: [
            // In the app bar, not a panel: panels are individually toggleable
            // and the whole layout changes at the breakpoint, so anywhere else
            // is somewhere a player can end up unable to reach. Absent — not
            // disabled — on the analysis board, where there is nobody to
            // concede to.
            if (game.botEnabled && !game.gameOver && game.moves.isNotEmpty)
              IconButton(
                onPressed: () => _confirmResign(context, game),
                icon: const Icon(Icons.flag_outlined),
                tooltip: 'Resign',
              ),
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
            // only where there is plausibly a keyboard, and only while the
            // menu bar is not up — there it lives under Help instead
            if (!_wideShell(context) &&
                MediaQuery.sizeOf(context).width >= _PlayTabState._wideBreakpoint)
              IconButton(
                onPressed: () => showKeyboardHelp(context),
                icon: const Icon(Icons.keyboard_outlined),
                tooltip: 'Keyboard shortcuts',
              ),
            // The primary action, so a labelled button at the far right rather
            // than one more anonymous icon.
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () => showNewGameSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New game'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF81B64C),
                  visualDensity: VisualDensity.compact,
                ),
              ),
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

/// The opponent's display name for a stored game, resolving ids renamed since
/// it was archived. Falls back to the raw id so an unknown persona still says
/// something rather than "game".
String _opponentName(BuildContext context, Map<String, dynamic> game) {
  // A FETCHED game (source set) carries no persona — it carries real player
  // names — so falling through to personaFor gave the review header "0-1 ·
  // game" above a list row that correctly read "vs respects_55". games_list
  // already made this distinction; this copy of it had not been updated.
  final source = game['source'] as String?;
  if (source != null) {
    final youAreWhite = (game['botColor'] as String?) != 'w';
    final them = (youAreWhite ? game['black'] : game['white']) as String?;
    if (them != null) return them;
  }
  final id = game['botPersona'] as String?;
  return context.read<GameController>().personaFor(id)?.name ?? id ?? 'game';
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
        // watched: the plates flank the board by orientation, which flips
        final game = context.watch<GameController>();
        // A rated game in progress is its own screen: no panels, no view bar,
        // the board as large as the space allows and centred, with the clocks
        // beside the names. #169.
        //
        // Not merely "the panels are empty" — blind already empties them. The
        // absence is the point: a player should be able to tell at a glance
        // that this game counts, and nothing on screen can leak an engine that
        // is not rendered. It ends at gameOver so the recap, the result and the
        // rating change are reachable without leaving the tab.
        if (game.rated && !game.gameOver) {
          return _ratedShell(context, game, constraints);
        }
        if (constraints.maxWidth < _wideBreakpoint) {
          // The board is square and was taking the full width, which is right
          // on a phone — where height is plentiful — and overflows a desktop
          // window that is narrow AND short. Cap it by what is left after the
          // strip, the view bar and enough panel to be worth showing.
          final board =
              narrowBoardSize(constraints.maxWidth, constraints.maxHeight);
          final topSide = game.whiteAtBottom ? 'b' : 'w';
          final botSide = game.whiteAtBottom ? 'w' : 'b';
          // fixed to kPlayerPlate so their height matches what narrowBoardSize
          // reserved — otherwise the column overflows and the page scrolls
          return Column(
            children: [
              SizedBox(
                  width: board,
                  height: kPlayerPlate,
                  child: PlayerPlate(key: ValueKey(topSide), side: topSide)),
              Center(child: SizedBox(width: board, child: const BoardPane())),
              SizedBox(
                  width: board,
                  height: kPlayerPlate,
                  child: PlayerPlate(
                      key: ValueKey(botSide), side: botSide, below: true)),
              _viewRow(),
              Expanded(child: _panel()),
            ],
          );
        }
        // The board takes the width, capped by height. The floor applies to
        // the WIDTH share only — flooring the height too would overflow a
        // window dragged short.
        final settings = context.watch<SettingsStore>();
        final boardSize = wideBoardSize(
            constraints.maxWidth, constraints.maxHeight, settings.split);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: boardSize,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        height: kPlayerPlate,
                        child: PlayerPlate(
                            key: ValueKey(game.whiteAtBottom ? 'b' : 'w'),
                            side: game.whiteAtBottom ? 'b' : 'w')),
                    const BoardPane(),
                    SizedBox(
                        height: kPlayerPlate,
                        child: PlayerPlate(
                            key: ValueKey(game.whiteAtBottom ? 'w' : 'b'),
                            side: game.whiteAtBottom ? 'w' : 'b',
                            below: true)),
                  ],
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

  /// Panels folded to just their header — open, but drawing no body.
  Set<int> _collapsed(BuildContext context) =>
      context.watch<SettingsStore>().collapsed;

  /// The rated screen: board, plates, clock. No panels.
  ///
  /// The plates stay full-width above and below the board as they do in a
  /// casual game — cramming a plate into a narrow column overflowed its
  /// captured-piece tray. Only the CLOCK moves, and where it goes depends on
  /// which dimension is scarce:
  ///
  ///   wide  — height is the constraint, so the clock goes to the RIGHT of the
  ///           board, flanking it top and bottom, spending the ample width.
  ///   narrow — width is the constraint, so the clock goes in the plate strips
  ///           above and below, spending height.
  Widget _ratedShell(
      BuildContext context, GameController game, BoxConstraints c) {
    final clock = game.clock;
    final topSide = game.whiteAtBottom ? 'b' : 'w';
    final botSide = game.whiteAtBottom ? 'w' : 'b';
    final wide = c.maxWidth >= _PlayTabState._wideBreakpoint;

    Widget clockFor(String s) => clock == null
        ? const SizedBox.shrink()
        : ClockFace(
            clock: clock, side: ClockSide.fromChar(s), fontSize: wide ? 34 : 26);

    if (wide) {
      // The clock column takes fixed width; the board is what is left of both
      // dimensions, square.
      const clockCol = 132.0;
      // No 160 floor here: forcing a bigger board than the window can hold is
      // what overflowed a very short window. A tiny board on a tiny window is
      // the honest outcome.
      final board = math.max(
          64.0,
          math.min(c.maxHeight - kPlayerPlate * 2, c.maxWidth - clockCol - 16));
      Widget plate(String s, {required bool below}) => SizedBox(
          width: board,
          height: kPlayerPlate,
          child: PlayerPlate(key: ValueKey(s), side: s, below: below));
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                plate(topSide, below: false),
                SizedBox(width: board, height: board, child: const BoardPane()),
                plate(botSide, below: true),
              ],
            ),
            const SizedBox(width: 8),
            // Exactly the BOARD's height, centred against the whole stack — so
            // it spans the board and not the plates: the top clock sits flush
            // with the board's top-right corner, the bottom with its bottom.
            SizedBox(
              width: clockCol,
              height: board,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  clockFor(topSide),
                  const Spacer(),
                  clockFor(botSide),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Narrow: the clock rides in the plate strip, so the plate flexes and the
    // clock takes a fixed slice on the outer edge.
    //
    // The strip is as tall as its TALLEST child, and that is the clock
    // (kClockFace 39), not the plate (kPlayerPlate 24) — so the two strips
    // reserve 2*kClockFace when a clock is present, plate height otherwise.
    // Reserving the plate height regardless overflowed a short window by the
    // difference.
    final stripH = clock == null ? kPlayerPlate : kClockFace;
    final board = math.max(
        64.0, math.min(c.maxWidth, c.maxHeight - (stripH + 4) * 2));
    Widget strip(String s, {required bool below}) => SizedBox(
        width: board,
        child: Row(
          children: [
            Expanded(
                child: SizedBox(
                    height: kPlayerPlate,
                    child: PlayerPlate(key: ValueKey(s), side: s, below: below))),
            if (clock != null) clockFor(s),
          ],
        ));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          strip(topSide, below: false),
          SizedBox(width: board, height: board, child: const BoardPane()),
          strip(botSide, below: true),
        ],
      ),
    );
  }

  Widget _stackedPanel() {
    final game = context.watch<GameController>();
    // shown in the view-bar order, not numeric id order
    final shown = _panels(context).toList()
      ..sort((a, b) => _paneOrder.indexOf(a).compareTo(_paneOrder.indexOf(b)));
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (game.gameOver) _gameOverRecap(game),
          for (final i in shown) ...[
            // headed once more than one is up; a collapsed panel is ALWAYS
            // headed, or folding the only one would leave a blank column
            if (shown.length > 1 || _collapsed(context).contains(i))
              _panelHeader(i),
            if (!_collapsed(context).contains(i)) _paneAt(i),
          ],
        ],
      ),
    );
  }

  Widget _panelHeader(int i) {
    final folded = _collapsed(context).contains(i);
    // the whole header is the hit target for folding — a 14px chevron alone is
    // a mean thing to ask anyone to hit
    return InkWell(
      onTap: () => context.read<SettingsStore>().toggleCollapsed(i),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
        child: Row(
          children: [
            Icon(folded ? Icons.chevron_right : Icons.expand_more,
                size: 14, color: Colors.white38),
            const SizedBox(width: 4),
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
      ),
    );
  }

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
          if (game.gameOver) _gameOverRecap(game),
          _paneAt(_view),
        ],
      ),
    );
  }

  /// What the app says when a game ends: the result, and then what that result
  /// did to the player's rating — the one moment the number can have moved,
  /// and the only place it is shown.
  ///
  /// Written once and used by both layouts (the phone's single panel and the
  /// desktop stack), which until now held their own copies of the result line.
  /// Two copies is two chances for one of them to be left a line behind.
  Widget _gameOverRecap(GameController game) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(game.statusLine,
                style: const TextStyle(
                    color: Color(0xFF81B64C), fontWeight: FontWeight.w600)),
          ),
          const PlayerRatingCard(afterGame: true),
        ],
      );

  static const List<(IconData, String)> _tabs = [
    (Icons.lightbulb_outline, 'Insights'),
    (Icons.manage_search, 'Lines'),
    (Icons.account_tree_outlined, 'Tree'),
    (Icons.show_chart, 'Chart'),
    (Icons.list_alt, 'Moves'),
    (Icons.menu_book_outlined, 'Book'),
  ];

  /// The order the panels are SHOWN in, by their stable id (the index into
  /// [_tabs] / [_paneAt], which never changes — so persisted selections
  /// (`botvinnik-panels`) stay valid without a migration). Analysis first —
  /// Tree and Chart — then the line list directly above the move list:
  /// Insights, Tree, Chart, Lines, Moves, Book.
  static const List<int> _paneOrder = [0, 2, 3, 1, 4, 5];

  /// [multi] makes the bar inclusive: tapping toggles a panel rather than
  /// replacing the selection. The last one cannot be turned off — an empty
  /// right-hand column would just look broken.
  Widget _viewRow({bool multi = false}) {
    const tabs = _tabs;
    return Container(
      color: const Color(0xFF1f1e1b),
      child: Row(
        children: [
          for (final i in _paneOrder)
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
