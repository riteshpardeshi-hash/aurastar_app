import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/features/account/screens/notification_preferences_screen.dart';

// Apple 3.1.1 resubmission: with coupons off (ADR 119) the notification settings must not
// mention offers anywhere — neither the "Offers & Rewards" category nor the push subtitle.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'player-1',
    });
    ApiClient.httpClient = MockClient((request) async => http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'preferences': {'pushEnabled': true, 'categories': {}, 'quietHours': {}},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));
  });
  tearDown(() => AppConfigService.instance.couponsEnabled.value = false);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationPreferencesScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('coupons off: no offers category and no offers wording', (tester) async {
    AppConfigService.instance.couponsEnabled.value = false;
    await pumpScreen(tester);

    expect(find.text('Score Results'), findsOneWidget);
    expect(find.text('Offers & Rewards'), findsNothing);
    expect(find.textContaining(RegExp('offer', caseSensitive: false)), findsNothing);
  });

  testWidgets('coupons on: the offers category is shown', (tester) async {
    AppConfigService.instance.couponsEnabled.value = true;
    await pumpScreen(tester);

    expect(find.text('Offers & Rewards'), findsOneWidget);
  });
}
