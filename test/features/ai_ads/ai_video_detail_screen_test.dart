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

  testWidgets('a storyboard labels each frame with its scene and time, and starts with all of them picked', (tester) async {
    final script = generationJson(id: 's1', durationSeconds: 10, output: {
      'text': 'flat',
      'script': {
        'scenes': [
          {'durationSeconds': 3, 'visual': 'Rain'},
          {'durationSeconds': 4, 'visual': 'Can'},
          {'durationSeconds': 3, 'visual': 'Sip'},
        ],
      },
    });
    final board = generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b.png', 'https://s3/c.png'],
      'sceneIndexes': [0, 1, 2],
    });
    backend.on('GET $base/workspace/generations/i1', board);
    backend.on('GET $base/workspace', workspaceJson(generations: [script, board]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    backend.on('POST $base/workspace/generations', generationJson(id: 'v2', stage: 'VIDEO', status: 'RUNNING'), status: 201);
    backend.on('GET $base/workspace/generations/v2', generationJson(id: 'v2', stage: 'VIDEO', status: 'RUNNING'));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i1'));

    expect(find.text('Your storyboard'), findsOneWidget);
    expect(find.text('Scene 1 · 0–3s'), findsOneWidget);
    expect(find.text('Scene 2 · 3–7s'), findsOneWidget);
    expect(find.text('Scene 3 · 7–10s'), findsOneWidget);
    // The script set the length — no choice here.
    expect(find.descendant(of: find.byKey(const Key('ai-fixed-length')), matching: find.text('10s')), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '10s'), findsNothing);

    await tester.ensureVisible(find.text('Create video · 20 credits'));
    await tester.tap(find.text('Create video · 20 credits'));
    await settle(tester);

    final body = backend.calls('POST', '$base/workspace/generations').single.body!;
    expect(body['keyframes'], [
      {'generationId': 'i1', 'index': 0},
      {'generationId': 'i1', 'index': 1},
      {'generationId': 'i1', 'index': 2},
    ]);
    expect(body['settings'], containsPair('durationSeconds', 10));
  });

  testWidgets('change images: pick several by number, say what to change in each → one priced REFINE', (tester) async {
    final set = generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b.png', 'https://s3/c.png'],
    });
    serve(gen: set);
    backend.on(
      'POST $base/workspace/generations',
      generationJson(id: 'i2', stage: 'IMAGE', scriptId: 's1', version: 2, operation: 'REFINE'),
      status: 201,
    );
    backend.on('GET $base/workspace/generations/i2', generationJson(id: 'i2', stage: 'IMAGE', scriptId: 's1', version: 2));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i1'));

    for (var i = 0; i < 3; i++) {
      expect(find.descendant(of: find.byKey(Key('ai-image-number-$i')), matching: find.text('${i + 1}')), findsOneWidget);
    }
    for (final i in [1, 2]) {
      await tester.ensureVisible(find.byKey(Key('ai-edit-image-$i')));
      await tester.tap(find.byKey(Key('ai-edit-image-$i')));
      await settle(tester);
    }
    await tester.enterText(find.byKey(const Key('ai-image-change-1')), 'Make the can bigger');
    await tester.enterText(find.byKey(const Key('ai-image-change-2')), 'Golden hour light');
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    expect(backend.calls('POST', '$base/workspace/quote').last.body, {
      'stage': 'IMAGE',
      'operation': 'REFINE',
      'parentId': 'i1',
      'edits': [
        {'imageIndex': 1, 'instructions': 'Make the can bigger'},
        {'imageIndex': 2, 'instructions': 'Golden hour light'},
      ],
    });
    await tester.ensureVisible(find.text('Update 2 images'));
    await tester.tap(find.text('Update 2 images'));
    await settle(tester);

    final body = backend.calls('POST', '$base/workspace/generations').single.body!;
    expect(body, containsPair('operation', 'REFINE'));
    expect(body, containsPair('expectedCredits', 9));
    expect((body['edits'] as List).length, 2);
  });

  testWidgets('each image can switch between its versions; the video and edits use the ones picked', (tester) async {
    final v1 = generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {
      'imageUrls': ['https://s3/a.png?sig=1', 'https://s3/b.png?sig=1'],
    });
    final v2 = generationJson(id: 'i2', stage: 'IMAGE', scriptId: 's1', version: 2, output: {
      'imageUrls': ['https://s3/a.png?sig=2', 'https://s3/b2.png?sig=2'],
    });
    v2['settings'] = {'editedImageIndexes': [1]};
    backend.on('GET $base/workspace/generations/i2', v2);
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1'), v1, v2]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    backend.on('POST $base/workspace/generations', generationJson(id: 'v9', stage: 'VIDEO', status: 'RUNNING'), status: 201);
    backend.on('GET $base/workspace/generations/v9', generationJson(id: 'v9', stage: 'VIDEO', status: 'RUNNING'));
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i2'));

    // Slot 1 never changed — one version, no switcher. Slot 2 has v1 and v2.
    expect(find.byKey(const Key('ai-image-0-version-1')), findsNothing);
    expect(find.byKey(const Key('ai-image-1-version-1')), findsOneWidget);
    expect(find.byKey(const Key('ai-image-1-version-2')), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('ai-image-1-version-1')));
    await tester.tap(find.byKey(const Key('ai-image-1-version-1')));
    await settle(tester);
    expect(find.text('Updated'), findsNothing); // slot 2 now shows v1's image

    await tester.tap(find.byKey(const Key('ai-image-0')));
    await tester.tap(find.byKey(const Key('ai-image-1')));
    await settle(tester);
    await tester.ensureVisible(find.text('Create video · 20 credits'));
    await tester.tap(find.text('Create video · 20 credits'));
    await settle(tester);

    expect(backend.calls('POST', '$base/workspace/generations').single.body!['keyframes'], [
      {'generationId': 'i2', 'index': 0},
      {'generationId': 'i1', 'index': 1},
    ]);
  });

  testWidgets('an edit from a switched board sends the version in every slot', (tester) async {
    final v1 = generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b.png'],
    });
    final v2 = generationJson(id: 'i2', stage: 'IMAGE', scriptId: 's1', version: 2, output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b2.png'],
    });
    backend.on('GET $base/workspace/generations/i2', v2);
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1'), v1, v2]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i2'));

    await tester.ensureVisible(find.byKey(const Key('ai-image-1-version-1')));
    await tester.tap(find.byKey(const Key('ai-image-1-version-1')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('ai-edit-image-0')));
    await tester.tap(find.byKey(const Key('ai-edit-image-0')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('ai-image-change-0')), 'More rain');
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);

    final quoted = backend.calls('POST', '$base/workspace/quote').last.body!;
    expect(quoted['slotSources'], [
      {'generationId': 'i2', 'index': 0},
      {'generationId': 'i1', 'index': 1},
    ]);
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
