import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/models/aura_tier.dart';
import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/shared/widgets/level_up_sheet.dart';

// A tier's "Unlocked: …" line is a coupon perk — hidden while coupons are off (ADR 119).
void main() {
  tearDown(() => AppConfigService.instance.couponsEnabled.value = true);

  Future<void> pumpSheet(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LevelUpSheet(level: 5, tier: auraTierForLevel(5)))),
      );

  testWidgets('shows the unlocked perk while coupons are on', (tester) async {
    AppConfigService.instance.couponsEnabled.value = true;
    await pumpSheet(tester);
    expect(find.textContaining('Unlocked:'), findsOneWidget);
  });

  testWidgets('hides the unlocked perk while coupons are off', (tester) async {
    AppConfigService.instance.couponsEnabled.value = false;
    await pumpSheet(tester);
    expect(find.textContaining('Unlocked:'), findsNothing);
    expect(find.textContaining('Rising'), findsWidgets);
  });
}
