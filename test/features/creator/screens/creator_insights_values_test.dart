import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/creator_insights_screen.dart';

// Regression: the Insights screen read `overview` / `rewards` / `gates` keys
// (a stale OpenAPI schema) while GET /creator/insights returns
// `{summary, growth}`, and the Performance tab read keys that
// /creator/insights/performance never sends — so nearly every card showed 0.
// Both tabs must render the numbers the backend actually returns.
WidgetTester? tester0;

void main() {
  final requestedRanges = <String?>[];

  Map<String, dynamic> insightsFor(String? range) => {
        'summary': {
          'totalViews': range == null ? 12000 : 340,
          'participants': range == null ? 450 : 27,
          'totalChallenges': 5,
          'activeChallenges': 3,
          'completedChallenges': 2,
          'totalLikes': 300,
          'shares': 80,
          'followers': 1200,
          if (range != null) 'newFollowers': 41,
          'auraEarned': 9500,
          'rewardEarned': range == null ? 2000 : 150,
        },
        'growth': {
          'totalGateRewardEarned': 2000,
          'totalCompletedGates': 4,
          'challengesWithGateProgress': 6,
          'completedAllGates': 1,
          'highestPerformingChallenge': null,
        },
      };

  setUp(() {
    requestedRanges.clear();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/creator/insights')) {
        final range = request.url.queryParameters['dateRange'];
        requestedRanges.add(range);
        return http.Response(
            jsonEncode({'status': 'success', 'data': insightsFor(range)}), 200);
      }
      return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  Future<void> settle(WidgetTester tester) async {
    tester0 = tester;
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  /// A stat card is a Column of exactly `[Text(value), Text(label)]`.
  void expectCard(String label, String value) {
    final match = find.byWidgetPredicate((w) =>
        w is Column &&
        w.children.length == 2 &&
        w.children[0] is Text &&
        w.children[1] is Text &&
        (w.children[1] as Text).data == label);
    expect(match, findsOneWidget, reason: 'one "$label" card expected');
    final shown = ((tester0!.widget(match) as Column).children[0] as Text).data;
    expect(shown, value, reason: '"$label" card should show $value');
  }

  testWidgets('Overview renders summary and growth figures', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreatorInsightsScreen()));
    await settle(tester);

    expect(requestedRanges, contains(null),
        reason: 'Overview is all-time — no dateRange');
    expectCard('Total Challenges', '5');
    expectCard('Live Challenges', '3');
    expectCard('Completed', '2');
    expectCard('Followers', '1200');
    expectCard('Views', '12000');
    expectCard('Participants', '450');
    expectCard('Total Reward Earned', '2000');
    expectCard('Completed Gates', '4');
    expectCard('Challenges w/ Gates', '6');
    expectCard('Fully Completed', '1');
  });

  // Regression: cards were sized by a width-based aspect ratio, so on a phone
  // they were very tall with the value/label pinned to the top while the icon
  // sat in the middle. The text block must be vertically centred on the icon
  // and the card compact.
  testWidgets('stat cards are compact with the text centred on the icon',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CreatorInsightsScreen()));
    await settle(tester);

    final label = find.text('Total Challenges');
    final card = find.ancestor(of: label, matching: find.byType(Container)).first;
    final icon = find.descendant(of: card, matching: find.byType(CircleAvatar));
    final text = find.ancestor(of: label, matching: find.byType(Column)).first;

    final cardBox = tester.getRect(card);
    expect(cardBox.height, lessThan(90),
        reason: 'card should hug its content, not stretch with the width');
    expect((tester.getRect(text).center.dy - tester.getRect(icon).center.dy).abs(),
        lessThan(2), reason: 'value + label must be vertically centred on the icon');
  });

  testWidgets('Performance renders the selected date range\'s figures',
      (tester) async {
    // Tall enough that the lazily-built ListView lays out every card.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CreatorInsightsScreen()));
    await settle(tester);
    await tester.tap(find.text('Performance'));
    await settle(tester);

    expect(requestedRanges, contains('30d'));
    expectCard('Views', '340');
    expectCard('Participants', '27');
    expectCard('New Followers', '41');
    expectCard('Reward Earned', '150');
    expectCard('Live Challenges', '3');
  });
}
