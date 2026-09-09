import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/auth_api_service.dart';

// Regression coverage for the "Refer a friend" card silently disappearing
// from MyAccountScreen: fetchReferralStats() was requesting the nonexistent
// path '/profile/referral' (per the live spec, the referral-code endpoint is
// GET /referrals — '/profile/referrals/list' is a different, paginated
// endpoint used by fetchReferralsList()). The bad path 404'd, the try/catch
// swallowed it into a null return, and _buildReferralCard responds to an
// empty referralCode by rendering SizedBox.shrink() with no visible error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  test('fetchReferralStats hits GET /referrals and returns the referral map',
      () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'referral': {'referralCode': 'SKW6GRR6', 'totalReferrals': 3},
          },
        }),
        200,
      );
    });

    final result = await AuthApiService().fetchReferralStats();

    expect(requestedPath!.endsWith('/referrals'), isTrue,
        reason: 'the referral-code endpoint per the live spec is GET '
            '/referrals, not /profile/referral (got $requestedPath)');
    expect(result?['referralCode'], 'SKW6GRR6');
    expect(result?['totalReferrals'], 3);
  });

  test('fetchReferralStats returns null when the backend 404s', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'fail', 'message': 'Not found'}),
        404,
      );
    });

    expect(await AuthApiService().fetchReferralStats(), isNull);
  });

  // Regression coverage for referral deep links being a no-op end-to-end:
  // main.dart stashes the incoming code in 'pending_referral_code' prefs, but
  // nothing ever sent it to the backend — setup_screen.dart just deleted the
  // pref on onboarding completion. AuthApiService had no method to apply a
  // code at all, so the deep link's captured code was silently discarded.
  test(
      'applyReferralCode POSTs the code to /referrals/apply and returns true '
      'on success', () async {
    String? requestedPath;
    Map<String, dynamic>? requestedBody;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await AuthApiService().applyReferralCode('SKW6GRR6');

    expect(requestedPath!.endsWith('/referrals/apply'), isTrue,
        reason: 'expected POST /referrals/apply, got $requestedPath');
    expect(requestedBody?['referralCode'], 'SKW6GRR6');
    expect(result, isTrue);
  });

  test(
      'applyReferralCode returns false without throwing when the code was '
      'already used (409)', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'fail', 'message': 'Code already used'}),
        409,
      );
    });

    expect(await AuthApiService().applyReferralCode('SKW6GRR6'), isFalse);
  });

  test('fetchReferralStatsDetail hits GET /referrals/stats and returns the stats map',
      () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'totalReferrals': 4, 'auraEarned': 200, 'recentActivity': []},
        }),
        200,
      );
    });

    final result = await AuthApiService().fetchReferralStatsDetail();

    expect(requestedPath!.endsWith('/referrals/stats'), isTrue,
        reason: 'expected GET /referrals/stats, got $requestedPath');
    expect(result?['totalReferrals'], 4);
    expect(result?['auraEarned'], 200);
  });

  test('fetchReferralStatsDetail returns null when the backend errors', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 500);
    });

    expect(await AuthApiService().fetchReferralStatsDetail(), isNull);
  });

  // Rewards / leaderboard-voucher coverage moved to
  // test/core/services/rewards_service_test.dart alongside RewardsService.
}
