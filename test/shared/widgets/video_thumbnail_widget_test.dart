import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/shared/widgets/video_thumbnail_widget.dart';

// Regression coverage for a "Home screen takes too long to load" complaint.
// `video_thumbnail` has no partial/byte-range fetch — extracting a frame
// always downloads the whole clip first. Every VideoThumbnailWidget used to
// fire that download the instant it mounted, so a screen with several
// thumbnails in view (or, worse, an endless grid that repeats the same
// handful of videos over and over) fired many full-video downloads at once,
// all fighting over the same connection. The fix caps how many extractions
// run concurrently and shares one in-flight extraction across widgets
// requesting the same URL.
const _channel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');

// A real, minimal 1x1 PNG — Image.memory must be able to decode whatever the
// fake handler returns, or Flutter's image pipeline throws its own
// unrelated "Invalid image data" exception and fails the test.
Uint8List _fakeImageBytes() => Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0x60, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xFF, 0xFF, 0x03, 0x00, 0x00, 0x06, 0x00, 0x05, 0x57, 0xBF,
      0xAB, 0xD4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    videoThumbnailCache.clear();
  });

  testWidgets('never runs more than 3 extractions at once', (tester) async {
    var inFlight = 0;
    var peakInFlight = 0;
    final calls = <String, Completer<void>>{};

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final video = (call.arguments as Map)['video'] as String;
      inFlight++;
      peakInFlight = peakInFlight < inFlight ? inFlight : peakInFlight;
      final c = Completer<void>();
      calls[video] = c;
      await c.future;
      inFlight--;
      return _fakeImageBytes();
    });

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: List.generate(
          6,
          (i) => SizedBox(
            width: 50,
            height: 50,
            child: VideoThumbnailWidget(videoUrl: 'https://example.com/v$i.mp4'),
          ),
        ),
      ),
    ));

    // Drain in batches: whatever's currently running gets released, which
    // lets the gate dispatch its next batch — repeat until all 6 have
    // reached the handler.
    for (var round = 0; round < 6 && calls.length < 6; round++) {
      await tester.pump(const Duration(milliseconds: 10));
      for (final c in calls.values.where((c) => !c.isCompleted).toList()) {
        c.complete();
      }
    }
    await tester.pumpAndSettle();

    expect(calls.length, 6,
        reason: 'all 6 widgets should eventually get a turn');
    expect(peakInFlight, lessThanOrEqualTo(3),
        reason: 'the extraction gate must cap concurrent downloads to 3, '
            'otherwise every visible thumbnail fights over the same '
            'connection at once');
  });

  testWidgets(
      'shares one in-flight extraction across widgets requesting the same URL',
      (tester) async {
    var callCount = 0;
    final release = Completer<void>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      callCount++;
      await release.future;
      return _fakeImageBytes();
    });

    // Same URL, mounted twice at once — e.g. Dashboard's endless grid, which
    // cycles the same small pool of challenge videos.
    await tester.pumpWidget(const MaterialApp(
      home: Column(
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: VideoThumbnailWidget(videoUrl: 'https://example.com/same.mp4'),
          ),
          SizedBox(
            width: 50,
            height: 50,
            child: VideoThumbnailWidget(videoUrl: 'https://example.com/same.mp4'),
          ),
        ],
      ),
    ));

    await tester.pump(const Duration(milliseconds: 10));

    expect(callCount, 1,
        reason: 'two widgets requesting the identical URL at the same time '
            'must share one extraction, not each download the clip '
            'themselves');

    release.complete();
    await tester.pumpAndSettle();

    expect(videoThumbnailCache['https://example.com/same.mp4'], isNotNull);
  });
}
