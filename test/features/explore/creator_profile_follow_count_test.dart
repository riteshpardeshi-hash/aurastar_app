import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/explore/screens/creator_profile_screen.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// Found in phone QA: Follow flipped the button to "Following" but the
// Followers stat stayed at the old number until the page was reopened.
void main() {
  late FakeAiAdsBackend backend;
  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('following / unfollowing moves the Followers count right away', (tester) async {
    backend
      ..on('GET /creators/u9', {
        'creator': {'_id': 'u9', 'displayName': 'Riya', 'username': 'riya'},
        'isFollowing': false,
      })
      ..on('GET /creators/u9/followers', {
        'pagination': {'total': 43},
      })
      ..on('POST /creators/u9/follow', <String, dynamic>{})
      ..on('DELETE /creators/u9/follow', <String, dynamic>{});

    await pumpAiScreen(tester, const CreatorProfileScreen(creatorId: 'u9'));
    expect(find.text('43'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await settle(tester);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('44'), findsOneWidget);

    await tester.tap(find.text('Following'));
    await settle(tester);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
  });

  testWidgets('a failed follow leaves the count alone', (tester) async {
    backend
      ..on('GET /creators/u9', {
        'creator': {'_id': 'u9', 'displayName': 'Riya', 'username': 'riya'},
        'isFollowing': false,
      })
      ..on('GET /creators/u9/followers', {
        'pagination': {'total': 43},
      })
      ..fail('POST /creators/u9/follow', 409, 'Already following');

    await pumpAiScreen(tester, const CreatorProfileScreen(creatorId: 'u9'));
    await tester.tap(find.text('Follow'));
    await settle(tester);

    expect(find.text('43'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
  });
}
