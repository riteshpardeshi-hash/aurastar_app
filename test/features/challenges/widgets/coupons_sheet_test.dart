import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/challenges/widgets/coupons_sheet.dart';

// The sheet is the moment-of-delight after a submission wins one or more
// coupons (level-up + leaderboard offers). Each card branches on `sourcing`:
// POOL shows a big copyable code and an optional "Open offer"; CATALOG shows
// a primary "Shop now" and an optional code.
void main() {
  Future<void> pumpWithSheet(
    WidgetTester tester,
    List<Map<String, dynamic>> coupons,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCouponsSheet(context, coupons),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('POOL coupon: shows label, reason, code and Open offer',
      (tester) async {
    await pumpWithSheet(tester, [
      {
        'grantId': 'G2',
        'offerName': 'Summer Top 10',
        'sourcing': 'POOL',
        'voucherLabel': '₹200 Coffee Card',
        'code': 'K7Q2M9X4RT',
        'reason': 'Finished rank 6 — top 10 of the "Summer Top 10" offer',
        'redeemUrl': 'https://brand.example.com/redeem',
        'claimExpiresAt': '2099-01-01T00:00:00.000Z',
      },
    ]);

    expect(find.text('You won a coupon!'), findsOneWidget);
    expect(find.text('₹200 Coffee Card'), findsOneWidget);
    expect(find.textContaining('Finished rank 6'), findsOneWidget);
    expect(find.text('K7Q2M9X4RT'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open offer'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Shop now'), findsNothing);
  });

  testWidgets('CATALOG coupon: primary Shop now, code shown, merchant caption',
      (tester) async {
    await pumpWithSheet(tester, [
      {
        'grantId': 'G1',
        'offerName': 'Level 8 Reward',
        'sourcing': 'CATALOG',
        'voucherLabel': 'Flat 60% off fashion',
        'merchantName': 'AJIO',
        'code': 'AJIO60',
        'reason': 'Reached level 8 — "Level 8 Reward"',
        'redeemUrl': 'https://api.auraarena.app/api/v1/r/G1',
        'claimExpiresAt': '2099-01-01T00:00:00.000Z',
      },
    ]);

    expect(find.widgetWithText(ElevatedButton, 'Shop now'), findsOneWidget);
    expect(find.text('AJIO60'), findsOneWidget);
    expect(find.text('at AJIO'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open offer'), findsNothing);
  });

  testWidgets('CATALOG code-less deal: Shop now with no code chip',
      (tester) async {
    await pumpWithSheet(tester, [
      {
        'grantId': 'G3',
        'offerName': 'Mystery Deal',
        'sourcing': 'CATALOG',
        'code': null,
        'reason': 'Reached level 9',
        'redeemUrl': 'https://api.auraarena.app/api/v1/r/G3',
        'claimExpiresAt': '2099-01-01T00:00:00.000Z',
      },
    ]);

    expect(find.widgetWithText(ElevatedButton, 'Shop now'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('sourcing inferred from a /r/ redeemUrl when absent',
      (tester) async {
    await pumpWithSheet(tester, [
      {
        'offerName': 'Inferred Catalog',
        'code': 'X1',
        'redeemUrl': 'https://api.auraarena.app/api/v1/r/G9',
        'claimExpiresAt': '2099-01-01T00:00:00.000Z',
      },
    ]);

    expect(find.widgetWithText(ElevatedButton, 'Shop now'), findsOneWidget);
  });

  testWidgets('pluralises the header for more than one coupon', (tester) async {
    await pumpWithSheet(tester, [
      {'offerName': 'Offer A', 'sourcing': 'POOL', 'code': 'AAA'},
      {'offerName': 'Offer B', 'sourcing': 'POOL', 'code': 'BBB'},
    ]);

    expect(find.text('You won 2 coupons!'), findsOneWidget);
    expect(find.text('AAA'), findsOneWidget);
    expect(find.text('BBB'), findsOneWidget);
  });

  testWidgets('Done dismisses the sheet', (tester) async {
    await pumpWithSheet(tester, [
      {'offerName': 'Offer A', 'sourcing': 'POOL', 'code': 'AAA'},
    ]);
    expect(find.text('AAA'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('AAA'), findsNothing);
  });
}
