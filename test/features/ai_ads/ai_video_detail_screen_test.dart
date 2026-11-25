import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_video_detail_screen.dart';

import 'package:aura_app/features/ai_ads/widgets/ai_ui.dart';

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
    expect(find.text('Making your video'), findsOneWidget);
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
    expect(find.widgetWithText(AiPill, '10s'), findsNothing);

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
    expect(find.text('Edited · v2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('ai-image-1-version-1')));
    await tester.tap(find.byKey(const Key('ai-image-1-version-1')));
    await settle(tester);
    expect(find.byKey(const Key('ai-image-1-edited')), findsNothing); // slot 2 now shows its original

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

  testWidgets('versions are counted per image, so images edited in different sets line up', (tester) async {
    // Set v1: originals. Set v2: image 2 edited. Set v3: images 1 and 3 edited (image 2 kept from v2).
    final v1 = generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b.png', 'https://s3/c.png'],
    });
    final v2 = generationJson(id: 'i2', stage: 'IMAGE', scriptId: 's1', version: 2, output: {
      'imageUrls': ['https://s3/a.png', 'https://s3/b2.png', 'https://s3/c.png'],
    });
    final v3 = generationJson(id: 'i3', stage: 'IMAGE', scriptId: 's1', version: 3, output: {
      'imageUrls': ['https://s3/a3.png', 'https://s3/b2.png', 'https://s3/c3.png'],
    });
    backend.on('GET $base/workspace/generations/i3', v3);
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1'), v1, v2, v3]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'i3'));

    for (var i = 0; i < 3; i++) {
      // Every image: its original (v1) and one edit (v2) — whichever set the edit was made in.
      expect(find.byKey(Key('ai-image-$i-version-1')), findsOneWidget);
      expect(find.byKey(Key('ai-image-$i-version-2')), findsOneWidget);
      expect(find.byKey(Key('ai-image-$i-version-3')), findsNothing);
      expect(find.descendant(of: find.byKey(Key('ai-image-$i-edited')), matching: find.text('Edited · v2')), findsOneWidget);
    }
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

  testWidgets('a generating video shows elapsed vs. the estimate, the current step and what is being made', (tester) async {
    final script = generationJson(id: 's1', output: {
      'text': 'flat',
      'script': {
        'scenes': [
          {'durationSeconds': 5, 'visual': 'Rain on a balcony'},
          {'durationSeconds': 5, 'visual': 'A sip and a smile'},
        ],
      },
    });
    final running = generationJson(id: 'v1', stage: 'VIDEO', status: 'RUNNING', scriptId: 's1');
    running['settings'] = {'durationSeconds': 10, 'resolution': '720p', 'onScreenText': false};
    running['eta'] = {
      'startedAt': DateTime.now().subtract(const Duration(seconds: 60)).toUtc().toIso8601String(),
      'estimatedSeconds': 300,
    };
    backend.on('GET $base/workspace/generations/v1', running);
    backend.on('GET $base/workspace', workspaceJson(generations: [script, running]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text('Making your video'), findsOneWidget);
    expect(find.text('10s · 720p'), findsOneWidget);
    expect(find.text('About 4 min left'), findsOneWidget);
    expect(find.textContaining('elapsed'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('ai-video-progress-bar')));
    expect(bar.value, closeTo(0.2, 0.05));
    expect(find.text('Generating your scenes'), findsOneWidget);
    expect(find.text('Rain on a balcony'), findsOneWidget);
    expect(find.text('On-screen text: off'), findsOneWidget);
  });

  // Tester, 24 Nov: "Finishing" showed while the video was still queued, because the step was a timer.
  testWidgets('the progress step is the real status, however long it has taken', (tester) async {
    final running = generationJson(id: 'v1', stage: 'VIDEO', status: 'RUNNING');
    running['step'] = 'WAITING';
    running['eta'] = {
      'startedAt': DateTime.now().subtract(const Duration(minutes: 22)).toUtc().toIso8601String(),
      'estimatedSeconds': 100,
    };
    backend.on('GET $base/workspace/generations/v1', running);
    backend.on('GET $base/workspace', workspaceJson(generations: [running]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget); // only "Sending" is done
    final waiting = tester.widget<Text>(find.text('Waiting for the video AI to start'));
    expect(waiting.style!.fontWeight, FontWeight.w700);
    expect(find.text('Taking longer than usual'), findsOneWidget);
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

    expect(find.text('Making your video'), findsNothing);
    expect(find.text('Submit as my final ad (free)'), findsOneWidget);
  });

  // Tester, 24 Nov: a single failed check stopped the checking for good, so the screen stayed
  // on "Making your video" for 33 minutes after the video was ready.
  testWidgets('a failed check does not stop the checking; the finished video then shows, with a ready message', (tester) async {
    var status = 'RUNNING';
    var failNext = false;
    backend.routes['GET $base/workspace/generations/v1'] = (_) => failNext
        ? FakeAiAdsBackend.error(503, 'Service unavailable')
        : FakeAiAdsBackend.ok(generationJson(id: 'v1', stage: 'VIDEO', status: status));
    backend.on('GET $base/workspace', workspaceJson());
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));
    expect(find.text('Making your video'), findsOneWidget);

    failNext = true;
    await tester.pump(const Duration(seconds: 5)); // this check fails
    await settle(tester);
    expect(find.text('Service unavailable'), findsNothing); // a background check stays quiet
    expect(find.text('Making your video'), findsOneWidget);

    failNext = false;
    status = 'COMPLETED';
    await tester.pump(const Duration(seconds: 10)); // the retry, a little later
    await settle(tester);
    expect(find.text('Making your video'), findsNothing);
    expect(find.text('Your video is ready.'), findsOneWidget);
    expect(find.text('Submit as my final ad (free)'), findsOneWidget);
  });

  testWidgets('coming back to the app checks a running video again at once', (tester) async {
    var status = 'RUNNING';
    backend.routes['GET $base/workspace/generations/v1'] =
        (_) => FakeAiAdsBackend.ok(generationJson(id: 'v1', stage: 'VIDEO', status: status));
    backend.on('GET $base/workspace', workspaceJson());
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));
    final before = backend.calls('GET', '$base/workspace/generations/v1').length;

    status = 'COMPLETED';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.calls('GET', '$base/workspace/generations/v1').length, greaterThan(before));
    expect(find.text('Making your video'), findsNothing);
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

  // Backend ADR 145: the brand's maximum (20s here) holds for a longer version too.
  testWidgets("\"Make it longer\" only offers what fits under the brand's maximum", (tester) async {
    serve(gen: {...doneVideo, 'settings': {'durationSeconds': 15, 'clipSeconds': 15}}, evaluations: [evaluationJson()]);
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    await tester.tap(find.text('Make it longer'));
    await settle(tester);
    expect(find.text('+4s'), findsOneWidget);
    expect(find.text('+5s'), findsOneWidget);
    expect(find.text('+8s'), findsNothing);
    expect(find.text('+10s'), findsNothing);
  });

  // Client decision, 25 Nov (backend ADR 146): the AI score is for the brand. A creator only
  // watches the video and submits it; no score, no "Get AI score", and no scores are fetched.
  testWidgets('a finished video shows no AI score — only Submit, which needs no score', (tester) async {
    serve(gen: doneVideo);
    backend.routes['POST $base/workspace/generations/v1/submit'] =
        (_) => FakeAiAdsBackend.ok({'_id': 'p1', 'status': 'SUBMITTED', 'finalGenerationId': 'v1'});
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));

    expect(find.text('AI score'), findsNothing);
    expect(find.textContaining('Get AI score'), findsNothing);
    expect(find.byKey(const Key('ai-score-card')), findsNothing);
    expect(backend.calls('GET', '$base/workspace/evaluations'), isEmpty);
    expect(backend.calls('POST', '$base/workspace/generations/v1/evaluate/quote'), isEmpty);

    await tester.tap(find.byKey(const Key('ai-submit-final')));
    await settle(tester);
    expect(backend.calls('POST', '$base/workspace/generations/v1/submit'), hasLength(1));
  });


  // Full-flow run, 25 Nov: the Edit / Make it longer / New audio options showed as light
  // "white pills" (Material chips take the app's light theme on device). They're AiPills now.
  testWidgets('the improve options are dark pills, not Material chips', (tester) async {
    serve(gen: doneVideo);
    await pumpAiScreen(tester, const AiVideoDetailScreen(campaignId: campaignId, generationId: 'v1'));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    for (final label in ['Edit', 'Make it longer', 'New audio']) {
      expect(find.widgetWithText(AiPill, label), findsOneWidget);
    }
  });
}
