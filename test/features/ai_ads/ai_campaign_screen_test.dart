import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/app_config_service.dart';
import 'package:aura_app/features/ai_ads/screens/ai_campaign_screen.dart';

import 'ai_ads_fake_backend.dart';

// Joining a campaign: asking to join goes through the application form (pitch, links, demo
// video, terms — backend ADR 131); accepting an invite goes through the ownership-terms
// dialog. `acceptTerms` is only ever sent after the creator agreed (ADR 113).
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

  testWidgets('ask to join opens the application form, prefilled with my links, and sends pitch + links + terms', (tester) async {
    var status = 'NONE';
    backend.routes['GET $base'] = (_) => FakeAiAdsBackend.ok({
      ...campaignJson(myStatus: status == 'NONE' ? null : status),
      'suggestedLinks': {'instagram': 'https://instagram.com/me.films'},
    });
    backend.routes['POST $base/request'] = (_) {
      status = 'REQUESTED';
      return FakeAiAdsBackend.ok({}, status: 201);
    };
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    expect(find.text('https://instagram.com/me.films'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ai-join-pitch')), 'I make warm family reels.');
    await tester.enterText(find.byKey(const Key('ai-join-link-youtube')), '@mefilms');
    await tester.ensureVisible(find.byKey(const Key('ai-join-terms')));
    await tester.tap(find.byKey(const Key('ai-join-terms')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ai-join-send')));
    await tester.tap(find.byKey(const Key('ai-join-send')));
    await settle(tester);

    expect(backend.calls('POST', '$base/request').single.body, {
      'acceptTerms': true,
      'message': 'I make warm family reels.',
      'links': {'instagram': 'https://instagram.com/me.films', 'youtube': '@mefilms'},
    });
    expect(find.text('Waiting for the brand to approve you.'), findsOneWidget);
  });

  testWidgets('without a link, or without agreeing to the terms, nothing is sent', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: null));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ai-join-send')));
    await tester.tap(find.byKey(const Key('ai-join-send')));
    await tester.pump();
    expect(find.textContaining('Add at least one link'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ai-join-link-instagram')), '@me');
    await tester.ensureVisible(find.byKey(const Key('ai-join-send')));
    await tester.tap(find.byKey(const Key('ai-join-send')));
    await tester.pump();
    expect(find.textContaining('agree to the campaign terms'), findsOneWidget);
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
    AppConfigService.instance.couponsEnabled.value = true;
    addTearDown(() => AppConfigService.instance.couponsEnabled.value = false);
    backend.on('GET $base', campaignJson(myStatus: 'WINNER'));
    backend.on('GET /creator/ai-rewards', []);
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    await tester.tap(find.text('See my rewards'));
    await settle(tester);

    expect(find.text('My rewards'), findsOneWidget);
  });

  testWidgets('while coupons are switched off a winner is not pointed to any rewards (Apple 3.1.1)', (tester) async {
    AppConfigService.instance.couponsEnabled.value = false;
    backend.on('GET $base', campaignJson(myStatus: 'WINNER'));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

    expect(find.text('Your ad won! 🏆'), findsOneWidget);
    expect(find.text('See my rewards'), findsNothing);
  });

  testWidgets('a closed campaign no longer offers the workspace', (tester) async {
    backend.on('GET $base', {...campaignJson(myStatus: 'ACTIVE'), 'status': 'CLOSED'});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
    expect(find.byKey(const Key('ai-campaign-ended')), findsOneWidget);
    expect(find.text('This campaign has ended — the brand is picking the winners.'), findsOneWidget);
    expect(find.text('Open my workspace'), findsNothing);
  });

  testWidgets('a cancelled campaign says so and offers nothing to make', (tester) async {
    backend.on('GET $base', {...campaignJson(myStatus: 'ACTIVE'), 'status': 'CANCELLED'});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
    expect(find.text('This campaign was cancelled.'), findsOneWidget);
    expect(find.text('Open my workspace'), findsNothing);
  });

  testWidgets('a paused campaign says so but still lets the creator look', (tester) async {
    backend.on('GET $base', {...campaignJson(myStatus: 'ACTIVE'), 'status': 'PAUSED'});
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
    expect(find.byKey(const Key('ai-campaign-paused')), findsOneWidget);
    expect(find.text('Open my workspace'), findsOneWidget);
  });

  // Backend ADR 147: submitting is once only — the campaign screen shows it's done.
  testWidgets('a submitted creator sees it is done: no workspace, a way to watch the ad', (tester) async {
    backend.on('GET $base', campaignJson(myStatus: 'SUBMITTED', finalGenerationId: 'v1'));
    await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
    expect(find.byKey(const Key('ai-submitted-note')), findsOneWidget);
    expect(find.text('Open my workspace'), findsNothing);
    expect(find.text('Watch my ad'), findsOneWidget);
    expect(find.textContaining('credits to make your ad'), findsNothing);
  });

  // 25 Nov 2026: a joined creator can leave (backend ADR 147). Their credits go back to the
  // brand; an ad they'd submitted still counts, but they can't win while they're out.
  group('leaving a campaign', () {
    testWidgets('an active creator leaves after confirming; Stay does nothing', (tester) async {
      var status = 'ACTIVE';
      backend.routes['GET $base'] = (_) => FakeAiAdsBackend.ok(campaignJson(myStatus: status));
      backend.routes['POST $base/withdraw'] = (_) {
        status = 'WITHDRAWN';
        return FakeAiAdsBackend.ok({'_id': 'p1', 'status': 'WITHDRAWN'});
      };
      await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));

      await tester.ensureVisible(find.byKey(const Key('ai-leave-campaign')));
      await tester.tap(find.byKey(const Key('ai-leave-campaign')));
      await settle(tester);
      expect(find.textContaining('Your unused credits go back to the brand'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await settle(tester);
      expect(backend.calls('POST', '$base/withdraw'), isEmpty);

      await tester.tap(find.byKey(const Key('ai-leave-campaign')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('ai-leave-confirm')));
      await settle(tester);
      expect(backend.calls('POST', '$base/withdraw'), hasLength(1));
      expect(find.text('Ask to join'), findsOneWidget); // they can ask to join again
      expect(find.byKey(const Key('ai-leave-campaign')), findsNothing);
    });

    testWidgets('a submitted creator is told their ad stays but they cannot win while out', (tester) async {
      backend.on('GET $base', campaignJson(myStatus: 'SUBMITTED', finalGenerationId: 'v1'));
      await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
      await tester.ensureVisible(find.byKey(const Key('ai-leave-campaign')));
      await tester.tap(find.byKey(const Key('ai-leave-campaign')));
      await settle(tester);
      expect(find.textContaining("can't be picked as a winner while you're out"), findsOneWidget);
    });

    testWidgets('after leaving with a submitted ad: a note, and Ask to rejoin', (tester) async {
      backend.on('GET $base', campaignJson(myStatus: 'WITHDRAWN', finalGenerationId: 'v1'));
      await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
      expect(find.byKey(const Key('ai-left-after-submitting')), findsOneWidget);
      expect(find.text('Ask to rejoin'), findsOneWidget);
    });

    testWidgets('no Leave for a winner, or once the campaign has ended', (tester) async {
      backend.on('GET $base', campaignJson(myStatus: 'WINNER', finalGenerationId: 'v1'));
      await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
      expect(find.byKey(const Key('ai-leave-campaign')), findsNothing);

      backend.on('GET $base', {...campaignJson(myStatus: 'SUBMITTED', finalGenerationId: 'v1'), 'status': 'CLOSED'});
      await pumpAiScreen(tester, const AiCampaignScreen(campaignId: campaignId));
      expect(find.byKey(const Key('ai-leave-campaign')), findsNothing);
    });
  });
}
