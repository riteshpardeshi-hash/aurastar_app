import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/create_ai_videos_screen.dart';
import 'package:aura_app/shared/widgets/video_thumbnail_widget.dart';

import 'ai_ads_fake_backend.dart';

// Tester report: a finished AI video showed as an empty box with a play icon until opened.
// In the workspace's "Your images & videos" row it now shows a frame of itself.
void main() {
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('a finished video shows its thumbnail; a running one shows a spinner', (tester) async {
    final backend = FakeAiAdsBackend();
    backend.on('GET $base', campaignJson());
    backend.on('GET $base/workspace', workspaceJson(generations: [
      generationJson(id: 's1'),
      generationJson(id: 'v1', stage: 'VIDEO', scriptId: 's1'),
      generationJson(id: 'v2', stage: 'VIDEO', status: 'RUNNING', scriptId: 's1'),
    ]));
    backend.routes['POST $base/workspace/quote'] = (_) => FakeAiAdsBackend.ok(quoteJson(2));
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    expect(find.byKey(const Key('ai-work-thumb-v1')), findsOneWidget);
    expect(find.byKey(const Key('ai-work-thumb-v2')), findsNothing);
    expect(
      find.descendant(of: find.byKey(const Key('ai-work-v2')), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    expect(find.byType(VideoThumbnailWidget), findsOneWidget);

    // Let the running video's poll and the thumbnail's timeout settle before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 40));
  });
}
