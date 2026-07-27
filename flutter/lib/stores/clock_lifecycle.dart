// Pause the clock while the app is not in front of the player (#234).
//
// Lifecycle wiring, not timekeeping. [ChessClock] has had `pause()`/`resume()`
// since it was written and derives every remaining time from a monotonic
// origin, so nothing here touches the arithmetic — it only says WHEN. Before
// this, neither method had a single production caller.
//
// A separate widget rather than a branch inside SyncTriggers, which is the
// other WidgetsBindingObserver in the app: that one is about pushing and
// pulling a sync, this is about a chess clock, and the only thing they share
// is the callback they both need.
//
// The policy itself lives on [GameController] (`pauseForBackground` /
// `resumeFromBackground`) so it can be tested without a widget at all. This
// class is the binding and nothing more.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'game_controller.dart';

class ClockLifecycle extends StatefulWidget {
  const ClockLifecycle({super.key, required this.child});

  final Widget child;

  @override
  State<ClockLifecycle> createState() => _ClockLifecycleState();
}

class _ClockLifecycleState extends State<ClockLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No `mounted` check. It cannot fire: [dispose] removes the observer, so a
    // torn-down instance is never called at all — and while BOTH were here,
    // each masked the other and neither could be shown to matter. Deleting
    // `removeObserver` now reddens the teardown test, which is what makes that
    // test worth having.
    final game = context.read<GameController>();
    // Everything that is not `resumed` pauses — `inactive` (iOS control
    // centre, a macOS window losing focus), `hidden` (a hidden web tab),
    // `paused` and `detached`. That breadth is the decision, not an
    // oversight: see GameController.pauseForBackground.
    if (state == AppLifecycleState.resumed) {
      game.resumeFromBackground();
    } else {
      game.pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
