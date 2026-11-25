import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/ai_ads_service.dart';
import 'package:aura_app/features/ai_ads/screens/ai_campaign_screen.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_campaign_spotlight.dart';
import 'package:aura_app/features/creator/screens/create_creator_profile_screen.dart';

import 'ai_ads_fake_backend.dart';

// Client, 24 Nov: the home banner shows to every user. Someone who isn't a creator is asked
// to become one when they tap it, and goes to the creator application if they agree.
final _campaign = AiCampaignSummary(
  id: 'c1',
  title: 'Summer splash',
  deadline: DateTime.now().add(const Duration(days: 3)),
  brand: const AiBrandRef(id: 'b1', name: 'Fizzy Co'),
  format: const AiAdFormat(aspectRatio: '9:16', minDurationSeconds: 10, maxDurationSeconds: 15),
);

Future<void> _pump(WidgetTester tester, {required bool isCreator}) async {
  FakeAiAdsBackend(); // any request the next screen makes gets a fake answer
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AiCampaignSpotlight(loader: () async => [_campaign], fallback: const Text('FEATURED'), isCreator: isCreator),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('a player sees the banner; a tap asks them to become a creator, then opens the application', (tester) async {
    await _pump(tester, isCreator: false);
    expect(find.text('Summer splash'), findsOneWidget);

    await tester.tap(find.text('Summer splash'));
    await tester.pumpAndSettle();
    expect(find.text('Become a creator to join'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-become-creator')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CreateCreatorProfileScreen), findsOneWidget);
    expect(find.byType(AiCampaignScreen), findsNothing);
  });

  testWidgets('"Not now" leaves the player on the home, and See all asks too', (tester) async {
    await _pump(tester, isCreator: false);

    await tester.tap(find.text('See All >'));
    await tester.pumpAndSettle();
    expect(find.text('Become a creator to join'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Become a creator to join'), findsNothing);
    expect(find.byType(CreateCreatorProfileScreen), findsNothing);
    expect(find.text('Summer splash'), findsOneWidget);
  });

  testWidgets('a creator goes straight to the campaign, with no prompt', (tester) async {
    await _pump(tester, isCreator: true);
    await tester.tap(find.text('Summer splash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Become a creator to join'), findsNothing);
    expect(find.byType(AiCampaignScreen), findsOneWidget);
  });
}
