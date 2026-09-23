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
  // /profile/videos response for the Profile tab's "MY VIDEOS" grid. Mutable
  // per test so most tests keep the empty default; left as-is (not pruned)
  // across a delete to match the real, documented backend behavior — see
  // docs/backend-issues/002-profile-videos-returns-soft-deleted-videos.md —
  // where the list endpoint keeps listing a video after DELETE /videos/{id}
  // soft-deletes it. Filtering is entirely VideosService's job client-side.
  late List<Map<String, dynamic>> myVideos;

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
    myVideos = [];

    ApiClient.httpClient = MockClient((request) async {
      final p = request.url.path;
      if (p.endsWith('/profile/videos')) {
        return ok({'responses': myVideos});
      }
      if (request.method == 'DELETE' && p.contains('/videos/')) {
        return ok({});
      }
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

  group('system back button', () {
    // Regression: the four tab roots have no in-app back button, and
    // MainShell has nothing below it on the navigator stack (post-login/
    // post-submit flows land here via pushAndRemoveUntil — ADR 019). With
    // no PopScope, pressing the hardware/system back button on ANY tab —
    // not just Home — fell straight through to "no route to pop, exit the
    // app", instead of returning to Home first like every other bottom-nav
    // app. Only Home itself exiting on back was correct.

    testWidgets(
        'on a non-Home tab, canPop is false so back cannot fall through '
        'to exiting the app', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(MyAccountScreen), findsOneWidget);

      // PopScope is generic (concretely PopScope<Object?> here), so
      // find.byType(PopScope) — an exact runtimeType match — misses it;
      // match by predicate instead.
      final popScope = tester.widget(
          find.byWidgetPredicate((w) => w is PopScope, description: 'PopScope')) as PopScope;
      expect(popScope.canPop, isFalse,
          reason: 'off Home, the system back button must be intercepted, '
              'not left to the default "no route below -> exit" behavior');
    });

    testWidgets(
        'pressing system back on a non-Home tab returns to Home instead of '
        'exiting', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Leaderboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LeaderboardScreen), findsOneWidget);
      expect(find.byType(Dashboard), findsNothing);

      // Simulates the Android hardware/gesture back button.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Dashboard), findsOneWidget,
          reason: 'back should land on Home, exactly like tapping the Home '
              'tab would');
      expect(find.byType(LeaderboardScreen), findsNothing);
    });

    testWidgets(
        'on the Home tab, canPop stays true — back exiting the app there is '
        'unchanged', (tester) async {
      await pumpShell(tester);

      final popScope = tester.widget(
          find.byWidgetPredicate((w) => w is PopScope, description: 'PopScope')) as PopScope;
      expect(popScope.canPop, isTrue,
          reason: 'Home is the app root; exiting on back from here was '
              'never the bug and must keep working');
    });
  });

  group('Profile "MY VIDEOS" staleness across screens', () {
    // Regression: MyAccountScreen (the Profile tab) stays mounted forever
    // inside MainShell's IndexedStack (ADR 011) — its initState/first load
    // runs once per app session, not on every tab visit. Deleting a video
    // from AllVideosScreen ("VIEW ALL") — always a fresh push with no
    // callback wired on return — updated AllVideosScreen's own state but
    // left the still-mounted Profile screen showing the already-deleted
    // video until the next pull-to-refresh or app relaunch. Simulates that
    // by calling VideosService().deleteVideo directly (as any other screen
    // would), independent of MyAccountScreen, instead of tapping its grid.

    Map<String, dynamic> video(String id, {int aura = 50}) => {
          '_id': id,
          'videoId': id,
          'videoUrl': 'https://example.com/$id.mp4',
          'thumbnailUrl': 'https://example.com/$id.jpg',
          'status': 'active',
          'submission': {'status': 'scored', 'verdict': 'GOOD', 'auraPoints': aura},
        };

    testWidgets(
        'a delete from elsewhere (AllVideosScreen) removes the video from '
        'the already-mounted Profile grid without a refetch', (tester) async {
      myVideos = [video('v1'), video('v2')];
      await pumpShell(tester);

      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Approved'), findsNWidgets(2),
          reason: 'both videos load into the Profile preview grid');

      // Simulates AllVideosScreen (a separate, unrelated screen instance)
      // deleting v2 — MyAccountScreen never calls this itself here.
      await VideosService().deleteVideo('v2', auraPoints: 50);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Approved'), findsNWidgets(1),
          reason: 'the already-mounted Profile grid must drop the deleted '
              'video in place, not keep showing it until the next reload');
    });

    testWidgets(
        'a second, unrelated delete also lands on the already-mounted '
        'Profile grid', (tester) async {
      myVideos = [video('v1'), video('v2')];
      await pumpShell(tester);

      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Approved'), findsNWidgets(2));

      await VideosService().deleteVideo('v1', auraPoints: 50);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Approved'), findsNWidgets(1));
    });
  });
}
