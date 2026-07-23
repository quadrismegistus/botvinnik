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
/// - **Launch:** load the cached session, then sync (a device edited elsewhere
///   catches up as the app opens).
/// - **Resume:** sync when the app returns to the foreground.
/// - **After a game:** sync a few seconds after a game finishes (debounced, so a
///   quick rematch doesn't double-fire).
///
/// All three go through [SyncController.autoSync], which is silent and throttled.
/// A pull is reloaded into the Practice/Review tabs via [SyncController.onPulled],
/// wired here so it works even when the Sync screen isn't open.
class SyncTriggers extends StatefulWidget {
  const SyncTriggers({super.key, required this.child});

  final Widget child;

  @override
  State<SyncTriggers> createState() => _SyncTriggersState();
}

class _SyncTriggersState extends State<SyncTriggers>
    with WidgetsBindingObserver {
  Timer? _debounce;
  GameController? _game;
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

    sync.onPulled = () async {
      await practice.load();
      await review.loadGames();
    };

    _game = context.read<GameController>()..addListener(_onGame);
    _wasOver = _game!.gameOver;

    await sync.loadCached(); // a paired device comes up "on"
    await sync.autoSync(); // launch sync
  }

  void _onGame() {
    final over = _game?.gameOver ?? false;
    // The false→true edge is a game just finished (and archived).
    if (over && !_wasOver) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 4), () {
        if (mounted) context.read<SyncController>().autoSync();
      });
    }
    _wasOver = over;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SyncController>().autoSync();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _game?.removeListener(_onGame);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
