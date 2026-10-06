import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/my_ai_videos_screen.dart';

import 'ai_ads_fake_backend.dart';

// The creator's image sets + videos in one campaign: newest first, scripts left
// out, each with its latest AI score, and the final ad marked.
void main() {
  late FakeAiAdsBackend backend;

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('lists images and videos newest first, with scores and the final ad', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [
      generationJson(id: 's1'),
      generationJson(id: 'i1', stage: 'IMAGE'),
      generationJson(id: 'v1', stage: 'VIDEO'),
      generationJson(id: 'v2', stage: 'VIDEO', version: 2, instructions: 'Show the can earlier'),
    ]));
    backend.on('GET $base/workspace/evaluations', [
      evaluationJson(id: 'e2', videoId: 'v1', score: 81), // newest first: this one wins
      evaluationJson(id: 'e1', videoId: 'v1', score: 60),
    ]);
    backend.on('GET $base', campaignJson(finalGenerationId: 'v1'));
    await pumpAiScreen(tester, const MyAiVideosScreen(campaignId: campaignId));

    expect(find.text('Script v1'), findsNothing);
    final labels = tester.widgetList<Text>(find.textContaining(RegExp(r'^(Images|Video) v\d$'))).map((t) => t.data).toList();
    expect(labels, ['Video v2', 'Video v1', 'Images v1']);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('60'), findsNothing);
    expect(find.text('Final ad'), findsOneWidget);
    expect(find.text('Show the can earlier'), findsOneWidget);
  });

  testWidgets('empty workspace says so', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [generationJson(id: 's1')]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const MyAiVideosScreen(campaignId: campaignId));

    expect(find.text('No AI videos yet'), findsOneWidget);
  });

  testWidgets('a running video is polled until it is done', (tester) async {
    var status = 'RUNNING';
    backend.routes['GET $base/workspace'] = (_) =>
        FakeAiAdsBackend.ok(workspaceJson(generations: [generationJson(id: 'v1', stage: 'VIDEO', status: status)]));
    backend.on('GET $base/workspace/evaluations', []);
    backend.on('GET $base', campaignJson());
    await pumpAiScreen(tester, const MyAiVideosScreen(campaignId: campaignId));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    status = 'COMPLETED';
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    expect(backend.calls('GET', '$base/workspace'), hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
