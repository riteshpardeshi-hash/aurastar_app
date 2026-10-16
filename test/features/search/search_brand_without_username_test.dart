import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/search/search_screen.dart';

// Brands often have no username. Their search row used to read "Brand · @" (a dangling
// "@"); it now shows no handle at all, while creators keep "Creator · @handle".
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('a brand without a username shows no dangling "@"', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenges': [],
              'brands': [
                {'_id': 'b1', 'displayName': 'Fizz Soda', 'username': null, 'avatar': ''},
              ],
              'creators': [
                {'_id': 'c1', 'displayName': 'Riya', 'username': 'riya', 'avatar': ''},
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/search/recent')) {
        return http.Response(jsonEncode({'status': 'success', 'data': {'items': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'fi');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Fizz Soda'), findsOneWidget);
    expect(find.text('Brand · @'), findsNothing);
    expect(find.text('Creator · @riya'), findsOneWidget);
  });
}
