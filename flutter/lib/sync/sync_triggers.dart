import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../stores/game_controller.dart';
import '../stores/practice_controller.dart';
import '../stores/review_controller.dart';
import 'sync_controller.dart';

/// Drives the automatic sync triggers (#203 M5). Wraps the app so it can reach
/// the controllers; renders its [child] unchanged.
///
/// - **Launch:** load the cached session, then sync.
/// - **Practice progress:** sync a few seconds after you attempt puzzles
///   (debounced), so progress pushes while you're still in the app — this is the
///   reliable path, especially in the PWA where a background sync may be frozen.
/// - **After a game:** sync shortly after a game finishes (debounced).
/// - **Leaving / returning:** sync when the app is hidden/paused (best-effort
///   push before the OS or browser suspends it) and when it resumes (pull).
///
/// Everything goes through [SyncController.autoSync], which is silent and
/// throttled. A pull is reloaded into the Practice/Review tabs via
/// [SyncController.onPulled], wired here so it works even when the Sync screen
/// isn't open.
class SyncTriggers extends StatefulWidget {
  const SyncTriggers({super.key, required this.child});

  final Widget child;

  @override
  State<SyncTriggers> createState() => _SyncTriggersState();
}

class _SyncTriggersState extends State<SyncTriggers>
    with WidgetsBindingObserver {
  Timer? _gameDebounce;
  Timer? _practiceDebounce;
  GameController? _game;
  PracticeController? _practice;
  bool _wasOver = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final sync = context.read<SyncController>();
    final practice = context.read<PracticeController>();
    final review = context.read<ReviewController>();

    // Reload the tabs whenever a sync pulls new data, even if the Sync screen
    // isn't open.
    sync.onPulled = () async {
      await practice.load();
      await review.loadGames();
    };

    _game = context.read<GameController>()..addListener(_onGame);
    _wasOver = _game!.gameOver;
    _practice = practice..addListener(_onPractice);

    await sync.loadCached(); // a paired device comes up "on"
    await sync.autoSync(); // launch sync
  }

  // A game just finished (gameOver false→true) — sync it, debounced.
  void _onGame() {
    final over = _game?.gameOver ?? false;
    if (over && !_wasOver) {
      _gameDebounce?.cancel();
      _gameDebounce = Timer(const Duration(seconds: 4), _autoSync);
    }
    _wasOver = over;
  }

  // Practice progress changed — sync it, debounced so a run of attempts
  // coalesces into one push while you're still playing.
  void _onPractice() {
    _practiceDebounce?.cancel();
    _practiceDebounce = Timer(const Duration(seconds: 4), _autoSync);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Push on the way out (best-effort — the OS/browser may suspend us first)
    // and pull on the way back in. `hidden` is the web tab-hidden state.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _autoSync();
    }
  }

  void _autoSync() {
    if (mounted) context.read<SyncController>().autoSync();
  }

  @override
  void dispose() {
    _gameDebounce?.cancel();
    _practiceDebounce?.cancel();
    _game?.removeListener(_onGame);
    _practice?.removeListener(_onPractice);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
