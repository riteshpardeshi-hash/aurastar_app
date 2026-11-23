import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaigns_screen.dart';

import 'ai_ads_fake_backend.dart';

// Tester report: a campaign the creator was only invited to (not accepted yet) showed under
// "Joined", and the invite-only campaign read "Open to all". Joined now means actually in the
// campaign; an invite or a pending request is not.
void main() {
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('an invite or a pending request is not Joined; invite-only is not Open to all', (tester) async {
    final backend = FakeAiAdsBackend();
    final soon = DateTime.now().add(const Duration(days: 2)).toIso8601String();
    backend.on('GET /creator/ai-campaigns', {
      'responses': [
        {'_id': 'inv', 'title': 'Invited one', 'deadline': soon, 'participationMode': 'INVITE_ONLY', 'myStatus': 'INVITED'},
        {'_id': 'req', 'title': 'Requested one', 'deadline': soon, 'myStatus': 'REQUESTED'},
        {'_id': 'in', 'title': 'Joined one', 'deadline': soon, 'myStatus': 'ACTIVE'},
      ],
    });
    await pumpAiScreen(tester, const AiCampaignsScreen());

    expect(find.text('No creator limit'), findsOneWidget);
    expect(find.text('Open to all'), findsOneWidget); // the requested (open) one

    await tester.tap(find.text('Joined · 1'));
    await settle(tester);

    expect(find.text('Joined one'), findsOneWidget);
    expect(find.text('Invited one'), findsNothing);
    expect(find.text('Requested one'), findsNothing);
  });
}
