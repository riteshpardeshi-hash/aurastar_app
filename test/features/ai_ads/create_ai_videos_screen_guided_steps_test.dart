import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_brand_assets_row.dart';
import 'package:aura_app/features/ai_ads/screens/create_ai_videos_screen.dart';

import 'ai_ads_fake_backend.dart';

// Client feedback (24 Nov): the workspace opened on "Your images & videos", so creators
// landed on old work instead of making the next ad. It now reads as guided steps — the
// brief folded, 1 Script, 2 Style, 3 Your images & videos — with Generate pinned to the
// bottom, a count on the My AI videos icon, and the script actions in one row.
void main() {
  late FakeAiAdsBackend backend;

  void quotes() {
    backend.routes['POST $base/workspace/quote'] = (req) => FakeAiAdsBackend.ok(switch (req.body!['stage']) {
      'VIDEO' => quoteJson(25),
      'IMAGE' => quoteJson(12),
      _ => quoteJson(2),
    });
  }

  setUp(() {
    backend = FakeAiAdsBackend();
    backend.on('GET $base', campaignJson());
    backend.on('GET $base/workspace', workspaceJson(generations: [
      generationJson(id: 's1'),
      generationJson(id: 'v1', stage: 'VIDEO', scriptId: 's1', status: 'RUNNING'),
    ]));
    quotes();
  });
  tearDown(FakeAiAdsBackend.reset);

  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  testWidgets('your images & videos come after the script and style steps, not first', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    final script = find.text('Script'), style = find.text('Style'), work = find.text('Your images & videos');
    expect(work, findsOneWidget);
    expect(top(tester, script), lessThan(top(tester, style)));
    expect(top(tester, style), lessThan(top(tester, work)));
    expect(top(tester, find.byKey(const Key('ai-brief-card'))), lessThan(top(tester, script)));
  });

  testWidgets('Generate is pinned at the bottom of a phone screen, with what it makes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CreateAiVideosScreen(campaignId: campaignId)));
    await settle(tester);

    final generate = find.text('Generate video · 25 credits');
    expect(generate, findsOneWidget);
    expect(tester.getBottomLeft(generate).dy, lessThanOrEqualTo(844));
    expect(find.descendant(of: find.byKey(const Key('ai-generate-bar')), matching: find.text('10s · 720p · text to video')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ai-generate-bar')), matching: find.text('100 credits left')), findsOneWidget);
  });

  testWidgets('the brief is folded to one line and opens to show the assets', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));
    expect(find.byType(AiBrandAssetsRow), findsNothing);

    await tester.tap(find.text('Brand brief & assets'));
    await settle(tester);
    expect(find.byType(AiBrandAssetsRow), findsOneWidget);
  });

  testWidgets('script actions sit in one row; Refine and New script open their panels', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));
    expect(find.text('Refine with AI'), findsNothing);
    expect(find.text('Write with AI'), findsNothing);
    final refine = find.byKey(const Key('ai-script-refine')), edit = find.text('Edit (free)'), add = find.byKey(const Key('ai-script-new'));
    double mid(Finder f) => tester.getCenter(f).dy;
    expect(mid(add), mid(refine));
    expect(mid(edit), closeTo(mid(refine), 2));

    await tester.tap(refine);
    await settle(tester);
    expect(find.text('Refine with AI'), findsOneWidget);

    await tester.tap(add);
    await settle(tester);
    expect(find.text('Write with AI'), findsOneWidget);
    expect(find.text('Use my text'), findsOneWidget);
    expect(find.text('Refine with AI'), findsNothing);
  });

  testWidgets('the My AI videos icon shows how many images and videos were made', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));
    expect(find.descendant(of: find.byKey(const Key('ai-my-videos')), matching: find.text('1')), findsOneWidget);
  });

  // Phone check (24 Nov): unselected chips rendered as white pills with near-white text,
  // because the app-wide ChipTheme won over the chip's own background colour.
  testWidgets('unselected chips are dark, selected ones purple — never white', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));
    for (final label in ['480p', 'Images first', '20s']) {
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip.selected, isFalse);
      final bg = chip.color?.resolve(<WidgetState>{});
      expect(bg, isNotNull, reason: '$label must set its own colour, not inherit the light theme');
      expect(bg!.a, lessThan(0.2), reason: '$label background should be (nearly) transparent on the dark page');
    }
    final on = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '720p'));
    expect(on.color?.resolve({WidgetState.selected}), const Color(0xFF7B2CBF));
  });
}
