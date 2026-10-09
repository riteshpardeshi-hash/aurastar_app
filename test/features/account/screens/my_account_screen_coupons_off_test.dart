import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/features/account/screens/my_account_screen.dart';

// The coupons on/off switch (backend ADR 119): the profile's "Rewards & Vouchers" row is
// the coupon wallet's entry point, so it disappears while an admin has coupons off.
void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Test User',
                'auraPoints': 500,
                'level': 42,
                'tier': 'elite',
              },
            },
          }),
          200,
        );
      }
      // Everything else (videos/achievements/saved-challenges/referral/
      // streak) degrades gracefully to empty/null in AuthApiService, so a
      // generic failure response is fine for the rest of this screen's load.
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  tearDown(() => AppConfigService.instance.couponsEnabled.value = true);

  Future<void> pumpAccount(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MyAccountScreen()));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('shows the Rewards & Vouchers row while coupons are on', (tester) async {
    AppConfigService.instance.couponsEnabled.value = true;
    await pumpAccount(tester);
    await tester.scrollUntilVisible(find.text('Rewards & Vouchers'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Rewards & Vouchers'), findsOneWidget);
  });

  testWidgets('hides it while coupons are off, and shows it again when switched on', (tester) async {
    AppConfigService.instance.couponsEnabled.value = false;
    await pumpAccount(tester);
    expect(find.text('Rewards & Vouchers', skipOffstage: false), findsNothing);

    AppConfigService.instance.couponsEnabled.value = true;
    await tester.pump();
    expect(find.text('Rewards & Vouchers', skipOffstage: false), findsOneWidget);
  });
}
