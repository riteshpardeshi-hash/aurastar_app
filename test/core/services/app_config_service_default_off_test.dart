import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/app_config_service.dart';

// Apple 3.1.1: a fresh install must not show coupon UI before it knows the admin's
// coupons switch — so coupons start OFF and stay off if the first fetch fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install starts with coupons off, and a failed fetch keeps them off', () async {
    expect(AppConfigService.instance.couponsEnabled.value, isFalse);

    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ApiClient.httpClient = MockClient((_) async => http.Response('down', 503));
    await AppConfigService.instance.init();

    expect(AppConfigService.instance.couponsEnabled.value, isFalse);
    ApiClient.httpClient = http.Client();
  });
}
