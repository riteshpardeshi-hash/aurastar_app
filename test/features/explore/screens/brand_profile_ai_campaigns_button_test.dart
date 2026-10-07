import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';
import 'package:aura_app/features/explore/screens/brand_profile_screen.dart';

import '../../ai_ads/ai_ads_fake_backend.dart';

// The brand page's "AI Ad Campaigns" entry point: AI ad campaigns are
// creator-only on the backend (requireRole("creator")), so players never see
// a button that would only lead to a 403. For creators it opens that brand's
// campaigns (GET /creator/ai-campaigns?brandId=…).
void main() {
  late FakeAiAdsBackend backend;

  void serveBrand({required String role}) {
    backend.on('GET /brands/b1', {
      'brand': {'_id': 'b1', 'displayName': 'Fizz Co', 'username': 'fizz', 'bio': '', 'website': ''},
      'isFollowing': false,
    });
    backend.on('GET /brands/b1/challenges', {'challenges': []});
    backend.on('GET /brands/b1/followers', {'totalCount': 0});
    backend.on('GET /profile', {'user': {'_id': 'u1', 'role': role}});
  }

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('a player does not see the AI campaigns button', (tester) async {
    serveBrand(role: 'player');
    await pumpAiScreen(tester, const BrandProfileScreen(brandId: 'b1'));

    expect(find.text('Fizz Co'), findsWidgets);
    expect(find.byKey(const Key('brand-ai-campaigns')), findsNothing);
  });

  testWidgets("a creator sees it, and it opens this brand's campaigns", (tester) async {
    serveBrand(role: 'creator');
    backend.on('GET /creator/ai-campaigns', {'responses': []});
    await pumpAiScreen(tester, const BrandProfileScreen(brandId: 'b1'));

    await tester.tap(find.byKey(const Key('brand-ai-campaigns')));
    await settle(tester);

    expect(find.byType(AiCampaignsScreen), findsOneWidget);
    expect(find.text('Fizz Co · AI ads'), findsOneWidget);
    expect(backend.calls('GET', '/creator/ai-campaigns').single.query['brandId'], 'b1');
  });
}
