import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/sync/sync_controller.dart';
import 'package:botvinnik_mobile/sync/sync_triggers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_sync_key_store.dart';
import 'support/game_harness.dart';
import 'support/memory_db.dart';
import 'support/practice_harness.dart';

/// Counts autoSync calls instead of doing real work, so the test observes which
/// events trigger a sync.
class _SpySync extends SyncController {
  _SpySync() : super(db: MemoryDb(), keyStore: FakeSyncKeyStore());
  int autoSyncs = 0;

  @override
  Future<void> autoSync() async => autoSyncs++;

  @override
  Future<void> loadCached() async {}
}

Future<void> _sendLifecycle(WidgetTester tester, String state) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state),
      (_) {},
    );

void main() {
  testWidgets('syncs on launch, practice progress, and leaving/returning',
      (tester) async {
    final sync = _SpySync();
    final game = await makeGame();
    final practice = makePractice(const []).practice;
    final review = ReviewController(MemoryDb());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncController>.value(value: sync),
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<PracticeController>.value(value: practice),
        ChangeNotifierProvider<ReviewController>.value(value: review),
      ],
      child: const SyncTriggers(child: SizedBox()),
    ));
    await tester.pump(); // run the post-frame _start
    await tester.pump(const Duration(seconds: 1)); // settle launch + any initial lifecycle
    expect(sync.autoSyncs, greaterThanOrEqualTo(1), reason: 'launch sync');

    // Each action must push the count up by at least one. (Exact counts are
    // flaky — the test harness dispatches its own initial lifecycle event.)
    Future<void> expectSyncs(String reason, Future<void> Function() act) async {
      final before = sync.autoSyncs;
      await act();
      expect(sync.autoSyncs, greaterThan(before), reason: reason);
    }

    // Practice progress → debounced push (the reliable path for the PWA).
    await expectSyncs('practice progress', () async {
      practice.notifyListeners();
      await tester.pump(const Duration(seconds: 5)); // past the 4s debounce
    });

    // Leaving (tab hidden / app backgrounded) → best-effort push.
    await expectSyncs('on leave', () async {
      await _sendLifecycle(tester, 'AppLifecycleState.paused');
      await tester.pump();
    });

    // Returning → pull.
    await expectSyncs('on resume', () async {
      await _sendLifecycle(tester, 'AppLifecycleState.resumed');
      await tester.pump();
    });
  });
}
