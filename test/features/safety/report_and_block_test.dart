import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/blocked_accounts_screen.dart';
import 'package:aura_app/features/explore/screens/creator_profile_screen.dart';
import 'package:aura_app/shared/widgets/safety_sheets.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// Report and block (backend ADR 117): the ⋯ menu, the report sheet, the block
// confirmation, Settings → Blocked accounts, and a profile the API won't show.
void main() {
  late FakeAiAdsBackend backend;
  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  Future<void> openMenu(WidgetTester tester, {VoidCallback? onBlocked, bool isBrand = false}) async {
    await pumpAiScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showProfileSafetyMenu(context, userId: 'u9', name: 'Riya', isBrand: isBrand, onBlocked: onBlocked),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('report an account: pick a reason, add details, send — and the reporter is thanked', (tester) async {
    backend.on('POST /users/u9/report', {'alreadyReported': false}, status: 201);
    await openMenu(tester);

    await tester.tap(find.byKey(const Key('safety-report-account')));
    await settle(tester);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('safety-report-send'))).onPressed, isNull); // no reason yet
    await tester.tap(find.byKey(const Key('safety-reason-harassment')));
    await tester.enterText(find.byKey(const Key('safety-report-details')), 'Keeps sending abuse');
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-report-send')));
    await settle(tester);

    expect(backend.calls('POST', '/users/u9/report').single.body, {'reason': 'harassment', 'details': 'Keeps sending abuse'});
    expect(find.textContaining("Thanks — we'll review it"), findsOneWidget);
  });

  testWidgets('reporting again says it is already under review', (tester) async {
    backend.on('POST /users/u9/report', {'alreadyReported': true});
    await openMenu(tester);
    await tester.tap(find.byKey(const Key('safety-report-account')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-reason-spam')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-report-send')));
    await settle(tester);

    expect(find.textContaining("already reported this"), findsOneWidget);
  });

  testWidgets('block asks first and explains what happens; cancel does nothing, confirm blocks', (tester) async {
    var blocked = 0;
    backend.on('POST /users/u9/block', {'blocked': true});
    await openMenu(tester, onBlocked: () => blocked++, isBrand: true);

    await tester.tap(find.byKey(const Key('safety-block-account')));
    await settle(tester);
    expect(find.text('Block Riya?'), findsOneWidget);
    expect(find.textContaining("challenges, ads or AI ad campaigns"), findsOneWidget); // brand wording
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(backend.calls('POST', '/users/u9/block'), isEmpty);

    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-block-account')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-block-confirm')));
    await settle(tester);

    expect(backend.calls('POST', '/users/u9/block'), hasLength(1));
    expect(blocked, 1);
    expect(find.textContaining('Blocked Riya'), findsOneWidget);
  });

  testWidgets('Blocked accounts lists who you blocked and unblocks them', (tester) async {
    backend.on('GET /users/blocked', {
      'responses': [
        {'_id': 'u9', 'displayName': 'Riya', 'profileName': 'riya', 'role': 'creator'},
        {'_id': 'b1', 'displayName': 'Fizz Soda', 'role': 'brand'},
      ],
    });
    backend.on('DELETE /users/u9/block', {'blocked': false});
    await pumpAiScreen(tester, const BlockedAccountsScreen());

    expect(find.text('Riya'), findsOneWidget);
    expect(find.text('@riya · Creator'), findsOneWidget);
    expect(find.text('Brand'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unblock-u9')));
    await settle(tester);

    expect(backend.calls('DELETE', '/users/u9/block'), hasLength(1));
    expect(find.text('Riya'), findsNothing);
    expect(find.text('Fizz Soda'), findsOneWidget);
  });

  testWidgets('Blocked accounts shows how to block when the list is empty', (tester) async {
    backend.on('GET /users/blocked', {'responses': []});
    await pumpAiScreen(tester, const BlockedAccountsScreen());

    expect(find.textContaining("You haven't blocked anyone"), findsOneWidget);
  });

  testWidgets("a profile the API won't show (blocked either way, or gone) says it isn't available", (tester) async {
    // No fake for GET /creators/u9 → 404, exactly what a blocked pair gets.
    await pumpAiScreen(tester, const CreatorProfileScreen(creatorId: 'u9'));

    expect(find.byKey(const Key('profile-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('profile-safety-menu')), findsNothing);
  });
}
