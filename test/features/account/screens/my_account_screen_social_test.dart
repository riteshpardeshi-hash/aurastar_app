import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/my_account_screen.dart';
import 'package:aura_app/features/account/screens/saved_challenges_screen.dart';
import 'package:aura_app/features/creator/screens/create_creator_profile_screen.dart';
import 'package:aura_app/features/leaderboard/leaderboard_screen.dart';
import 'package:aura_app/features/leaderboard/screens/challenge_leaderboard_screen.dart';

import '../../ai_ads/ai_ads_fake_backend.dart';

// Client, 26 Nov 2026: the profile is "social style" (option B) — @handle,
// avatar with Videos / Aura / Global rank beside it, highlight bubbles, and
// Videos | Ranks | Cards tabs — with every rank on the Ranks tab (B3).

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

  testWidgets('header shows @handle, Videos / Aura / Global rank, name, tier and city', (tester) async {
    await open(tester);
    expect(find.text('@yash'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-count-aura')), matching: find.text('550')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-count-rank')), matching: find.text('#2')),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('profile-tier-chip')), matching: find.text('Rising')),
        findsOneWidget);
    expect(find.text('Amravati'), findsOneWidget);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    expect(find.byKey(const Key('profile-share')), findsOneWidget);
  });

  testWidgets('tapping the rank opens the Ranks tab with region and challenge ranks', (tester) async {
    await open(tester);
    expect(find.text('REGION'), findsNothing);
    await tester.tap(find.byKey(const Key('profile-count-rank')));
    await settle(tester);

    expect(find.text('REGION'), findsOneWidget);
    expect(find.text('CHALLENGES'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('rank-region-country')), matching: find.text('India')),
        findsOneWidget);
    final city = find.byKey(const Key('rank-region-city'));
    expect(find.descendant(of: city, matching: find.text('#1')), findsOneWidget);
    expect(find.descendant(of: city, matching: find.textContaining('GOAT')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('rank-challenge-ch1')), matching: find.text('best 88 · of 12')),
        findsOneWidget);
  });

  testWidgets('a region row opens Aura Farmers, a challenge row opens its board', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('profile-tab-ranks')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('rank-region-global')));
    await settle(tester);
    expect(find.byType(LeaderboardScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(LeaderboardScreen))).pop();
    await settle(tester);
    await tester.tap(find.byKey(const Key('rank-challenge-ch1')));
    await settle(tester);
    final board = tester.widget<ChallengeLeaderboardScreen>(find.byType(ChallengeLeaderboardScreen));
    expect(board.challengeId, 'ch1');
    expect(board.challengeTitle, 'FitNest Jump Rope');
  });

  testWidgets('Ranks tab has a Gen Z empty state when there are no ranks (or no endpoint)', (tester) async {
    backend.routes.remove('GET /leaderboard/me/ranks');
    await open(tester);
    expect(find.descendant(of: find.byKey(const Key('profile-count-rank')), matching: find.text('–')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-tab-ranks')));
    await settle(tester);
    expect(find.text('No ranks yet'), findsOneWidget);
    expect(find.textContaining('start farming aura'), findsOneWidget);
  });

  testWidgets('Level highlight opens the level card', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('highlight-level')));
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
