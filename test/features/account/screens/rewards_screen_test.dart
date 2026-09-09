import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/account/screens/rewards_screen.dart';

// RewardsScreen shows two backend-distinct tracks: /profile/rewards (coupons
// + aura bonuses) and /profile/offer-vouchers (brand Leaderboard Offer
// vouchers). Both sections must render, an unclaimed coupon must offer
// "Claim", and a GRANTED voucher with a redeemUrl must offer "Redeem".
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

  // The real backend serves UTF-8 JSON; http.Response defaults to latin1 for
  // a bare string body, which throws on non-Latin1 chars (e.g. ₹ in a
  // voucher value). Mirror the real content-type so the decode path matches.
  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // A tall surface so the whole scroll view is on-stage — otherwise a card in
  // the second section renders but sits below the fold and `find.text`
  // (which skips off-stage widgets) misses it.
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('renders both sections, a claimable coupon and a redeemable voucher',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile/rewards')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                '_id': 'r1',
                'rewardType': 'coupon_code',
                'reason': 'streak_completion',
                'status': 'active',
                'couponValue': '10% off your next order',
              },
            ],
          },
        });
      }
      if (path.endsWith('/profile/offer-vouchers')) {
        return json({
          'status': 'success',
          'data': {
            'responses': [
              {
                'code': 'K7Q2M9X4RT',
                'status': 'GRANTED',
                'rankAtGrant': 6,
                'offerName': 'Summer Top 10',
                'voucherValue': '₹200',
                'redeemUrl': 'https://brand.example.com/redeem',
                'claimExpiresAt': '2099-01-01T00:00:00.000Z',
              },
            ],
          },
        });
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('COUPONS & BONUSES'), findsOneWidget);
    expect(find.text('LEADERBOARD VOUCHERS'), findsOneWidget);

    // Coupon reward: labelled by reason, still claimable (no code revealed).
    expect(find.text('Streak Bonus'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Claim'), findsOneWidget);

    // Voucher: offer name, code and a Redeem action.
    expect(find.text('Summer Top 10'), findsOneWidget);
    expect(find.text('K7Q2M9X4RT'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Redeem'), findsOneWidget);
  });

  testWidgets('shows per-section empty lines when the backend returns nothing',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      return json({'status': 'success', 'data': {'responses': []}});
    });

    await useTallSurface(tester);
    await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No coupons or bonuses yet'), findsOneWidget);
    expect(find.textContaining('top ranks to win brand vouchers'), findsOneWidget);
  });
}
