import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaign_screen.dart';
import 'package:aura_app/features/notifications/notifications_screen.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// A creator's AI ad notifications (invite, request answered, credits, win) open their
// campaign, and every notification shows its headline above the detail. Before, an invite
// read just "Summer Fizz" and tapping it only marked it read.
Map<String, dynamic> _n(String id, String type, String title, String body, [Map<String, dynamic>? payload]) => {
  '_id': id,
  'type': type,
  'title': title,
  'body': body,
  'payload': payload ?? {},
  'isRead': false,
  'createdAt': DateTime.now().toIso8601String(),
};

void main() {
  late FakeAiAdsBackend backend;

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET /notifications', {
      'responses': [
        _n('n1', 'AI_AD_INVITE', "You're invited to an AI ad campaign", 'Summer Fizz', {
          'campaignId': campaignId,
          'participationId': 'p1',
        }),
        _n('n2', 'dropped_rank', 'Someone passed you', 'You dropped to #3 on the leaderboard.'),
        _n('n3', 'AI_AD_JOIN_REQUEST', 'A creator wants to join', 'Summer Fizz', {'campaignId': campaignId}),
      ],
      'totalCount': 3,
      'page': 1,
      'totalPages': 1,
    });
    backend.on('PATCH /notifications/n1/read', {});
    backend.on('PATCH /notifications/n2/read', {});
    backend.on('PATCH /notifications/n3/read', {});
    backend.on('GET $base', campaignJson(myStatus: 'INVITED'));
  });

  tearDown(FakeAiAdsBackend.reset);

  testWidgets('an invite shows its headline and opens the campaign', (tester) async {
    await pumpAiScreen(tester, const NotificationsScreen());

    expect(find.text("You're invited to an AI ad campaign"), findsOneWidget);
    expect(find.text('Someone passed you'), findsOneWidget);

    await tester.tap(find.text("You're invited to an AI ad campaign"));
    await settle(tester);

    expect(find.byType(AiCampaignScreen), findsOneWidget);
    expect(backend.calls('PATCH', '/notifications/n1/read'), hasLength(1));
  });

  testWidgets('other notifications are only marked read', (tester) async {
    await pumpAiScreen(tester, const NotificationsScreen());

    await tester.tap(find.text('Someone passed you'));
    await settle(tester);
    // The brand-side one is for the brand portal, not the app.
    await tester.tap(find.text('A creator wants to join'));
    await settle(tester);

    expect(find.byType(AiCampaignScreen), findsNothing);
    expect(backend.calls('PATCH', '/notifications/n2/read'), hasLength(1));
    expect(backend.calls('PATCH', '/notifications/n3/read'), hasLength(1));
  });
}
