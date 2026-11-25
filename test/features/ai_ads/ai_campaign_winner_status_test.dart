import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/ai_ads_service.dart';
import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_campaign_spotlight.dart';

import 'ai_ads_fake_backend.dart';

// Full-flow run, 25 Nov: after the brand picked the creator's ad, the home banner showed the
// campaign as "AI Ad Campaign · Join →", inviting the winner to join the campaign they won.
AiCampaignSummary _won() => AiCampaignSummary(
      id: 'c1',
      title: 'Summer splash',
      deadline: DateTime.now().add(const Duration(days: 2)),
      myStatus: 'WINNER',
      brand: const AiBrandRef(id: 'b1', name: 'Fizzy Co'),
      format: const AiAdFormat(aspectRatio: '9:16', minDurationSeconds: 10, maxDurationSeconds: 15),
    );

void main() {
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('the home banner shows a winner "You won", never Join', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AiCampaignSpotlight(loader: () async => [_won()], fallback: const Text('F')))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('You won'), findsOneWidget);
    expect(find.text('See your win →'), findsOneWidget);
    expect(find.text('Join →'), findsNothing);
    expect(find.text('AI Ad Campaign'), findsNothing);
  });

  testWidgets('the campaign list shows a winner "You won" too', (tester) async {
    final backend = FakeAiAdsBackend();
    backend.on('GET /creator/ai-campaigns', {
      'responses': [
        {'_id': 'c1', 'title': 'Summer splash', 'deadline': DateTime.now().add(const Duration(days: 2)).toIso8601String(), 'myStatus': 'WINNER'},
      ],
    });
    await pumpAiScreen(tester, const AiCampaignsScreen());

    expect(find.text('You won'), findsOneWidget);
    expect(find.text('Join ›'), findsNothing);
  });
}
