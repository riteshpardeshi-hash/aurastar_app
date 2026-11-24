import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/create_ai_videos_screen.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_ui.dart';

import 'ai_ads_fake_backend.dart';

// Client decision (24 Nov): the brand picks the video quality for the campaign (backend
// ADR 144). The creator no longer chooses it: the app shows the brand's quality and sends
// it with every quote and video on its own.
void main() {
  late FakeAiAdsBackend backend;

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET $base', campaignJson());
    final workspace = workspaceJson(generations: [generationJson(id: 's1')]);
    final campaign = workspace['campaign'] as Map;
    campaign['format'] = <String, Object?>{...(campaign['format'] as Map).cast<String, Object?>(), 'resolution': '480p'};
    backend.on('GET $base/workspace', workspace);
    backend.routes['POST $base/workspace/quote'] = (req) => FakeAiAdsBackend.ok(quoteJson(req.body!['stage'] == 'VIDEO' ? 18 : 2));
  });
  tearDown(FakeAiAdsBackend.reset);

  testWidgets("no quality picker: the brand's quality is shown and sent with the video", (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    for (final r in ['480p', '720p', '1080p']) {
      expect(find.widgetWithText(AiPill, r), findsNothing);
    }
    expect(find.descendant(of: find.byKey(const Key('ai-quality-set-by-brand')), matching: find.text('480p, set by the brand')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ai-generate-bar')), matching: find.text('10s · 480p · text to video')), findsOneWidget);

    final videoQuote = backend.calls('POST', '$base/workspace/quote').lastWhere((r) => r.body!['stage'] == 'VIDEO');
    expect((videoQuote.body!['settings'] as Map)['resolution'], '480p');
  });
}
