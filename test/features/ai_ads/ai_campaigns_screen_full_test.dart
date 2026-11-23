import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';

import 'ai_ads_fake_backend.dart';

// Found on a device: the campaign list offered "Join ›" on a full campaign the creator
// isn't part of, which can't be joined. It says "Full" now; one they're in says "You're in".
void main() {
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('a full campaign offers no Join; a joined one says You\'re in', (tester) async {
    final backend = FakeAiAdsBackend();
    final soon = DateTime.now().add(const Duration(days: 2)).toIso8601String();
    backend.on('GET /creator/ai-campaigns', {
      'responses': [
        {'_id': 'full', 'title': 'Full one', 'deadline': soon, 'seatsLeft': 0, 'creatorCap': 1, 'myStatus': null},
        {'_id': 'mine', 'title': 'Mine', 'deadline': soon, 'seatsLeft': 0, 'creatorCap': 1, 'myStatus': 'ACTIVE'},
        {'_id': 'open', 'title': 'Open one', 'deadline': soon, 'seatsLeft': 3, 'creatorCap': 5, 'myStatus': null},
      ],
    });
    await pumpAiScreen(tester, const AiCampaignsScreen());

    expect(find.text('Join ›'), findsOneWidget); // only the open one
    expect(find.text('Full'), findsNWidgets(2)); // the full one's seats line and its action
    expect(find.text("You're in"), findsOneWidget);
    expect(find.text('Create ›'), findsOneWidget);
  });
}
