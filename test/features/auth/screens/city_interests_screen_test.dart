import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/auth/screens/city_interests_screen.dart';

// Regression coverage for "City ID must be a valid 24-character ID": a failed
// cities request used to fill the picker with hardcoded cities whose ids the
// backend rejects. The screen must instead show a retry row, and only offer
// cities that came from the backend.
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

  testWidgets(
    'a failed cities load shows a retry row, and retrying loads real cities',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var citiesUp = false;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/countries')) {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'countries': [
                  {'_id': indiaId, 'name': 'India', 'code': 'IN'},
                ],
              },
            }),
            200,
          );
        }
        if (!citiesUp) return http.Response('bad gateway', 502);
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'cities': [
                {'_id': mumbaiId, 'name': 'Mumbai'},
              ],
            },
          }),
          200,
        );
      });

      await tester.pumpWidget(const MaterialApp(home: CityInterestsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select your country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('India').last);
      await tester.pumpAndSettle();

      // Both attempts failed: a retry row, and no made-up cities on offer.
      expect(find.text("Couldn't load cities. Tap to retry."), findsOneWidget);

      citiesUp = true;
      await tester.tap(find.text("Couldn't load cities. Tap to retry."));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select your city'));
      await tester.pumpAndSettle();
      expect(find.text('Mumbai'), findsOneWidget);
    },
  );
}
