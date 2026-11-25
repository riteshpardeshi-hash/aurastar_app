import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';

import 'ai_ads_fake_backend.dart';

// Client request: a search bar on the AI ad campaigns list. Typing filters the list by
// campaign name or brand name only (not product or brief); it works together with the
// Joined filter, says so when nothing matches, and the clear button brings the list back.
void main() {
  tearDown(FakeAiAdsBackend.reset);

  Future<void> pumpList(WidgetTester tester) async {
    final backend = FakeAiAdsBackend();
    final soon = DateTime.now().add(const Duration(days: 2)).toIso8601String();
    backend.on('GET /creator/ai-campaigns', {
      'responses': [
        {
          '_id': 'a',
          'title': 'Summer splash',
          'deadline': soon,
          'brand': {'_id': 'b1', 'name': 'Fizzy Co'},
          'brief': {'product': 'Lemon soda'},
        },
        {
          '_id': 'b',
          'title': 'Crunch time',
          'deadline': soon,
          'brand': {'_id': 'b2', 'name': 'Snacko'},
          'brief': {'product': 'Potato chips'},
          'myStatus': 'ACTIVE',
        },
        {
          '_id': 'c',
          'title': 'Night run',
          'deadline': soon,
          'brand': {'_id': 'b3', 'name': 'Stride'},
          'brief': {'product': 'Running shoes', 'objective': 'Launch the marathon line'},
        },
      ],
    });
    await pumpAiScreen(tester, const AiCampaignsScreen());
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('ai-campaigns-search')), text);
    await settle(tester);
  }

  testWidgets('filters by campaign or brand name, case-insensitively, and nothing else', (tester) async {
    await pumpList(tester);
    expect(find.text('Summer splash'), findsOneWidget);
    expect(find.text('Crunch time'), findsOneWidget);
    expect(find.text('Night run'), findsOneWidget);

    await search(tester, 'night'); // campaign name
    expect(find.text('Night run'), findsOneWidget);
    expect(find.text('Summer splash'), findsNothing);
    expect(find.text('Crunch time'), findsNothing);

    await search(tester, 'FIZZY'); // brand name
    expect(find.text('Summer splash'), findsOneWidget);
    expect(find.text('Night run'), findsNothing);

    await search(tester, '  run   stride '); // campaign + brand words, any order, extra spaces
    expect(find.text('Night run'), findsOneWidget);
    expect(find.text('Summer splash'), findsNothing);

    await search(tester, 'chips'); // product: not searched
    expect(find.text('Crunch time'), findsNothing);

    await search(tester, 'marathon'); // objective: not searched
    expect(find.text('Night run'), findsNothing);
  });

  testWidgets('says so when nothing matches, and clearing brings the list back', (tester) async {
    await pumpList(tester);

    await search(tester, 'zzz');
    expect(find.text('No contests match "zzz".'), findsOneWidget);
    expect(find.text('Summer splash'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    expect(find.text('Summer splash'), findsOneWidget);
    expect(find.text('Crunch time'), findsOneWidget);
    expect(find.text('Night run'), findsOneWidget);
  });

  testWidgets('works together with the Joined tab', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('Joined · 1'));
    await settle(tester);

    await search(tester, 'snacko');
    expect(find.text('Crunch time'), findsOneWidget);

    await search(tester, 'stride'); // not joined
    expect(find.text('Night run'), findsNothing);
    expect(find.text('No contests match "stride".'), findsOneWidget);
  });
}
