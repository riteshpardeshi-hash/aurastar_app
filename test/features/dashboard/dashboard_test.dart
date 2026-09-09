import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/connectivity_probe.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';
import 'package:aura_app/shared/widgets/avatar_widget.dart';

void main() {
  // Regression coverage: profileAutoRetryDelaySeconds replaced a fixed 2s
  // single retry (which made a persistently bad connection flash the
  // "Couldn't reach Aura's servers" screen every ~2s) with exponential
  // backoff. Tested directly as a pure function rather than through a full
  // widget test driving real Timers against a rejecting Future — the latter
  // is fragile in this codebase's Flutter-test harness (see camera_screen_
  // test.dart and challenge_detail_test.dart's timer-related comments).
  group('profileAutoRetryDelaySeconds', () {
    test('grows 8s, 16s, 32s for the first three attempts', () {
      expect(profileAutoRetryDelaySeconds(1), 8);
      expect(profileAutoRetryDelaySeconds(2), 16);
      expect(profileAutoRetryDelaySeconds(3), 32);
    });

    test('is capped at 60s rather than growing unbounded', () {
      expect(profileAutoRetryDelaySeconds(4), 60);
      expect(profileAutoRetryDelaySeconds(10), 60);
    });

    test('every delay is well past the old fixed 2s retry', () {
      for (var attempt = 1; attempt <= 6; attempt++) {
        expect(profileAutoRetryDelaySeconds(attempt), greaterThan(2));
      }
    });
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('the bottom-nav avatar renders the real profile photo, not '
      "just the display name's initial", (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Tushar',
                'avatar': 'https://example.com/avatar.jpg',
                'auraPoints': 0,
                'level': 1,
                'tier': 'rookie',
                'isProfileComplete': true,
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    // Dashboard resolves in stages: a FutureBuilder for the user id, then a
    // postFrameCallback that kicks off the profile FutureBuilder. Pump
    // through each stage before letting real (even if mocked) network calls
    // settle via runAsync.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    // Deliberately no further pump/runAsync after this: once AvatarWidget is
    // built with the right photoUrl, that's the regression this test cares
    // about — letting its Image.network actually attempt to load risks the
    // test process reaching out over a real socket.

    // The top-bar avatar button was later removed entirely (the profile tab
    // in the bottom nav is the only way to reach the account screen now),
    // so only the bottom-nav profile-tab avatar renders via AvatarWidget.
    final withRealPhoto = tester
        .widgetList<AvatarWidget>(find.byType(AvatarWidget))
        .where((w) => w.photoUrl == 'https://example.com/avatar.jpg');
    expect(withRealPhoto.length, 1,
        reason: 'the bottom-nav avatar must receive the real photo URL');
  });

  // Regression coverage: users reported the "Couldn't reach Aura's servers"
  // error screen appearing even on a strong connection — a single failed
  // request (a lone dropped packet, a transient blip) was enough to show
  // it. Per the backend team's guidance, a network-classified failure now
  // goes through ConnectivityProbe first; if the probe finds the backend
  // is actually reachable, _fetchDashboardProfile silently retries once
  // instead of ever surfacing the error screen.
  testWidgets(
      'a single transient network blip does not show the "no connection" '
      'error screen when ConnectivityProbe confirms the backend is '
      'actually reachable', (tester) async {
    var profileCalls = 0;
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile')) {
        profileCalls++;
        if (profileCalls == 1) {
          throw const SocketException('Network is unreachable');
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Tushar',
                'auraPoints': 0,
                'level': 1,
                'tier': 'rookie',
                'isProfileComplete': true,
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    // ConnectivityProbe pings through its own separate client — mocked to
    // always succeed, simulating "the backend really is reachable", which
    // is exactly the real-world case this feature targets (a lone blip,
    // not a genuine outage).
    ConnectivityProbe.httpClient =
        MockClient((request) async => http.Response('ok', 200));
    addTearDown(() => ConnectivityProbe.httpClient = http.Client());

    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.byIcon(Icons.wifi_off_rounded), findsNothing,
        reason: 'a single transient blip, confirmed reachable by the '
            'probe, must never surface the "no connection" error screen');
    // >= 2 rather than an exact count: Dashboard's outer FutureBuilder<uid>
    // can independently kick off _loadProfile more than once while early
    // frames settle (a pre-existing, unrelated quirk of its
    // postFrameCallback-driven load), so the exact call count isn't a
    // stable signal — what matters here is that the first failure was
    // followed by a real, successful load rather than the error screen.
    expect(profileCalls, greaterThanOrEqualTo(2),
        reason: 'the first attempt fails and at least one subsequent '
            'attempt must succeed for the dashboard to ever render');
  });
}
