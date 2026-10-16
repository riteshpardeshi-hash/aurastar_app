import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/ai_ads_service.dart';
import 'package:aura_app/features/ai_ads/widgets/ai_join_request_sheet.dart';

import 'ai_ads_fake_backend.dart';

// A demo video picked in the join form is uploaded presign → PUT → key (backend ADR 001/131)
// and only its key is sent with the request.
void main() {
  late FakeAiAdsBackend backend;

  setUp(() => backend = FakeAiAdsBackend());
  tearDown(FakeAiAdsBackend.reset);

  testWidgets('uploads the demo video, then sends its key with the request', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ai-join');
    // The fake backend JSON-decodes every body, so the "video" bytes are JSON.
    final video = File('${dir.path}/sample.mov')..writeAsStringSync('{"fake":"video"}');
    backend.on('POST $base/request/demo-video/presign', {
      'key': 'ai-ads/c1/applications/u1/demo.mov',
      'uploadUrl': 'https://s3.test/upload/demo.mov',
      'expiresIn': 300,
      'maxSeconds': 90,
    }, status: 201);
    backend.routes['PUT /upload/demo.mov'] = (_) => FakeAiAdsBackend.ok({});
    backend.on('POST $base/request', {}, status: 201);

    final campaign = AiCampaign.fromJson(campaignJson(myStatus: null));
    bool? sent;
    await pumpAiScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => sent = await showJoinRequestSheet(context, campaign: campaign, pickVideo: () async => video),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-join-link-instagram')), '@me');
    await tester.ensureVisible(find.byKey(const Key('ai-join-add-video')));
    // Reading the picked file is real I/O, which fake-async widget time never completes.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('ai-join-add-video')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.textContaining('sample.mov'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ai-join-terms')));
    await tester.tap(find.byKey(const Key('ai-join-terms')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ai-join-send')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('ai-join-send')));
      for (var i = 0; i < 10 && backend.calls('POST', '$base/request').isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await settle(tester);

    expect(backend.calls('POST', '$base/request/demo-video/presign').single.body, {'contentType': 'video/quicktime', 'sizeBytes': 16});
    expect(backend.calls('PUT', '/upload/demo.mov'), hasLength(1));
    expect(backend.calls('POST', '$base/request').single.body, {
      'acceptTerms': true,
      'links': {'instagram': '@me'},
      'demoVideoKey': 'ai-ads/c1/applications/u1/demo.mov',
    });
    expect(sent, isTrue);
    dir.deleteSync(recursive: true);
  });
}
