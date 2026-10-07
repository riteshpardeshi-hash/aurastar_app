import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_rewards_screen.dart';

import 'ai_ads_fake_backend.dart';

// Rewards brands granted the creator: shown with campaign, value and coupon;
// only granted/fulfilled ones can be confirmed as received.
void main() {
  late FakeAiAdsBackend backend;

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('confirming a reward marks it received', (tester) async {
    var status = 'FULFILLED';
    backend.routes['GET /creator/ai-rewards'] = (_) => FakeAiAdsBackend.ok([
      {'_id': 'w1', 'type': 'COUPON', 'title': '20% off', 'couponCode': 'FIZZ20', 'status': status, 'campaignId': {'title': 'Summer Fizz'}},
    ]);
    backend.routes['POST /creator/ai-rewards/w1/received'] = (_) {
      status = 'RECEIVED';
      return FakeAiAdsBackend.ok({'_id': 'w1', 'type': 'COUPON', 'title': '20% off', 'status': status});
    };
    await pumpAiScreen(tester, const AiRewardsScreen());

    expect(find.text('Summer Fizz'), findsOneWidget);
    expect(find.text('FIZZ20'), findsOneWidget);
    expect(find.text('The brand says it was sent'), findsOneWidget);
    await tester.tap(find.text('I got it'));
    await settle(tester);

    expect(backend.calls('POST', '/creator/ai-rewards/w1/received'), hasLength(1));
    expect(find.text('Received ✓'), findsOneWidget);
    expect(find.text('I got it'), findsNothing);
  });

  testWidgets('no rewards yet', (tester) async {
    backend.on('GET /creator/ai-rewards', []);
    await pumpAiScreen(tester, const AiRewardsScreen());
    expect(find.text('No rewards yet — win a campaign to get one.'), findsOneWidget);
  });
}
