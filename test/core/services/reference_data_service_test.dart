import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/reference_data_service.dart';

// Regression coverage for "Failed to save your location: City ID must be a
// valid 24-character ID": when GET /countries/:id/cities failed, the service
// silently returned a hardcoded fallback list whose ids ('IN_MUM', …) the
// backend can never accept, so Continue always failed afterwards. Reference
// data must now only ever come from the backend.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const indiaId = '60a1c1a2f3a4b5c6d7e8f001';
  const mumbaiId = '6a460014043cc1cca8ff4e56';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  http.Response citiesResponse(List<Map<String, dynamic>> cities) =>
      http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'cities': cities},
        }),
        200,
      );

  test(
    'fetchCities returns backend cities with id normalised from _id',
    () async {
      ApiClient.httpClient = MockClient(
        (_) async => citiesResponse([
          {'_id': mumbaiId, 'name': 'Mumbai'},
        ]),
      );

      final cities = await ReferenceDataService().fetchCities(indiaId);

      expect(cities.single['id'], mumbaiId);
      expect(cities.single['name'], 'Mumbai');
    },
  );

  test(
    'fetchCities retries once, then throws instead of returning fake-id cities',
    () async {
      var calls = 0;
      ApiClient.httpClient = MockClient((_) async {
        calls++;
        return http.Response('upstream timeout', 504);
      });

      await expectLater(
        ReferenceDataService().fetchCities(indiaId),
        throwsA(isA<ReferenceDataException>()),
      );
      expect(calls, 2);
    },
  );

  test('fetchCities recovers when the retry succeeds', () async {
    var calls = 0;
    ApiClient.httpClient = MockClient((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('connection reset');
      return citiesResponse([
        {'_id': mumbaiId, 'name': 'Mumbai'},
      ]);
    });

    final cities = await ReferenceDataService().fetchCities(indiaId);

    expect(cities.single['id'], mumbaiId);
  });

  test('fetchCities drops any entry whose id is not a backend id', () async {
    ApiClient.httpClient = MockClient(
      (_) async => citiesResponse([
        {'id': 'IN_MUM', 'name': 'Mumbai (bad)'},
        {'_id': mumbaiId, 'name': 'Mumbai'},
      ]),
    );

    final cities = await ReferenceDataService().fetchCities(indiaId);

    expect(cities.map((c) => c['id']), [mumbaiId]);
  });

  test(
    'fetchCities asks for up to 100 cities (the backend defaults to 20)',
    () async {
      Uri? requested;
      ApiClient.httpClient = MockClient((request) async {
        requested = request.url;
        return citiesResponse([]);
      });

      await ReferenceDataService().fetchCities(indiaId);

      expect(requested!.path.endsWith('/countries/$indiaId/cities'), isTrue);
      expect(requested!.queryParameters['limit'], '100');
    },
  );

  test('fetchCountries throws when the backend has none to offer', () async {
    ApiClient.httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'countries': []},
        }),
        200,
      ),
    );

    await expectLater(
      ReferenceDataService().fetchCountries(),
      throwsA(isA<ReferenceDataException>()),
    );
  });

  test('isBackendId accepts only 24-hex ids', () {
    expect(isBackendId(mumbaiId), isTrue);
    expect(isBackendId('IN_MUM'), isFalse);
    expect(isBackendId('IN'), isFalse);
    expect(isBackendId(null), isFalse);
  });
}
