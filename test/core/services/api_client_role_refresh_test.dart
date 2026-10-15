import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creator_page_service.dart';

// Regression (backend ADR 132): a user promoted to creator kept a "player" access token for up to
// 15 minutes, and every creator call came back 403 "Access denied. Requires one of: creator" —
// the client only refreshed on 401. Now a role-refused 403 refreshes once and retries, and the
// tokens returned by POST /creator/page are stored straight away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'player-token',
      'api_refresh_token': 'refresh-1',
      'api_user_id': 'user-1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  http.Response json(int status, Map<String, dynamic> body) => http.Response(jsonEncode(body), status);

  test('a role-refused 403 refreshes the token once and retries with the new role', () async {
    var refreshes = 0;
    ApiClient.httpClient = MockClient((req) async {
      if (req.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        return json(200, {'status': 'success', 'data': {'accessToken': 'creator-token', 'refreshToken': 'refresh-2'}});
      }
      if (req.headers['Authorization'] == 'Bearer creator-token') {
        return json(200, {'status': 'success', 'data': {'categories': ['Dance']}});
      }
      return json(403, {'status': 'fail', 'message': 'Access denied. Requires one of: creator'});
    });

    final res = await ApiClient().get('/creator/challenge/categories', auth: true);
    expect(res['status'], 'success');
    expect(refreshes, 1);
  });

  test('any other 403 is not retried', () async {
    var refreshes = 0;
    ApiClient.httpClient = MockClient((req) async {
      if (req.url.path.endsWith('/auth/refresh')) refreshes++;
      return json(403, {'status': 'fail', 'message': 'You are blocked by this creator.'});
    });

    final res = await ApiClient().get('/creators/x', auth: true);
    expect(res['message'], 'You are blocked by this creator.');
    expect(refreshes, 0);
  });

  test('creating a creator page stores the fresh creator tokens it returns', () async {
    final seen = <String?>[];
    ApiClient.httpClient = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      if (req.url.path.endsWith('/creator/page')) {
        return json(201, {
          'status': 'success',
          'data': {'status': 'ACTIVE', 'tokens': {'accessToken': 'creator-token', 'refreshToken': 'refresh-2'}},
        });
      }
      return json(200, {'status': 'success', 'data': {}});
    });

    await CreatorPageService().createPage(displayName: 'Ana', username: 'ana.films');
    await ApiClient().get('/creator/challenge/categories', auth: true);
    expect(seen.last, 'Bearer creator-token');
  });
}
