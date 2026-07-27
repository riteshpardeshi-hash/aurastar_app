import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/explore/screens/explore_creators_screen.dart';

// Regression coverage: this screen used to query a Firestore `challenges`
// collection directly (`.where('creatorId', isNotEqualTo: 'system')`) to
// derive a creator list, and a Firestore `users` doc per creator for their
// name. Neither collection is ever written by the real backend (creators
// live in REST/Mongo, fetched via GET /creators) — so "Trending Creators →
// See All" always rendered an empty list. Fixed by routing through
// CreatorsService.fetchCreators, same as the trending-creators shelf on the
// home feed that links into this screen.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('loads creators from GET /creators, not Firestore',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/creators')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'creators': [
                {'_id': 'creator-1', 'displayName': 'Nova Brand', 'avatar': ''},
              ],
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: ExploreCreatorsScreen()));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('Nova Brand'), findsOneWidget);
    expect(find.text('No creators found.'), findsNothing);
  });

  testWidgets('shows an empty state, not an infinite Firestore spinner, '
      'when no creators come back', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'creators': []},
        }),
        200,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: ExploreCreatorsScreen()));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('No creators found.'), findsOneWidget);
  });
}
