import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/rewards_service.dart';

// RewardsService owns both player reward tracks:
//  - /profile/rewards        — the UserReward ledger (coupons + aura bonuses)
//  - /profile/offer-vouchers — brand Leaderboard Offer vouchers (ADR 082)
// plus /challenges/{id}/offers/claim for the legacy per-challenge claim pool.
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

  // ── /profile/rewards ──────────────────────────────────────────────────

  test('fetchRewards hits GET /profile/rewards and returns the UserReward list',
      () async {
    String? path;
    ApiClient.httpClient = MockClient((request) async {
      path = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'responses': [
              {
                '_id': 'r1',
                'rewardType': 'coupon_code',
                'reason': 'streak_completion',
                'status': 'active',
              },
            ],
          },
        }),
        200,
      );
    });

    final result = await RewardsService().fetchRewards();

    expect(path!.endsWith('/profile/rewards'), isTrue,
        reason: 'expected GET /profile/rewards, got $path');
    expect(result.single['_id'], 'r1');
    expect(result.single['rewardType'], 'coupon_code');
  });

  test('fetchRewards forwards the status filter', () async {
    String? query;
    ApiClient.httpClient = MockClient((request) async {
      query = request.url.query;
      return http.Response(
          jsonEncode({'status': 'success', 'data': {'responses': []}}), 200);
    });

    await RewardsService().fetchRewards(status: 'claimed');

    expect(query, contains('status=claimed'));
  });

  test('claimReward POSTs /profile/rewards/{id}/claim and returns the reward',
      () async {
    String? path;
    ApiClient.httpClient = MockClient((request) async {
      path = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'reward': {
              '_id': 'r1',
              'status': 'claimed',
              'couponCode': 'ABC123DEF456',
            },
          },
        }),
        200,
      );
    });

    final result = await RewardsService().claimReward('r1');

    expect(path!.endsWith('/profile/rewards/r1/claim'), isTrue,
        reason: 'expected POST /profile/rewards/r1/claim, got $path');
    expect(result?['status'], 'claimed');
    expect(result?['couponCode'], 'ABC123DEF456');
  });

  test('claimReward returns null without throwing on a 409 (already claimed)',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 409);
    });

    expect(await RewardsService().claimReward('r1'), isNull);
  });

  // ── /profile/offer-vouchers ───────────────────────────────────────────

  test('fetchOfferVouchers hits GET /profile/offer-vouchers and unwraps the list',
      () async {
    String? path;
    String? query;
    ApiClient.httpClient = MockClient((request) async {
      path = request.url.path;
      query = request.url.query;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'responses': [
              {
                'code': 'K7Q2M9X4RT',
                'status': 'GRANTED',
                'rankAtGrant': 6,
                'redeemUrl': 'https://brand.example.com/redeem',
                'offerName': 'Summer Top 10',
              },
            ],
          },
        }),
        200,
      );
    });

    final result = await RewardsService().fetchOfferVouchers();

    expect(path!.endsWith('/profile/offer-vouchers'), isTrue,
        reason: 'expected GET /profile/offer-vouchers, got $path');
    expect(query, allOf(contains('page=1'), contains('limit=20')));
    expect(result.single['code'], 'K7Q2M9X4RT');
    expect(result.single['status'], 'GRANTED');
  });

  test('fetchOfferVouchers tolerates the alternate `vouchers` array key',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      // The endpoint is documented only as a generic success envelope, so the
      // array key is not guaranteed — the service falls back across names.
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'vouchers': [
              {'code': 'AAA', 'status': 'REDEEMED'},
            ],
          },
        }),
        200,
      );
    });

    final result = await RewardsService().fetchOfferVouchers();

    expect(result.single['code'], 'AAA');
  });

  test('fetchOfferVouchers returns [] on a backend error, no throw', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 500);
    });

    expect(await RewardsService().fetchOfferVouchers(), isEmpty);
  });

  test('fetchOfferVouchers passes ?type= through when given', () async {
    String? query;
    ApiClient.httpClient = MockClient((request) async {
      query = request.url.query;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'responses': []},
        }),
        200,
      );
    });

    await RewardsService().fetchOfferVouchers(type: 'level');

    expect(query, contains('type=level'));
  });

  // ── /challenges/{id}/offers/claim ────────────────────────────────────

  test('claimChallengeOffer POSTs /challenges/{id}/offers/claim', () async {
    String? path;
    String? method;
    ApiClient.httpClient = MockClient((request) async {
      path = request.url.path;
      method = request.method;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'code': 'ZZZ999', 'voucherLabel': 'Free Coffee'},
        }),
        200,
      );
    });

    final result = await RewardsService().claimChallengeOffer('chal-1');

    expect(method, 'POST');
    expect(path!.endsWith('/challenges/chal-1/offers/claim'), isTrue,
        reason: 'expected POST /challenges/chal-1/offers/claim, got $path');
    expect(result?['code'], 'ZZZ999');
  });

  test('claimChallengeOffer returns null without throwing on 409 (out of stock)',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'fail'}), 409);
    });

    expect(await RewardsService().claimChallengeOffer('chal-1'), isNull);
  });
}
