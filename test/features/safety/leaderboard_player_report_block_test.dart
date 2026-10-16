import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/leaderboard/screens/challenge_leaderboard_screen.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// Players have no profile screen (profiles are private), so a leaderboard row is where
// another player can be reported or blocked (backend ADR 117). Tapping one used to show
// only a "profiles are private" toast — with no way to report or block that player.
void main() {
  late FakeAiAdsBackend backend;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    backend = FakeAiAdsBackend();
    backend.on('GET /profile', {'user': {'_id': 'me', 'displayName': 'Me'}});
    backend.on('GET /challenges/ch1/submissions', {
      'submissions': [
        {'_id': 's1', 'userId': {'_id': 'p7', 'displayName': 'Kabir', 'username': 'kabir'}, 'aiScore': 88, 'starsCount': 3},
      ],
    });
  });
  tearDown(FakeAiAdsBackend.reset);

  Future<void> openPlayer(WidgetTester tester) async {
    await pumpAiScreen(tester, const ChallengeLeaderboardScreen(challengeId: 'ch1', challengeTitle: 'Dance'));
    await tester.tap(find.text('@kabir'));
    await settle(tester);
  }

  testWidgets('tapping a player opens report and block, under the private-profile note', (tester) async {
    await openPlayer(tester);

    expect(find.textContaining('Player profiles are private'), findsOneWidget);
    expect(find.byKey(const Key('safety-report-account')), findsOneWidget);
    expect(find.byKey(const Key('safety-block-account')), findsOneWidget);
  });

  testWidgets('reporting the player sends it for that player id', (tester) async {
    backend.on('POST /users/p7/report', {'alreadyReported': false}, status: 201);
    await openPlayer(tester);

    await tester.tap(find.byKey(const Key('safety-report-account')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-reason-spam')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-report-send')));
    await settle(tester);

    expect(backend.calls('POST', '/users/p7/report').single.body, {'reason': 'spam'});
  });

  testWidgets('blocking the player reloads the board without them', (tester) async {
    backend.on('POST /users/p7/block', {'blocked': true});
    await openPlayer(tester);

    await tester.tap(find.byKey(const Key('safety-block-account')));
    await settle(tester);
    // The board the API returns after the block no longer has them.
    backend.on('GET /challenges/ch1/submissions', {'submissions': []});
    await tester.tap(find.byKey(const Key('safety-block-confirm')));
    await settle(tester);

    expect(backend.calls('POST', '/users/p7/block'), hasLength(1));
    expect(backend.calls('GET', '/challenges/ch1/submissions'), hasLength(2));
    expect(find.text('@kabir'), findsNothing);
  });
}
