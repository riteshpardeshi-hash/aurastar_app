import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';

// Regression coverage for the refresh-token race: the backend rotates
// refresh tokens on every use (single-use — see docs/api/openapi.yaml on
// /auth/refresh), so if several authenticated calls hit a 401 at the same
// moment (e.g. Dashboard firing 3 authed calls via Future.wait right as the
// access token expires), each one naively reading and POSTing the refresh
// token would mean only the first lands — the rest replay an already-revoked
// token, get rejected, and clearSession() wipes out the valid pair the first
// call just saved. ApiClient._tryRefresh() dedupes concurrent refresh
// attempts behind a single in-flight Future so this can't happen; these
// tests pin that behavior down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'expired-access-token',
      'api_refresh_token': 'valid-refresh-token',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  http.Response _success(Map<String, dynamic> data) =>
      http.Response(jsonEncode({'status': 'success', 'data': data}), 200);

  http.Response _unauthorized() => http.Response(
      jsonEncode({'status': 'fail', 'message': 'jwt expired'}), 401);

  test(
      '3 concurrent authed calls racing one expired token trigger only one '
      'refresh request, and all 3 succeed with the new token', () async {
    var refreshCalls = 0;
    var callsWithNewToken = 0;

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return _success({
          'accessToken': 'new-access-token',
          'refreshToken': 'new-refresh-token',
        });
      }

      if (request.headers['Authorization'] == 'Bearer new-access-token') {
        callsWithNewToken++;
        return _success({'ok': true});
      }

      // Still using the pre-refresh token — the backend would reject this.
      return _unauthorized();
    });

    final client = ApiClient();
    final results = await Future.wait([
      client.get('/profile', auth: true),
      client.get('/profile/streak', auth: true),
      client.get('/creator/page', auth: true),
    ]);

    expect(refreshCalls, 1,
        reason: 'only one refresh should hit the network even though all '
            '3 calls raced a 401 at the same time');
    expect(callsWithNewToken, 3);
    for (final r in results) {
      expect(r['status'], 'success');
    }

    // The refreshed pair must have survived — a pre-dedupe bug would have a
    // later, redundant refresh attempt fail (replaying a revoked token) and
    // clear the session out from under the first successful refresh.
    expect(await client.accessToken, 'new-access-token');
    expect(await client.refreshToken, 'new-refresh-token');
  });

  test(
      'when the refresh token is genuinely dead, concurrent 401s only clear '
      'the session and signal onSessionExpired once', () async {
    var refreshCalls = 0;
    var sessionExpiredEvents = 0;

    final sub = ApiClient.onSessionExpired.listen((_) {
      sessionExpiredEvents++;
    });

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return _unauthorized();
      }
      return _unauthorized();
    });

    final client = ApiClient();
    final results = await Future.wait([
      client.get('/profile', auth: true),
      client.get('/profile/streak', auth: true),
      client.get('/creator/page', auth: true),
    ]);

    expect(refreshCalls, 1,
        reason: 'a dead refresh token should still only be attempted once, '
            'not once per concurrent caller');
    for (final r in results) {
      expect(r['status'], 'fail');
    }
    expect(await client.accessToken, isNull);
    expect(await client.refreshToken, isNull);

    // Let the broadcast stream's microtask queue flush before asserting.
    await Future<void>.delayed(Duration.zero);
    expect(sessionExpiredEvents, 1);

    await sub.cancel();
  });

  // Regression coverage: POST /challenges/{id}/submissions runs a
  // synchronous, multi-step AI pipeline server-side (content moderation +
  // face verification + rubric scoring, each its own Gemini call — see
  // openapi.yaml) and can legitimately take well past ApiClient's default
  // 15s CRUD timeout. That was surfacing a real "video doesn't match"
  // verdict as a misleading "network error" screen because the client gave
  // up before the response arrived. post()'s optional `timeout` lets a
  // caller like ChallengesService.createSubmission opt into a longer
  // budget instead of being stuck with the CRUD default.
  test('post() honors a shorter custom timeout instead of the 15s default',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response(
          jsonEncode({'status': 'success', 'data': {}}), 200);
    });

    final client = ApiClient();
    await expectLater(
      client.post('/slow', {}, timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
      reason: 'a 50ms custom timeout should fire well before the 200ms '
          'mock response, proving the custom timeout — not the 15s '
          'default — is what governs this call',
    );
  });

  test(
      'post() with a longer custom timeout lets a slow-but-legitimate '
      'response through', () async {
    ApiClient.httpClient = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response(
          jsonEncode({'status': 'success', 'data': {'ok': true}}), 200);
    });

    final client = ApiClient();
    final res = await client.post(
      '/slow',
      {},
      timeout: const Duration(seconds: 2),
    );
    expect(res['status'], 'success',
        reason: 'a response slower than the 15s default would still be '
            'legitimate under a longer per-call timeout, and must not be '
            'misreported as a network failure');
  });
}
