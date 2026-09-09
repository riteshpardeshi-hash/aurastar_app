import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/home_service.dart';

// Regression coverage for home banners never registering a click: the
// carousel fetches via GET /home/banners but nothing called
// POST /banners/{id}/click, so the backend had zero click analytics on
// banners despite a fully working display carousel. Also pins down that the
// click endpoint lives under the plain /banners tag, not /home/banners/*.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  test('registerBannerClick POSTs to /banners/{id}/click', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    await HomeService().registerBannerClick('banner-1');

    expect(requestedMethod, 'POST');
    expect(requestedPath!.endsWith('/banners/banner-1/click'), isTrue,
        reason: 'expected POST /banners/banner-1/click, got $requestedPath');
  });

  test('registerBannerClick swallows errors without throwing', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await expectLater(
      HomeService().registerBannerClick('missing'),
      completes,
    );
  });
}
