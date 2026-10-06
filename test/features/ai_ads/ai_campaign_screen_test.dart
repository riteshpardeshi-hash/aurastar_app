import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_campaign_screen.dart';

import 'ai_ads_fake_backend.dart';

// Joining a campaign: every way in (asking to join, accepting an invite) goes
// through the ownership-terms dialog, and `acceptTerms` is only ever sent after
// the creator agreed — the backend rejects a join without it (ADR 113).
void main() {
  late FakeAiAdsBackend backend;

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('shows the brief and the brand assets', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: null));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    expect(find.textContaining('Key message: Zero sugar, all zing.'), findsOneWidget);
    expect(find.textContaining('cures thirst forever'), findsOneWidget);
    expect(find.text('Fizz jingle'), findsOneWidget);
    expect(find.text('Ask to join'), findsOneWidget);
  });

  testWidgets('ask to join → agree to the terms → request sent with acceptTerms', (tester) async {
    var status = 'NONE';
    backend.routes['GET $base'] = (_) => FakeAiAdsBackend.ok(campaignJson(myStatus: status == 'NONE' ? null : status));
    backend.routes['POST $base/request'] = (_) {
      status = 'REQUESTED';
      return FakeAiAdsBackend.ok({}, status: 201);
    };
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('belongs to the brand'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-terms-accept')));
    await settle(tester);

    expect(backend.calls('POST', '$base/request').single.body, {'acceptTerms': true});
    expect(find.text('Waiting for the brand to approve you.'), findsOneWidget);
  });

  testWidgets('declining the terms sends nothing', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: null));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await settle(tester);

    expect(backend.calls('POST', '$base/request'), isEmpty);
  });

  testWidgets('accepting an invite goes through the terms too', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: 'INVITED'));
    backend.on('POST /creator/ai-campaign-invites/p1/respond', {});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('Accept invite'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-terms-accept')));
    await settle(tester);

    expect(backend.calls('POST', '/creator/ai-campaign-invites/p1/respond').single.body, {'accept': true, 'acceptTerms': true});
  });

  testWidgets('an invite-only campaign cannot be joined uninvited', (tester) async {
    backend.on('GET $base', {...campaignJson(myStatus: null), 'participationMode': 'INVITE_ONLY'});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    expect(find.text('This campaign is invite-only.'), findsOneWidget);
    expect(find.text('Ask to join'), findsNothing);
  });

  testWidgets('a full campaign is not taking creators', (tester) async {
    backend.on('GET $base', {...campaignJson(myStatus: null), 'seatsLeft': 0});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    expect(find.text("This campaign isn't taking creators right now."), findsOneWidget);
  });

  testWidgets('an active creator sees their credits and the workspace button', (tester) async {
    backend.on('GET $base', campaignJson(creditsLeft: 64));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    expect(find.text('64 credits to make your ad'), findsOneWidget);
    expect(find.text('Open my workspace'), findsOneWidget);
  });

  testWidgets('a winner is pointed to their rewards', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: 'WINNER'));
    backend.on('GET /creator/ai-rewards', []);
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('See my rewards'));
    await settle(tester);

    expect(find.text('My rewards'), findsOneWidget);
  });
}
