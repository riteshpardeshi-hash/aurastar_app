import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';

import 'ai_ads_fake_backend.dart';

// Apple 3.1.1 resubmission: AI ad campaign prizes (brand-awarded coupon codes) follow the
// coupons switch (ADR 119) — no "My rewards" entry while coupons are off.
void main() {
  late FakeAiAdsBackend backend;
  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET /creator/ai-campaigns', {'responses': []});
  });
  tearDown(() {
    FakeAiAdsBackend.reset();
    AppConfigService.instance.couponsEnabled.value = false;
  });

  testWidgets('the My rewards entry shows only while coupons are on', (tester) async {
    AppConfigService.instance.couponsEnabled.value = true;
    await pumpAiScreen(tester, const AiCampaignsScreen());
    expect(find.byTooltip('My rewards'), findsOneWidget);

    AppConfigService.instance.couponsEnabled.value = false;
    await tester.pump();
    expect(find.byTooltip('My rewards'), findsNothing);
  });
}
