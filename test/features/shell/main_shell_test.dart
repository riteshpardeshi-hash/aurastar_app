import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/screen_cache.dart';
import 'package:aura_app/core/services/videos_service.dart';
import 'package:aura_app/features/account/screens/my_account_screen.dart';
import 'package:aura_app/features/challenges/screens/all_general_challenges_screen.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';
import 'package:aura_app/features/leaderboard/leaderboard_screen.dart';
import 'package:aura_app/features/shell/main_shell.dart';
import 'package:aura_app/shared/widgets/screen_skeleton.dart';

// MainShell keeps all four tab screens alive in an IndexedStack so switching
// tabs is instant — no route push, no re-fetch. The tapped tab is revealed
// on the next frame whether or not its first payload has arrived; it shows
// its own skeleton while loading rather than the shell freezing on the
// previous tab (the pre-ADR-011-amendment behavior).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int leaderboardCalls;
  Completer<void>? gateLeaderboard;

  http.Response ok(Object body) =>
      http.Response(jsonEncode({'status': 'success', 'data': body}), 200);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
    ScreenCache.clear();
    VideosService.resetLocallyDeletedForTest();
    leaderboardCalls = 0;
    gateLeaderboard = null;

    ApiClient.httpClient = MockClient((request) async {
      final p = request.url.path;
      if (p.endsWith('/leaderboard')) {
        leaderboardCalls++;
        if (gateLeaderboard != null) await gateLeaderboard!.future;
        return ok({
          'leaderboard': [
            {'_id': 'u9', 'displayName': 'Ada', 'auraPoints': 900},
          ],
        });
      }
      if (p.endsWith('/profile')) {
        return ok({
          'user': {
            '_id': 'user-1',
            'displayName': 'Test User',
            'auraPoints': 300,
            'level': 3,
            'tier': 'rookie',
          },
        });
      }
      if (p.endsWith('/challenges')) {
        return ok({
          'challenges': [
            {'_id': 'c1', 'title': 'Challenge 1', 'videoUrl': '', 'creatorId': 'system'},
          ],
        });
      }
      // Everything else (videos / saved / referrals / streak / rewards /
      // categories / home shelves / friends) degrades to empty in its
      // service — a generic empty payload is enough for this screen set.
      return ok({
        'challenges': [],
        'categories': [],
        'leaderboard': [],
        'responses': [],
        'items': [],
        'user': {'_id': 'user-1', 'displayName': 'Test User'},
      });
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ScreenCache.clear();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    // Real http (even mocked) needs the real event loop to resolve.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('builds all four tab screens up front (kept alive)',
      (tester) async {
    await pumpShell(tester);

    expect(find.byType(Dashboard, skipOffstage: false), findsOneWidget);
    expect(find.byType(AllGeneralChallengesScreen, skipOffstage: false),
        findsOneWidget);
    expect(find.byType(LeaderboardScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(MyAccountScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('switching to a ready tab shows it with no spinner',
      (tester) async {
    await pumpShell(tester);

    // Home is the visible tab; Profile is built but offstage.
    expect(find.byType(MyAccountScreen), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MyAccountScreen), findsOneWidget,
        reason: 'the already-loaded Profile tab appears immediately');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a tab switch must never show a loading spinner');
  });

  testWidgets('switching away and back does not re-fetch (IndexedStack keep-alive)',
      (tester) async {
    await pumpShell(tester);
    expect(leaderboardCalls, 1, reason: 'global board loads once on mount');

    await tester.tap(find.text('Leaderboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.tap(find.text('Leaderboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(leaderboardCalls, 1,
        reason: 'the board stays mounted — revisiting a tab must not re-run '
            'its initState fetch');
  });

  testWidgets(
      'reveals a still-loading tab immediately instead of freezing on the '
      'current one',
      (tester) async {
    // Hold the Leaderboard's /leaderboard call open so the tab cannot finish
    // loading at the moment it's revealed.
    gateLeaderboard = Completer<void>();
    await pumpShell(tester);

    expect(find.byType(LeaderboardScreen), findsNothing,
        reason: 'Leaderboard starts offstage in the IndexedStack');

    await tester.tap(find.text('Leaderboard'));
    await tester.pump();

    // One frame later the tab is on screen — showing its own skeleton, not
    // the previous tab. The old behavior held Home here for up to 5s.
    expect(find.byType(LeaderboardScreen), findsOneWidget,
        reason: 'the tapped tab is revealed on the next frame, still loading');
    expect(find.byType(Dashboard), findsNothing,
        reason: 'the previous tab is no longer shown');
    expect(find.byType(ScreenSkeleton), findsWidgets,
        reason: 'the revealed-but-loading tab shows its own skeleton');

    // Let the gated request finish so no 15s timeout Timer outlives the test.
    gateLeaderboard!.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  });
}
