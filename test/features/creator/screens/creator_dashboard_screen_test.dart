import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/creator_dashboard_screen.dart';

// Regression: the creator dashboard used to render the *account's* player-side
// figures — the personal Aura balance from GET /profile and the player
// submission history from GET /profile/videos — because promoting an account to
// `creator` keeps the same user record. A creator with 51,597 lifetime Aura and
// 10 player submissions saw "Total Aura 51597", "Submissions 10", an
// Aura/level progress bar, and a "Recent Submissions" list, none of which are
// creator concepts. The dashboard now shows only creator-scoped totals from
// GET /creator/dashboard/overview. See ADR 009.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;

      if (request.method == 'GET' && path.endsWith('/creator/page')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'profile': {
                'displayName': 'hero',
                'username': 'jagga_daku',
                'bio': '',
              },
            },
          }),
          200,
        );
      }

      if (request.method == 'GET' && path.endsWith('/creator/dashboard-summary')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'profileComplete': true,
              'creatorPageLive': true,
              'canUploadChallenge': true,
              'challengeCount': 3,
              'followers': 0,
            },
          }),
          200,
        );
      }

      if (request.method == 'GET' &&
          path.endsWith('/creator/dashboard/overview')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'summary': {
                'totalChallenges': 3,
                'liveChallenges': 2,
                'totalParticipants': 245,
                'totalStars': 71,
              },
              'cards': [],
              'pendingActions': [],
            },
          }),
          200,
        );
      }

      if (request.method == 'GET' && path.endsWith('/creator/following')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'pagination': {'total': 0},
            },
          }),
          200,
        );
      }

      // The player profile + player video history: these endpoints must NOT be
      // consulted by this screen any more. Return loud sentinel values so that
      // if a regression re-introduces the call, the assertions below catch the
      // leaked numbers on screen.
      if (request.method == 'GET' && path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'creator-1',
                'auraPoints': 51597,
                'level': 516,
                'tier': 'rookie',
              },
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' && path.contains('/profile/videos')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'responses': List.generate(
                10,
                (i) => {
                  'challengeTitle': 'Player Challenge $i',
                  'verdict': 'FAIL',
                  'createdAt': '2026-09-01T00:00:00.000Z',
                },
              ),
            },
          }),
          200,
        );
      }

      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'shows creator-scoped totals, not the account\'s personal Aura or player submissions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreatorDashboardScreen()));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(tester.takeException(), isNull);

    // Player-side figures must be gone.
    expect(find.text('51597'), findsNothing,
        reason: 'the account\'s personal Aura balance must not appear on the '
            'creator dashboard');
    expect(find.text('Total Aura'), findsNothing);
    expect(find.text('Recent Submissions'), findsNothing,
        reason: 'player submission history is a My Account concept');
    expect(find.textContaining('Level 516'), findsNothing,
        reason: 'the personal level/tier progress bar was removed');

    // Creator-scoped stats from /creator/dashboard/overview are what shows.
    expect(find.text('My Stats'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
    expect(find.text('Participants'), findsOneWidget);
    expect(find.text('245'), findsOneWidget,
        reason: 'totalParticipants from the overview summary');
    expect(find.text('71'), findsOneWidget,
        reason: 'totalStars from the overview summary');
  });
}
