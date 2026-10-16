import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';

// ApiClient.send keeps the status code (the AI Ads flow branches on 402/409),
// refreshes once on 401 like the other verbs, and never throws on a non-JSON
// body (an HTML gateway error must surface as a readable failure).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'old',
      'api_refresh_token': 'refresh',
      'api_user_id': 'u1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  http.Response json(Map<String, dynamic> body, int status) => http.Response(jsonEncode(body), status);

  test('returns status, data and message without throwing on errors', () async {
    ApiClient.httpClient = MockClient((_) async => json({'status': 'fail', 'message': 'Out of credits'}, 402));

    final res = await ApiClient().send('POST', '/x', body: {'a': 1});

    expect(res.ok, isFalse);
    expect(res.statusCode, 402);
    expect(res.message, 'Out of credits');
  });

  test('sends the JSON body and the bearer token', () async {
    late http.Request seen;
    ApiClient.httpClient = MockClient((req) async {
      seen = req;
      return json({'status': 'success', 'data': {'ok': true}}, 201);
    });

    final res = await ApiClient().send('POST', '/x', body: {'expectedCredits': 4});

    expect(jsonDecode(seen.body), {'expectedCredits': 4});
    expect(seen.headers['Authorization'], 'Bearer old');
    expect(res.ok, isTrue);
    expect(res.data, {'ok': true});
  });

  test('a 401 refreshes once and retries with the new token', () async {
    final tokens = <String?>[];
    ApiClient.httpClient = MockClient((req) async {
      if (req.url.path.endsWith('/auth/refresh')) {
        return json({'status': 'success', 'data': {'accessToken': 'new', 'refreshToken': 'r2'}}, 200);
      }
      tokens.add(req.headers['Authorization']);
      return req.headers['Authorization'] == 'Bearer new'
          ? json({'status': 'success', 'data': 1}, 200)
          : json({'status': 'fail', 'message': 'jwt expired'}, 401);
    });

    final res = await ApiClient().send('GET', '/x');

    expect(tokens, ['Bearer old', 'Bearer new']);
    expect(res.data, 1);
  });

  test('a non-JSON body becomes a readable failure', () async {
    ApiClient.httpClient = MockClient((_) async => http.Response('<html>Bad gateway</html>', 502));

    final res = await ApiClient().send('GET', '/x');

    expect(res.ok, isFalse);
    expect(res.message, 'Unexpected response (502)');
  });

  test('an empty body is fine', () async {
    ApiClient.httpClient = MockClient((_) async => http.Response('', 204));
    final res = await ApiClient().send('DELETE', '/x');
    expect(res.ok, isTrue);
    expect(res.data, isNull);
  });
}
