import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/brands_service.dart';

// Endpoint-shape coverage for the new (previously fully unintegrated) Brands
// tag. Also guards the routing bug this integration fixed: search_screen.dart
// used to send 'Brand' search-result taps to CreatorProfileScreen (backed by
// GET /creators/{id}), which is the wrong collection for a Brand entity —
// these tests pin down the actual /brands/* request shapes that
// BrandProfileScreen now relies on instead.
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

  test('fetchBrand hits GET /brands/{id} and unwraps the brand map',
      () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'_id': 'b1', 'displayName': 'Acme Co', 'username': 'acme'},
        }),
        200,
      );
    });

    final raw = await BrandsService().fetchBrand('b1');

    expect(requestedPath!.endsWith('/brands/b1'), isTrue,
        reason: 'expected GET /brands/b1, got $requestedPath');
    final entry = normaliseBrand(raw!);
    expect(entry['id'], 'b1');
    expect(entry['displayName'], 'Acme Co');
  });

  test(
      'fetchBrand lifts the sibling isFollowing flag into the returned brand map',
      () async {
    // Live shape (verified 2026-08-27): the profile sits under `data.brand`
    // and `isFollowing` is a *sibling* of it, not a field inside it.
    // Regression: the old unwrap returned `data['brand']` verbatim, dropping
    // the flag, so BrandProfileScreen always showed "Follow" after reload.
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'brand': {'_id': 'b1', 'displayName': 'Acme Co'},
            'isFollowing': true,
          },
        }),
        200,
      );
    });

    final raw = await BrandsService().fetchBrand('b1');

    expect(raw!['isFollowing'], isTrue);
    expect(normaliseBrand(raw)['isFollowing'], isTrue);
  });

  test('fetchBrandChallenges hits GET /brands/{id}/challenges', () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'responses': [
              {'_id': 'c1', 'title': 'Dance Challenge'},
            ],
          },
        }),
        200,
      );
    });

    final raw = await BrandsService().fetchBrandChallenges('b1');

    expect(requestedPath!.endsWith('/brands/b1/challenges'), isTrue,
        reason: 'expected GET /brands/b1/challenges, got $requestedPath');
    expect(raw.single['title'], 'Dance Challenge');
  });

  test('followBrand POSTs to /brands/{id}/follow', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await BrandsService().followBrand('b1');

    expect(requestedMethod, 'POST');
    expect(requestedPath!.endsWith('/brands/b1/follow'), isTrue,
        reason: 'expected POST /brands/b1/follow, got $requestedPath');
    expect(result, isTrue);
  });

  test('unfollowBrand DELETEs /brands/{id}/follow', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await BrandsService().unfollowBrand('b1');

    expect(requestedMethod, 'DELETE');
    expect(requestedPath!.endsWith('/brands/b1/follow'), isTrue,
        reason: 'expected DELETE /brands/b1/follow, got $requestedPath');
    expect(result, isTrue);
  });

  test('normaliseBrand falls back across displayName/brandName/companyName and avatar/logo',
      () {
    expect(
      normaliseBrand({'brandName': 'Widgets Inc', 'logo': 'https://x/logo.png'})['displayName'],
      'Widgets Inc',
    );
    expect(
      normaliseBrand({'brandName': 'Widgets Inc', 'logo': 'https://x/logo.png'})['avatar'],
      'https://x/logo.png',
    );
    expect(
      normaliseBrand({'companyName': 'Fallback Co'})['displayName'],
      'Fallback Co',
    );
  });
}
