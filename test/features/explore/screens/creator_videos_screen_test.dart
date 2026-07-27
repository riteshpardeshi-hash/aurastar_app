import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/explore/screens/creator_videos_screen.dart';

// Regression coverage: this screen queried a Firestore `challenges`
// collection directly (.where('creatorId', isNotEqualTo: 'system')) and a
// Firestore `users` doc per creator for the name chip — neither is ever
// written by the real backend. Fixed by routing through
// GET /challenges?sourceType=Brand (now available per the live spec) and
// GET /creators/{id} for the name chip, same REST sources the rest of the
// app already uses.
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

  testWidgets('loads brand challenges via GET /challenges?sourceType=Brand',
      (tester) async {
    String? capturedSourceType;

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/challenges')) {
        capturedSourceType = request.url.queryParameters['sourceType'];
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenges': [
                {
                  '_id': 'challenge-1',
                  'title': 'Brand Dance Challenge',
                  'videoUrl': '',
                  'starsCount': 42,
                  'creatorId': 'brand-1',
                  'sourceType': 'Brand',
                },
              ],
            },
          }),
          200,
        );
      }
      if (path.endsWith('/creators') && !path.contains('/creators/')) {
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'creators': []}}), 200);
      }
      if (path.endsWith('/creators/brand-1')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'displayName': 'Nova Brand', 'avatar': ''},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: CreatorVideosScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(capturedSourceType, 'Brand',
        reason: 'must filter to brand-created challenges via the REST '
            'sourceType param, not a Firestore query');
    expect(find.text('Brand Dance Challenge'), findsOneWidget);
    expect(find.text('Nova Brand'), findsOneWidget,
        reason: 'the creator name chip must resolve via GET /creators/{id}, '
            'not a Firestore users doc');
  });
}
