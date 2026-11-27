import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/my_account_screen.dart';
import 'package:aura_app/features/account/screens/saved_challenges_screen.dart';
import 'package:aura_app/features/creator/screens/create_creator_profile_screen.dart';
import 'package:aura_app/features/leaderboard/leaderboard_screen.dart';
import 'package:aura_app/features/leaderboard/screens/challenge_leaderboard_screen.dart';

import '../../ai_ads/ai_ads_fake_backend.dart';

// Client, 26–27 Nov 2026: the profile is "social style" (option B) with
// your ranks as a card row under your name (B2) — @handle, avatar with
// Videos / Aura / Level beside it, highlight bubbles, Videos | Cards tabs.

Map<String, dynamic> get _ranks => {
      'global': {'rank': 2, 'total': 1240, 'score': 550},
      'country': {'_id': 'in', 'name': 'India', 'rank': 2, 'total': 900},
      'city': {'_id': 'amr', 'name': 'Amravati', 'rank': 1, 'total': 40},
      'challenges': [
        {'challengeId': 'ch1', 'title': 'FitNest Jump Rope', 'rank': 2, 'total': 12, 'bestScore': 88},
      ],
    };

void main() {
  late FakeAiAdsBackend backend;

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET /profile', {
      'user': {
        '_id': 'creator-1',
        'displayName': 'Yash',
        'profileName': 'yash',
        'role': 'player',
        'auraPoints': 550,
        'level': 6,
        'tier': 'rising',
        'city': {'name': 'Amravati'},
      },
    });
    backend.on('GET /referrals', {
      'referral': {'code': 'AURA42'}
    });
    backend.on('GET /leaderboard/me/ranks', _ranks);
  });
  tearDown(FakeAiAdsBackend.reset);

  Future<void> open(WidgetTester tester) async {
    await pumpAiScreen(tester, const MyAccountScreen());
  }

  testWidgets('header shows @handle, Videos / Aura / Level, name, tier and city', (tester) async {
    await open(tester);
    expect(find.text('@yash'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-count-aura')), matching: find.text('550')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-count-level')), matching: find.text('L6')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-tier-chip')), matching: find.text('Rising')),
        findsOneWidget);
    expect(find.text('Amravati'), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    expect(find.byKey(const Key('profile-share')), findsOneWidget);
    expect(find.byKey(const Key('profile-tab-ranks')), findsNothing, reason: 'ranks live in the row now');
  });

  // Client, 27 Nov 2026 (option B2): your ranks as a row of cards under your
  // name — best region rank first, then challenges most recently played first.
  testWidgets('the rank row shows the best region rank first, then challenges in server order',
      (tester) async {
    backend.on('GET /leaderboard/me/ranks', {
      ..._ranks,
      'challenges': [
        {'challengeId': 'recent', 'title': 'Played Today', 'rank': 5, 'total': 9, 'bestScore': 40},
        {'challengeId': 'ch1', 'title': 'FitNest Jump Rope', 'rank': 2, 'total': 12, 'bestScore': 88},
      ],
    });
    await open(tester);
    final keys = tester
        .widgetList(find.descendant(
            of: find.byKey(const Key('profile-rank-cards')),
            matching: find.byWidgetPredicate(
                (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('rank-card-'))))
        .map((w) => (w.key as ValueKey<String>).value)
        .toList();
    expect(keys, [
      'rank-card-region-city', // #1
      'rank-card-region-global', // #2
      'rank-card-region-country', // #2 (ties keep Global first)
      'rank-card-challenge-recent', // most recent
      'rank-card-challenge-ch1',
    ]);
    final city = find.byKey(const Key('rank-card-region-city'));
    expect(find.descendant(of: city, matching: find.text('#1')), findsOneWidget);
    expect(find.descendant(of: city, matching: find.text('GOAT 🐐')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('rank-card-region-global')), matching: find.text('top 1% 🔥')),
        findsOneWidget);
    expect(find.text('See All 5 >'), findsOneWidget);
  });

  testWidgets('a region card opens Aura Farmers on that board, a challenge card its board',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('rank-card-region-city')));
    await settle(tester);
    expect(tester.widget<LeaderboardScreen>(find.byType(LeaderboardScreen)).initialScope, 'city');

    Navigator.of(tester.element(find.byType(LeaderboardScreen))).pop();
    await settle(tester);
    await tester.dragUntilVisible(find.byKey(const Key('rank-card-challenge-ch1')),
        find.byKey(const Key('profile-rank-cards')), const Offset(-200, 0));
    await tester.tap(find.byKey(const Key('rank-card-challenge-ch1')));
    await settle(tester);
    final board = tester.widget<ChallengeLeaderboardScreen>(find.byType(ChallengeLeaderboardScreen));
    expect(board.challengeId, 'ch1');
    expect(board.challengeTitle, 'FitNest Jump Rope');
  });

  testWidgets('See All lists every rank, best region first', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('profile-ranks-see-all')));
    await settle(tester);
    expect(find.text('Your ranks 🏆'), findsOneWidget);
    expect(find.text('REGION'), findsOneWidget);
    expect(find.text('CHALLENGES'), findsOneWidget);
    final cityY = tester.getTopLeft(find.byKey(const Key('rank-region-city'))).dy;
    final globalY = tester.getTopLeft(find.byKey(const Key('rank-region-global'))).dy;
    expect(cityY, lessThan(globalY), reason: 'your #1 (city) comes before #2 (global)');
    expect(find.descendant(of: find.byKey(const Key('rank-challenge-ch1')), matching: find.text('best 88 · of 12')),
        findsOneWidget);
  });

  testWidgets('no ranks (or no endpoint) shows a Gen Z note instead of the row', (tester) async {
    backend.routes.remove('GET /leaderboard/me/ranks');
    await open(tester);
    expect(find.byKey(const Key('profile-rank-cards')), findsNothing);
    expect(find.byKey(const Key('profile-ranks-empty')), findsOneWidget);
    expect(find.textContaining('start farming aura'), findsOneWidget);
  });

  testWidgets('the Level count opens the level card', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('profile-count-level')));
    await settle(tester);
    expect(find.byKey(const Key('levelProgressRing')), findsOneWidget);
    expect(find.text('YOUR AURA POINTS'), findsOneWidget);
  });

  testWidgets('Invite highlight opens the referral sheet with the code', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('highlight-invite')));
    await settle(tester);
    expect(find.text('AURA42'), findsOneWidget);
    expect(find.text('SHARE REFERRAL LINK'), findsOneWidget);
    expect(find.text('VIEW REFERRED USERS'), findsOneWidget);
  });

  testWidgets('Creator highlight starts the creator application for a player', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('highlight-creator')));
    await settle(tester);
    expect(find.byType(CreateCreatorProfileScreen), findsOneWidget);
  });

  testWidgets('Saved highlight opens saved challenges', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('highlight-saved')));
    await settle(tester);
    expect(find.byType(SavedChallengesScreen), findsOneWidget);
  });

  testWidgets('Cards tab has an empty state until a challenge is scored', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('profile-tab-cards')));
    await settle(tester);
    expect(find.text('No cards yet'), findsOneWidget);
  });
}
