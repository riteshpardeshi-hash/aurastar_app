import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenges_service.dart';
import 'package:aura_app/core/services/creator_challenges_service.dart';

// Regression (2026-10-15): POST /creator/challenges runs the AI safety check on the reference
// video before answering — 25–90 s in production. With the default 15 s timeout the app showed
// "Couldn't reach Aura's servers" although the challenge WAS created, and creators retried
// into duplicate drafts. A 40 s response (the real "test create" timing) must succeed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'creator-token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  // testWidgets runs on fake time, so the 40 s server delay and the request timeout both
  // advance with tester.pump — no real waiting.
  testWidgets('creating a draft waits for a 40 s AI check instead of timing out at 15 s', (tester) async {
    ApiClient.httpClient = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 40));
      return http.Response(
        jsonEncode({'status': 'success', 'data': {'challenge': {'_id': 'c1', 'title': 'test create'}}}),
        201,
      );
    });

    Map<String, dynamic>? created;
    Object? error;
    CreatorChallengesService()
        .createDraft(title: 'test create', category: 'cat1', difficulty: 'Medium', videoId: 'v1')
        .then((c) => created = c)
        .catchError((Object e) {
      error = e;
      return <String, dynamic>{};
    });

    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(error, isNull);
    expect(created?['title'], 'test create');
  });

  testWidgets('creating a challenge from the record flow (POST /challenges) also waits for the AI check', (tester) async {
    ApiClient.httpClient = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 40));
      return http.Response(
        jsonEncode({'status': 'success', 'data': {'challenge': {'_id': 'c2', 'title': 'recorded'}}}),
        201,
      );
    });

    Map<String, dynamic>? created;
    Object? error;
    ChallengesService()
        .createChallenge(title: 'recorded', description: 'd', categoryId: 'cat1', difficulty: 'Medium', videoId: 'v2')
        .then((c) => created = c)
        .catchError((Object e) {
      error = e;
      return <String, dynamic>{};
    });

    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(error, isNull);
    expect(created?['title'], 'recorded');
  });
}
