import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenges_service.dart';

// Report & block (backend ADR 117): the backend can only leave out the viewer's blocked
// accounts if it knows who's asking. The challenge list, a challenge and the
// per-challenge leaderboard used to be fetched anonymously, so a blocked player stayed
// on the challenge board.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final seen = <String, String?>{};

  setUp(() {
    seen.clear();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'tok',
      'api_refresh_token': 'ref',
      'api_user_id': 'me',
    });
    SharedPreferences.setMockInitialValues({});
    ApiClient.httpClient = MockClient((r) async {
      seen[r.url.path] = r.headers['Authorization'];
      final data = r.url.path.endsWith('/submissions')
          ? {'submissions': []}
          : r.url.path.endsWith('/challenges')
              ? {'challenges': []}
              : {'challenge': {'_id': 'c1'}};
      return http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  test('challenge list, a challenge and its leaderboard are fetched signed in', () async {
    final svc = ChallengesService();
    await svc.fetchChallenges();
    await svc.fetchChallenge('c1');
    await svc.fetchSubmissions('c1');

    expect(seen.values, everyElement('Bearer tok'));
    expect(seen.keys.where((p) => p.contains('/challenges')), hasLength(3));
  });
}
