import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/shell/main_shell_controller.dart';
import 'package:aura_app/shared/widgets/app_bottom_nav.dart';

// AppBottomNav is the single bottom nav every top-level screen uses. The four
// tab screens live permanently inside MainShell's IndexedStack, so a tab tap
// is no longer a route push — it (a) pops back down to the shell if we're on
// a drill-down screen stacked above it, and (b) asks MainShell to reveal the
// requested tab via MainShellController. These tests pin that contract.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('renders the same four tabs regardless of which screen hosts it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppBottomNav()),
    ));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // "Challenges" and "Brand" were tabs before Home/Search replaced them.
    expect(find.text('Challenges'), findsNothing);
    expect(find.text('Brand'), findsNothing);
  });

  testWidgets('tapping the tab matching the current screen does nothing',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(
        body: AppBottomNav(activeTab: AppNavTab.search),
      ),
    ));
    await tester.pump();
    observer.popCount = 0;

    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(selections, isEmpty,
        reason: 'the active tab is already on screen — no switch to request');
    expect(observer.popCount, 0);
  });

  testWidgets(
      'tapping a non-active tab asks MainShell for that tab index',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    // Host on the Search tab so Home / Leaderboard / Profile are all
    // non-active and each should fire.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppBottomNav(activeTab: AppNavTab.search)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(selections, [AppNavTab.leaderboard.shellIndex]); // 2

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(selections, [2, AppNavTab.profile.shellIndex]); // + 3

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(selections, [2, 3, AppNavTab.home.shellIndex]); // + 0
  });

  testWidgets(
      'a tap on the tab item padding (not the icon/label) still switches',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppBottomNav(activeTab: AppNavTab.home)),
    ));
    await tester.pumpAndSettle();

    // The Leaderboard tab's tappable area — its GestureDetector, which is
    // larger than the glyph + text it wraps.
    final item = find.ancestor(
      of: find.text('Leaderboard'),
      matching: find.byType(GestureDetector),
    );
    final rect = tester.getRect(item);
    // Just inside the top-left corner: inside the padding, well clear of the
    // icon and label. Only registers because the GestureDetector is opaque.
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();

    expect(selections, [AppNavTab.leaderboard.shellIndex]);
  });

  // ── Regression: the bar stays fully tappable on small / large-font phones ──
  //
  // Before the fix the nav row used `MainAxisAlignment.spaceAround` with bare
  // 9px labels (no ellipsis) and no text-scale clamp. On a narrow screen or
  // with the OS font size raised, the row's intrinsic width exceeded the pill,
  // Flutter clipped the overflow, and — the actual bug — pointer events were
  // not delivered to the clipped-out region. The last items, Leaderboard and
  // Profile, went dead on exactly those devices. The row is now equal-width
  // `Expanded` slots (can't overflow) with ellipsised labels, and the bar
  // clamps text scaling to 1.2x.

  Future<void> pumpNav(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: AppBottomNav(activeTab: AppNavTab.home),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets(
      'Leaderboard and Profile stay tappable on a 320dp screen at 1.5x font',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    await pumpNav(tester, size: const Size(320, 640), textScale: 1.5);

    // Pre-fix this row overflowed and logged a RenderFlex overflow here.
    expect(tester.takeException(), isNull);

    // Pre-fix these taps landed on clipped-out pixels and either did nothing
    // or threw because the widget centre was off-screen.
    await tester.tap(find.text('Leaderboard'));
    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(selections,
        [AppNavTab.leaderboard.shellIndex, AppNavTab.profile.shellIndex]);
  });

  testWidgets(
      'Leaderboard and Profile stay tappable at 2x OS font scale',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    await pumpNav(tester, size: const Size(360, 720), textScale: 2.0);

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Leaderboard'));
    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(selections,
        [AppNavTab.leaderboard.shellIndex, AppNavTab.profile.shellIndex]);
  });

  testWidgets(
      'the centre action button does not swallow taps meant for its neighbours',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(
        body: AppBottomNav(activeTab: AppNavTab.home),
      ),
    ));
    await tester.pump();
    observer.pushCount = 0;

    // Tap the inner edge of the Search slot — the side nearest the FAB, where
    // the FAB's opaque square hit box used to overlap on tight layouts.
    final search = find.ancestor(
      of: find.text('Search'),
      matching: find.byType(GestureDetector),
    );
    final rect = tester.getRect(search);
    await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
    await tester.pump();

    expect(selections, [AppNavTab.search.shellIndex]);
    // …and it did NOT also push the reels feed the FAB opens.
    expect(observer.pushCount, 0);
  });

  testWidgets(
      'from a screen nested several routes deep, a tab tap pops back to the '
      'shell before asking for the tab — it never leaves routes stacked',
      (tester) async {
    final selections = <int>[];
    final sub = MainShellController.instance.onSelect.listen(selections.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) {
                  return Scaffold(
                    body: Builder(builder: (context) {
                      return Center(
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const Scaffold(
                                body: AppBottomNav(activeTab: AppNavTab.search),
                              ),
                            ),
                          ),
                          child: const Text('Go to Current'),
                        ),
                      );
                    }),
                  );
                }));
              },
              child: const Text('Go to Mid'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Go to Mid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Current'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    // Popped straight back to the root (Mid and Current gone)…
    expect(find.text('Go to Mid'), findsOneWidget);
    expect(find.text('Go to Current'), findsNothing);
    // …and the tab switch was requested from MainShellController.
    expect(selections, [AppNavTab.leaderboard.shellIndex]);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;
  int popCount = 0;

  @override
  void didPush(Route route, Route? previousRoute) => pushCount++;

  @override
  void didPop(Route route, Route? previousRoute) => popCount++;
}
