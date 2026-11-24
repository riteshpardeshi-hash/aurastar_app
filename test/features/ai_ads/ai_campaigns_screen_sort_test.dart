import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';

import 'ai_ads_fake_backend.dart';

// Client request: the AI ad campaigns list can be sorted (ending soon / last, newest,
// oldest, name, credits), separately from the All / Joined filter.
void main() {
  tearDown(FakeAiAdsBackend.reset);

  final now = DateTime.now();
  String at(int days) => now.add(Duration(days: days)).toIso8601String();

  Future<void> pumpList(WidgetTester tester) async {
    final backend = FakeAiAdsBackend();
    backend.on('GET /creator/ai-campaigns', {
      'responses': [
        // title, went live, deadline, credits
        {'_id': 'b', 'title': 'Bravo', 'liveAt': at(-5), 'deadline': at(3), 'creditsPerCreator': 50},
        {'_id': 'a', 'title': 'alpha', 'liveAt': at(-1), 'deadline': at(9), 'creditsPerCreator': 10},
        {'_id': 'c', 'title': 'Charlie', 'liveAt': at(-9), 'deadline': at(1), 'creditsPerCreator': 200, 'myStatus': 'ACTIVE'},
      ],
    });
    await pumpAiScreen(tester, const AiCampaignsScreen());
  }

  /// Titles top to bottom as shown.
  List<String> order(WidgetTester tester) {
    const titles = ['alpha', 'Bravo', 'Charlie'];
    final shown = titles.where((t) => find.text(t).evaluate().isNotEmpty).toList();
    shown.sort((x, y) => tester.getTopLeft(find.text(x)).dy.compareTo(tester.getTopLeft(find.text(y)).dy));
    return shown;
  }

  Future<void> sortBy(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('ai-campaigns-sort')));
    await settle(tester);
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  testWidgets('ending soon by default, and every sort orders the list', (tester) async {
    await pumpList(tester);
    expect(order(tester), ['Charlie', 'Bravo', 'alpha']);

    await sortBy(tester, 'Ending last');
    expect(order(tester), ['alpha', 'Bravo', 'Charlie']);

    await sortBy(tester, 'Newest');
    expect(order(tester), ['alpha', 'Bravo', 'Charlie']);

    await sortBy(tester, 'Oldest');
    expect(order(tester), ['Charlie', 'Bravo', 'alpha']);

    await sortBy(tester, 'Name A–Z'); // case-insensitive: "alpha" first
    expect(order(tester), ['alpha', 'Bravo', 'Charlie']);

    await sortBy(tester, 'Name Z–A');
    expect(order(tester), ['Charlie', 'Bravo', 'alpha']);

    await sortBy(tester, 'Most AI credits');
    expect(order(tester), ['Charlie', 'Bravo', 'alpha']);
  });

  testWidgets('the sort keeps working with the Joined filter, and All brings everything back', (tester) async {
    await pumpList(tester);
    await sortBy(tester, 'Name A–Z');

    await tester.tap(find.text('Joined · 1'));
    await settle(tester);
    expect(order(tester), ['Charlie']);

    await tester.tap(find.text('All'));
    await settle(tester);
    expect(order(tester), ['alpha', 'Bravo', 'Charlie']);
  });
}
