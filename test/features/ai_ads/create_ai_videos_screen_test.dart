import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/create_ai_videos_screen.dart';

import 'ai_ads_fake_backend.dart';

// The workspace: every paid button carries its backend quote, the tap sends
// that exact price as `expectedCredits`, and each refusal (price changed, out
// of credits) leads somewhere useful instead of a dead end.
void main() {
  late FakeAiAdsBackend backend;

  /// Script quote 2, images 12, video 25 (or [videoCredits]).
  void quotes({int videoCredits = 25, bool canAffordVideo = true}) {
    backend.routes['POST $base/workspace/quote'] = (req) => FakeAiAdsBackend.ok(switch (req.body!['stage']) {
      'VIDEO' => quoteJson(videoCredits, canAfford: canAffordVideo),
      'IMAGE' => quoteJson(12),
      _ => quoteJson(2),
    });
  }

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET $base', campaignJson());
  });
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('with no script yet, video generation is blocked and AI writing is priced', (tester) async {
    backend.on('GET $base/workspace', workspaceJson());
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    expect(find.text('Write with AI'), findsOneWidget);
    expect(find.text('2 credits'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Get a script first — write it, or let the AI write it.'), findsOneWidget);
    expect(find.text('Getting your ad judged by AI is free — 5 of 5 left.'), findsOneWidget);
    final generate = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Generate video'));
    expect(generate.onPressed, isNull);
  });

  testWidgets('"Use my text" saves the script for free (no quote, no expectedCredits)', (tester) async {
    var generations = <Map<String, dynamic>>[];
    backend.routes['GET $base/workspace'] = (_) => FakeAiAdsBackend.ok(workspaceJson(generations: generations));
    backend.routes['POST $base/workspace/scripts'] = (req) {
      generations = [generationJson(id: 's9', operation: 'MANUAL_EDIT', output: {'text': req.body!['text']})];
      return FakeAiAdsBackend.ok(generations.single, status: 201);
    };
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    await tester.enterText(find.byType(TextField).last, 'A can pops. Zing!');
    await settle(tester);
    await tester.tap(find.text('Use my text'));
    await settle(tester);

    expect(backend.calls('POST', '$base/workspace/scripts').single.body, {'text': 'A can pops. Zing!'});
    expect(find.descendant(of: find.byKey(const Key('ai-selected-script')), matching: find.text('A can pops. Zing!')), findsOneWidget);
    expect(find.text('Generate video · 25 credits'), findsOneWidget);
  });

  testWidgets('generate video sends the quoted price and opens the video', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')]));
    backend.on('POST $base/workspace/generations', generationJson(id: 'v1', stage: 'VIDEO', status: 'RUNNING', scriptId: 's1'), status: 201);
    backend.on('GET $base/workspace/generations/v1', generationJson(id: 'v1', stage: 'VIDEO', status: 'RUNNING', scriptId: 's1'));
    backend.on('GET $base/workspace/evaluations', []);
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    await tester.tap(find.text('Generate video · 25 credits'));
    await settle(tester);

    final body = backend.calls('POST', '$base/workspace/generations').single.body!;
    expect(body['expectedCredits'], 25);
    expect(body['stage'], 'VIDEO');
    expect(body['scriptId'], 's1');
    expect(body['settings'], {'resolution': '720p', 'durationSeconds': 10});
    expect(find.text('Generating your video…'), findsOneWidget);
  });

  testWidgets('choosing length and images-first changes what is quoted', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')]));
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    await tester.tap(find.text('20s'));
    await settle(tester);
    final lastVideoQuote = backend.calls('POST', '$base/workspace/quote').lastWhere((r) => r.body!['stage'] == 'VIDEO');
    expect(lastVideoQuote.body!['settings'], {'resolution': '720p', 'durationSeconds': 20});

    await tester.tap(find.text('Images first'));
    await settle(tester);
    expect(find.text('Generate images · 12 credits'), findsOneWidget);
    expect(backend.calls('POST', '$base/workspace/quote').last.body, {'stage': 'IMAGE', 'operation': 'GENERATE', 'scriptId': 's1', 'imageCount': 4});
  });

  testWidgets('unaffordable: button disabled, shortfall explained, can ask for credits', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')], creditsLeft: 26));
    quotes(canAffordVideo: false);
    backend.on('POST $base/credit-requests', {'_id': 'r1', 'requestedCredits': 40, 'status': 'PENDING'}, status: 201);
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    expect(find.text('This costs 25 credits and you have 100.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Generate video · 25 credits')).onPressed, isNull);

    await tester.tap(find.text('Ask the brand for more credits'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-credit-amount')), '40');
    await tester.tap(find.text('Send request'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(backend.calls('POST', '$base/credit-requests').single.body, {'credits': 40});
    expect(find.text('Request sent — the brand will review it.'), findsOneWidget);
  });

  testWidgets('a changed price is not charged: the creator is told and the button re-quotes', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')]));
    quotes();
    backend.fail('POST $base/workspace/generations', 409, 'The price changed — this now costs 30 credits. Check and try again.');
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    quotes(videoCredits: 30);
    await tester.tap(find.text('Generate video · 25 credits'));
    await settle(tester);

    expect(find.textContaining('The price changed'), findsOneWidget);
    expect(find.text('Generate video · 30 credits'), findsOneWidget);
  });

  testWidgets('out of credits offers "Ask for more"', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')]));
    quotes();
    backend.fail('POST $base/workspace/generations', 402, 'You are out of credits');
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    await tester.tap(find.text('Generate video · 25 credits'));
    await settle(tester);

    expect(find.text('You are out of credits'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Ask for more'), findsOneWidget);
  });

  testWidgets('editing a script is free and selects the new version', (tester) async {
    var generations = [generationJson(id: 's1')];
    backend.routes['GET $base/workspace'] = (_) => FakeAiAdsBackend.ok(workspaceJson(generations: generations));
    backend.routes['POST $base/workspace/generations/s1/script'] = (req) {
      generations = [...generations, generationJson(id: 's2', version: 2, operation: 'MANUAL_EDIT', output: {'text': req.body!['text']})];
      return FakeAiAdsBackend.ok(generations.last);
    };
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    await tester.tap(find.text('Edit (free)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-edit-script')), 'Shorter version');
    await tester.tap(find.text('Save (free)'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('v2'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ai-selected-script')), matching: find.text('Shorter version')), findsOneWidget);
  });

  testWidgets('offers a 5s first take below the brand minimum, with a hint to extend it', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(shortClipSeconds: 5));
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    for (final s in ['5s', '10s', '15s', '20s']) {
      expect(find.widgetWithText(ChoiceChip, s), findsOneWidget);
    }
    expect(find.byKey(const Key('ai-short-take-hint')), findsNothing);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '5s'));
    await tester.tap(find.widgetWithText(ChoiceChip, '5s'));
    await settle(tester);

    expect(find.byKey(const Key('ai-short-take-hint')), findsOneWidget);
  });

  testWidgets('without shortClipSeconds (older backend) only the brand lengths are offered', (tester) async {
    backend.on('GET $base/workspace', workspaceJson());
    quotes();
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    expect(find.widgetWithText(ChoiceChip, '5s'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '10s'), findsOneWidget);
  });
}
