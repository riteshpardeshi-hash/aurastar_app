import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_video_detail_screen.dart';

import 'ai_ads_fake_backend.dart';

// One generation: picking keyframes → video, waiting on / cancelling a video,
// getting a finished video judged (paid, quoted), reading the score, picking
// it as the final ad (free) and iterating on it (quoted).
void main() {
  late FakeAiAdsBackend backend;

  void serve({required Map<String, dynamic> gen, List<Map<String, dynamic>> evaluations = const [], String? finalId}) {
    backend.on('GET $base/workspace/generations/${gen['_id']}', gen);
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1'), gen]));
    backend.on('GET $base/workspace/evaluations', evaluations);
    backend.on('GET $base', campaignJson(finalGenerationId: finalId));
  }

  final doneVideo = generationJson(id: 'v1', stage: 'VIDEO', scriptId: 's1');

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.routes['POST $base/workspace/quote'] = (req) =>
        FakeAiAdsBackend.ok(quoteJson(req.body!['operation'] == 'GENERATE' ? 20 : 9));
    backend.on('POST $base/workspace/generations/v1/evaluate/quote', evalQuoteJson());
  });
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('images: pick keyframes → priced "Create video" sends them in order', (tester) async {
    serve(gen: generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1'));
    backend.on('POST $base/workspace/generations', generationJson(id: 'v2', stage: 'VIDEO', status: 'RUNNING'), status: 201);
    backend.on('GET $base/workspace/generations/v2', generationJson(id: 'v2', stage: 'VIDEO', status: 'RUNNING'));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i1'));

    expect(find.text('Pick at least one image'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-image-1')));
    await tester.tap(find.byKey(const Key('ai-image-0')));
    await settle(tester);
    await tester.tap(find.text('Create video · 20 credits'));
    await settle(tester);

    final body = backend.calls('POST', '$base/workspace/generations').single.body!;
    expect(body['expectedCredits'], 20);
    expect(body['scriptId'], 's1');
    expect(body['keyframes'], [{'generationId': 'i1', 'index': 0}, {'generationId': 'i1', 'index': 1}]);
    expect(find.text('Generating your video…'), findsOneWidget);
  });

  testWidgets('a running video can be cancelled (refunded)', (tester) async {
    var status = 'RUNNING';
    backend.routes['GET $base/workspace/generations/v1'] =
        (_) => FakeAiAdsBackend.ok(generationJson(id: 'v1', stage: 'VIDEO', status: status));
    backend.on('GET $base/workspace', workspaceJson());
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    backend.routes['POST $base/workspace/generations/v1/cancel'] = (_) {
      status = 'CANCELLED';
      return FakeAiAdsBackend.ok(generationJson(id: 'v1', stage: 'VIDEO', status: status));
    };
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text('5 credits on hold'), findsOneWidget);
    await tester.tap(find.text('Cancel (refunded)'));
    await settle(tester);

    expect(backend.calls('POST', '$base/workspace/generations/v1/cancel'), hasLength(1));
    expect(find.text("Cancelled — you weren't charged."), findsOneWidget);
  });

  testWidgets('a running video is polled until it finishes', (tester) async {
    var status = 'RUNNING';
    backend.routes['GET $base/workspace/generations/v1'] =
        (_) => FakeAiAdsBackend.ok(generationJson(id: 'v1', stage: 'VIDEO', status: status));
    backend.on('GET $base/workspace', workspaceJson());
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    status = 'COMPLETED';
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    expect(find.text('Generating your video…'), findsNothing);
    expect(find.text('Get AI score · Free · 4 left'), findsOneWidget);
  });

  testWidgets('get AI score: free, then shows the pending state', (tester) async {
    var evaluations = <Map<String, dynamic>>[];
    serve(gen: doneVideo);
    backend.routes['GET $base/workspace/evaluations'] = (_) => FakeAiAdsBackend.ok(evaluations);
    backend.routes['POST $base/workspace/generations/v1/evaluate'] = (_) {
      evaluations = [evaluationJson(status: 'QUEUED')];
      return FakeAiAdsBackend.ok(evaluations.single, status: 202);
    };
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    await tester.tap(find.text('Get AI score · Free · 4 left'));
    await settle(tester);

    // Free — no price is sent.
    expect(backend.calls('POST', '$base/workspace/generations/v1/evaluate').single.body, isEmpty);
    expect(find.text('Scoring your video against the brand brief…'), findsOneWidget);
  });

  testWidgets('the score card shows score, criteria, missing assets by name, timed feedback', (tester) async {
    serve(gen: doneVideo, evaluations: [evaluationJson()]);
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    final card = find.byKey(const Key('ai-score-card'));
    expect(find.descendant(of: card, matching: find.text('72')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('6.5/10')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Missing brand assets: Logo')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('0:04  Logo too small')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('→ Show the logo in the first 2 seconds')), findsOneWidget);
    // Already judged — no second paid evaluation offered.
    expect(find.textContaining('Get AI score'), findsNothing);
  });

  testWidgets('a failed evaluation (refunded) can be retried', (tester) async {
    serve(gen: doneVideo, evaluations: [{...evaluationJson(status: 'FAILED'), 'error': 'The AI could not watch the video'}]);
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text('The AI could not watch the video'), findsOneWidget);
    expect(find.text('Try again · Free · 4 left'), findsOneWidget);
  });

  testWidgets('submit as final ad is free and marks it final', (tester) async {
    String? finalId;
    serve(gen: doneVideo, evaluations: [evaluationJson()]);
    backend.routes['GET $base'] = (_) => FakeAiAdsBackend.ok(campaignJson(finalGenerationId: finalId));
    backend.routes['POST $base/workspace/generations/v1/submit'] = (req) {
      finalId = 'v1';
      return FakeAiAdsBackend.ok({'_id': 'p1', 'status': 'SUBMITTED', 'finalGenerationId': 'v1', 'finalScore': 72});
    };
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    await tester.tap(find.text('Submit as my final ad (free)'));
    await settle(tester);

    expect(backend.calls('POST', '$base/workspace/generations/v1/submit').single.body, isEmpty); // free — no expectedCredits
    expect(find.text('✓ This is your final ad'), findsOneWidget);
    expect(find.text('Submit as my final ad (free)'), findsNothing);
  });

  testWidgets('iterate: "Make it longer" quotes an EXTEND with the chosen seconds', (tester) async {
    serve(gen: doneVideo, evaluations: [evaluationJson()]);
    backend.on('POST $base/workspace/generations', generationJson(id: 'v3', stage: 'VIDEO', status: 'RUNNING'), status: 201);
    backend.on('GET $base/workspace/generations/v3', generationJson(id: 'v3', stage: 'VIDEO', status: 'RUNNING'));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text('Describe the change first'), findsOneWidget);
    await tester.tap(find.text('Make it longer'));
    await settle(tester);
    await tester.tap(find.text('+8s'));
    await tester.enterText(find.byKey(const Key('ai-iterate-instructions')), 'End on the can');
    await settle(tester);
    await tester.tap(find.text('Make the change · 9 credits'));
    await settle(tester);

    final body = backend.calls('POST', '$base/workspace/generations').single.body!;
    expect(body, {
      'stage': 'VIDEO',
      'operation': 'EXTEND',
      'parentId': 'v1',
      'instructions': 'End on the can',
      'settings': {'durationSeconds': 8},
      'expectedCredits': 9,
    });
  });

  testWidgets('no free evaluations left: the reason shows and the button is off', (tester) async {
    serve(gen: doneVideo);
    backend.on('POST $base/workspace/generations/v1/evaluate/quote', evalQuoteJson(left: 0, reason: "You've used all 5 free AI evaluations in this campaign."));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text("You've used all 5 free AI evaluations in this campaign."), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Get AI score · Free · 0 left'));
    expect(button.onPressed, isNull);
  });
}
