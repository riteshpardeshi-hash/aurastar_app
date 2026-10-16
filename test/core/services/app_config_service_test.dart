import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/app_config_service.dart';

// The coupons on/off switch (backend ADR 119) as the app sees it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = AppConfigService.instance;

  http.Response config(bool coupons) => http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'features': {'coupons': coupons},
          },
        }),
        200,
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    svc.couponsEnabled.value = true;
  });

  tearDown(() => ApiClient.httpClient = http.Client());

  test('reads features.coupons from GET /app/config and remembers it', () async {
    ApiClient.httpClient = MockClient((r) async {
      expect(r.url.path, endsWith('/app/config'));
      return config(false);
    });

    await svc.refresh();

    expect(svc.couponsEnabled.value, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('app_config.coupons_enabled'), isFalse);
  });

  test('a cold start restores the remembered value before the network answers', () async {
    SharedPreferences.setMockInitialValues({'app_config.coupons_enabled': false});
    ApiClient.httpClient = MockClient((_) async => http.Response('nope', 500));

    await svc.init();

    expect(svc.couponsEnabled.value, isFalse);
  });

  test('a failed or malformed fetch keeps the last known value', () async {
    svc.couponsEnabled.value = false;
    ApiClient.httpClient = MockClient((_) async => http.Response(jsonEncode({'status': 'success', 'data': {}}), 200));

    await svc.refresh();

    expect(svc.couponsEnabled.value, isFalse);
  });
}
