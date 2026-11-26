import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenges_service.dart';
import 'package:aura_app/core/services/creator_challenges_service.dart';

// Client, 26 Nov 2026: difficulty is gone from Aura Arena altogether, so the
// app no longer sends it when a creator or brand makes a challenge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bodies = <Map<String, dynamic>>[];

  setUp(() {
    bodies.clear();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'creator-token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    ApiClient.httpClient = MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'challenge': {'_id': 'c1', 'title': 't'},
          },
        }),
        201,
      );
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  test('a creator draft is created without a difficulty', () async {
    await CreatorChallengesService().createDraft(
      title: 't',
      category: 'cat1',
      videoId: 'v1',
    );
    expect(bodies.single.containsKey('difficulty'), isFalse);
    expect(bodies.single['title'], 't');
  });

  test('a recorded challenge is created without a difficulty', () async {
    await ChallengesService().createChallenge(
      title: 't',
      description: 'd',
      categoryId: 'cat1',
      videoId: 'v1',
    );
    expect(bodies.single.containsKey('difficulty'), isFalse);
  });

  test('editing a draft never sends a difficulty', () async {
    await CreatorChallengesService().updateDraft('c1', title: 't2');
    expect(bodies.single.containsKey('difficulty'), isFalse);
  });
}
