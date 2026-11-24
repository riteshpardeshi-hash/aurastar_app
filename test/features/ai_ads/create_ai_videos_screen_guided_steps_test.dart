import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/ai_ads/screens/ai_brand_assets_row.dart';
import 'package:aura_app/features/ai_ads/screens/create_ai_videos_screen.dart';

import 'package:aura_app/features/ai_ads/widgets/ai_ui.dart';

import 'ai_ads_fake_backend.dart';

// Client feedback (24 Nov): the workspace opened on "Your images & videos", so creators
// landed on old work instead of making the next ad. It now reads as guided steps — the
// brief folded, 1 Script, 2 Style, then Your images and Your videos — with Generate pinned to the
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

    final script = find.text('Script'), style = find.text('Style'), work = find.text('Your videos');
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

  // Phone check (24 Nov): Material ChoiceChips took the app's light theme on device and
  // showed unselected options as white blanks with unreadable labels. The pills now paint
  // their own colours, independent of the theme.
  testWidgets('unselected pills are dark with readable labels, selected ones purple', (tester) async {
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));
    expect(find.byType(ChoiceChip), findsNothing);

    BoxDecoration paint(String label) => tester
        .widget<AnimatedContainer>(find.descendant(of: find.widgetWithText(AiPill, label), matching: find.byType(AnimatedContainer)))
        .decoration! as BoxDecoration;
    for (final label in ['15s', 'Images first', '20s']) {
      expect(tester.widget<AiPill>(find.widgetWithText(AiPill, label)).selected, isFalse);
      expect(paint(label).color!.a, lessThan(0.2), reason: '$label must not be a white pill');
      expect(tester.widget<Text>(find.text(label)).style!.color, isNot(Colors.white));
    }
    expect(paint('10s').color, AiUi.accent);
  });

  // Client feedback (24 Nov): don't merge images and videos into one collection — show
  // the images first, then the videos, as two separate sections.
  testWidgets('images and videos are two separate collections, images first', (tester) async {
    backend.on('GET $base/workspace', workspaceJson(generations: [
      generationJson(id: 's1'),
      // Videos still being made: no thumbnail fetch (its 30 s timeout would outlive the test).
      generationJson(id: 'v1', stage: 'VIDEO', scriptId: 's1', status: 'RUNNING'),
      generationJson(id: 'i1', stage: 'IMAGE', scriptId: 's1', output: {'imageUrls': ['https://s3/a.png']}),
      generationJson(id: 'v2', stage: 'VIDEO', scriptId: 's1', version: 2, status: 'RUNNING'),
    ]));
    await pumpAiScreen(tester, const CreateAiVideosScreen(campaignId: campaignId));

    final images = top(tester, find.text('Your images')), videos = top(tester, find.text('Your videos'));
    expect(images, lessThan(videos));
    final i1 = top(tester, find.byKey(const Key('ai-work-i1')));
    expect(i1, greaterThan(images));
    expect(i1, lessThan(videos));
    for (final v in ['v1', 'v2']) {
      expect(top(tester, find.byKey(Key('ai-work-$v'))), greaterThan(videos));
    }
  });
}
