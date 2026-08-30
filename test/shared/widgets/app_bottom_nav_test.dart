import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/shared/widgets/app_bottom_nav.dart';

// Regression coverage: every top-level screen used to hand-copy its own
// bottom nav — Dashboard, the challenges list, the brand challenges list,
// and creator activity had each drifted apart (different labels — "Brand"
// vs "Brand Challenges"; different icons for the same tab — person_rounded
// vs person_outline_rounded; different navigation calls for the same tab —
// push vs pushReplacement vs popUntil; one version wasn't even the same
// pill+FAB design at all). AppBottomNav is now the single implementation
// every screen instantiates, so these tests pin down its own contract
// rather than re-testing each individual screen.
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
    // "Challenges" and "Brand" were tabs before Home/Search replaced them —
    // neither should exist anymore.
    expect(find.text('Challenges'), findsNothing);
    expect(find.text('Brand'), findsNothing);
  });

  testWidgets('tapping the tab matching the current screen does not navigate',
      (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(
        body: AppBottomNav(activeTab: AppNavTab.search),
      ),
    ));
    await tester.pump();
    observer.pushCount = 0; // ignore the initial route push

    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(observer.pushCount, 0,
        reason: 'the active tab is already the current screen — tapping it '
            'again must not push a duplicate copy of itself');
  });

  testWidgets(
      'tapping a different tab from a screen nested several levels deep '
      'returns to the root before pushing, instead of stacking ever deeper',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                // Build a 3-deep stack: Root -> Mid -> Current (which hosts
                // the nav bar) — mirrors a user having navigated a few
                // screens deep before using the bottom nav to switch tabs.
                Navigator.push(context, MaterialPageRoute(builder: (_) {
                  return Scaffold(
                    body: Builder(builder: (context) {
                      return Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) {
                              return const Scaffold(
                                body: AppBottomNav(
                                    activeTab: AppNavTab.search),
                              );
                            }));
                          },
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

    // Now 3 deep: Root, Mid, Current. Tap "Leaderboard" (not the active tab).
    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    // If this landed on Leaderboard directly on top of Root (2 deep, not
    // 4), popping once should return straight to Root, not to Mid or
    // Current — proving those intermediate routes were discarded rather
    // than left underneath the new screen.
    expect(find.text('Go to Mid'), findsNothing,
        reason: 'Leaderboard should be showing now, on top of Root');
    final rootNavigator = tester.state<NavigatorState>(find.byType(Navigator));
    rootNavigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Go to Mid'), findsOneWidget,
        reason: 'a single pop from the pushed tab must land straight back '
            'on Root — Mid and Current must have been popped when the tab '
            'was tapped, not left stacked underneath the new screen');
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    pushCount++;
  }
}
