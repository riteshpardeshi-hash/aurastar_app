import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/leaderboard/leaderboard_screen.dart';

// Regression coverage: the Challenge tab used to fetch
// GET /leaderboard/challenge/{id} — confirmed against the live backend to
// always return an empty `responses` array even for challenges with real,
// scored public submissions (verified against two separate challenges with
// genuine submission activity). Every challenge board silently showed
// "No scores yet" regardless of real activity. Fixed by switching to
// GET /challenges/{id}/submissions (the endpoint the backend's own docs call
// "the public leaderboard"), which is confirmed to actually return data.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'my-id',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'Challenge tab uses GET /challenges/{id}/submissions, never the '
      'broken GET /leaderboard/challenge/{id}', (tester) async {
    var hitBrokenLeaderboardEndpoint = false;

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/leaderboard/challenge/')) {
        hitBrokenLeaderboardEndpoint = true;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'page': 1, 'totalCount': 0, 'totalPages': 0, 'responses': []},
          }),
          200,
        );
      }
      if (path.endsWith('/challenges')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenges': [
                {'_id': 'challenge-1', 'title': 'Knuckle Pushup Challenge'},
              ],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/submissions') && path.contains('/challenges/')) {
        // Mirrors the real, live response shape confirmed via manual curl
        // against the backend: userId is populated with only `_id`, and
        // starsCount is a real (undocumented-in-Swagger) field.
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submissions': [
                {
                  '_id': 'sub-1',
                  'userId': {'_id': 'player-1'},
                  'aiScore': 67,
                  'starsCount': 3,
                  'isPublic': true,
                },
              ],
              'pagination': {'total': 1, 'limit': 50, 'hasNextPage': false},
            },
          }),
          200,
        );
      }
      if (path.endsWith('/leaderboard') || path.endsWith('/leaderboard/friends')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'responses': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
    await tester.pump();
    await tester.tap(find.text('Challenge'));
    await tester.pumpAndSettle();

    expect(hitBrokenLeaderboardEndpoint, isFalse,
        reason: 'must not call the confirmed-broken /leaderboard/challenge '
            'endpoint');
    expect(find.text('67'), findsOneWidget,
        reason: 'the real aiScore from /challenges/{id}/submissions must '
            'render');
    expect(find.text('@Player 1'), findsOneWidget,
        reason: 'with no name available from the API, the row must show an '
            'honest rank-based label, not a blank or fabricated one');
    expect(find.text('No scores yet'), findsNothing);
  });

  testWidgets(
      'pulling to refresh on the Global tab re-fetches page 1 and replaces '
      'the list', (tester) async {
    var globalCallCount = 0;

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/leaderboard')) {
        globalCallCount++;
        final name = globalCallCount == 1 ? 'Original Player' : 'Refreshed Player';
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'responses': [
                {'_id': 'p1', 'displayName': name, 'auraPoints': 100},
              ],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/leaderboard/friends')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'responses': []}}), 200);
      }
      if (path.endsWith('/challenges')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'challenges': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: LeaderboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Original Player'), findsOneWidget);

    // Pull down to refresh.
    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(globalCallCount, greaterThanOrEqualTo(2),
        reason: 'pull-to-refresh must re-fetch page 1');
    expect(find.text('Refreshed Player'), findsOneWidget,
        reason: 'the refreshed data must replace the old list');
    expect(find.text('Original Player'), findsNothing);
  });
}
