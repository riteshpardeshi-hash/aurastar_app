import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/account/screens/rewards_screen.dart';

// Regression coverage for: (1) rewards/vouchers now render in a two-column
// grid, not a stacked full-width list; (2) a reward's server-resolved
// refTitle (or, absent that, a granted date) is shown so two same-`reason`
// rewards are distinguishable; (3) level-up and leaderboard-finish vouchers
// are split into their own correctly-labelled sections instead of both
// being dumped under "LEADERBOARD VOUCHERS".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('lays reward cards out two-per-row', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile/rewards')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                '_id': 'r1',
                'rewardType': 'aura_points',
                'reason': 'leaderboard_top',
                'status': 'active',
                'auraAmount': 500,
                'awardedAt': '2026-09-01T00:00:00.000Z',
              },
              {
                '_id': 'r2',
                'rewardType': 'aura_points',
                'reason': 'leaderboard_top',
                'status': 'active',
                'auraAmount': 500,
                'awardedAt': '2026-09-05T00:00:00.000Z',
              },
            ],
          },
        });
      }
      return json({'status': 'success', 'data': {'responses': []}});
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    final cardOne = tester.getTopLeft(find.text('Won on Sep 1').hitTestable());
    final cardTwo = tester.getTopLeft(find.text('Won on Sep 5').hitTestable());
    // Two-per-row: same row (near-equal y), different column (different x).
    expect((cardOne.dy - cardTwo.dy).abs(), lessThan(5));
    expect(cardOne.dx, isNot(closeTo(cardTwo.dx, 5)));
  });

  testWidgets('shows the resolved refTitle instead of a bare reason label',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile/rewards')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                '_id': 'r1',
                'rewardType': 'aura_points',
                'reason': 'challenge_participant_target',
                'status': 'active',
                'auraAmount': 75,
                'refTitle': 'Milestone Challenge',
              },
            ],
          },
        });
      }
      return json({'status': 'success', 'data': {'responses': []}});
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Milestone Challenge'), findsOneWidget);
  });

  testWidgets('two same-reason rewards without a refTitle are distinguished by date',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile/rewards')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                '_id': 'r1',
                'rewardType': 'aura_points',
                'reason': 'leaderboard_top',
                'status': 'active',
                'auraAmount': 500,
                'awardedAt': '2026-09-01T00:00:00.000Z',
              },
              {
                '_id': 'r2',
                'rewardType': 'aura_points',
                'reason': 'leaderboard_top',
                'status': 'active',
                'auraAmount': 500,
                'awardedAt': '2026-09-05T00:00:00.000Z',
              },
            ],
          },
        });
      }
      return json({'status': 'success', 'data': {'responses': []}});
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Won on Sep 1'), findsOneWidget);
    expect(find.text('Won on Sep 5'), findsOneWidget);
  });

  testWidgets('splits level-up and leaderboard vouchers into their own sections',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile/offer-vouchers')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                'code': 'LEVELCODE1',
                'status': 'GRANTED',
                'levelAtGrant': 529,
                'offerName': 'Level 529 Reward',
              },
              {
                'code': 'RANKCODE1',
                'status': 'GRANTED',
                'rankAtGrant': 1,
                'offerName': 'Top 10',
              },
            ],
          },
        });
      }
      return json({'status': 'success', 'data': {'responses': []}});
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('LEVEL-UP VOUCHERS'), findsOneWidget);
    expect(find.text('LEADERBOARD VOUCHERS'), findsOneWidget);

    final levelHeader = tester.getTopLeft(find.text('LEVEL-UP VOUCHERS'));
    final levelCard = tester.getTopLeft(find.text('Level 529 Reward'));
    final leaderboardHeader = tester.getTopLeft(find.text('LEADERBOARD VOUCHERS'));
    final rankCard = tester.getTopLeft(find.text('Top 10'));

    // The level voucher renders between its own header and the leaderboard
    // header; the rank voucher renders below the leaderboard header.
    expect(levelCard.dy, greaterThan(levelHeader.dy));
    expect(levelCard.dy, lessThan(leaderboardHeader.dy));
    expect(rankCard.dy, greaterThan(leaderboardHeader.dy));
  });
}
