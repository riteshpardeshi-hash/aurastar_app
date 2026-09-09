import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/asset_cache_key.dart';
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

  // Regression for "thumbnails reload on every screen". List screens re-fetch
  // in the background (SWR) and hand each card a freshly re-signed URL for
  // the same clip. That must NOT re-extract / flash the shimmer — the cache
  // and didUpdateWidget both key on the unsigned URL now.
  testWidgets('a re-signed URL for the same clip does not re-extract',
      (tester) async {
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      callCount++;
      return _fakeImageBytes();
    });

    Widget host(String url) => MaterialApp(
          home: SizedBox(
            width: 50,
            height: 50,
            child: VideoThumbnailWidget(videoUrl: url),
          ),
        );

    await tester.pumpWidget(host(
        'https://b.s3.amazonaws.com/raw/uid/clip.mp4?X-Amz-Signature=aaaa'));
    await tester.pumpAndSettle();
    expect(callCount, 1);
    expect(find.byType(VideoThumbnailSkeleton), findsNothing);

    // Same clip, new signature — what an SWR list refresh produces.
    await tester.pumpWidget(host(
        'https://b.s3.amazonaws.com/raw/uid/clip.mp4?X-Amz-Signature=zzzz'));
    // One frame only: didUpdateWidget must not have called
    // setState(_loading = true) — the old code did, flashing the shimmer on
    // every screen revisit.
    await tester.pump();
    expect(find.byType(VideoThumbnailSkeleton), findsNothing,
        reason: 'didUpdateWidget must not reload for a query-only URL change');

    await tester.pumpAndSettle();
    expect(callCount, 1, reason: 'no second extraction for the same object');
    expect(find.byType(VideoThumbnailSkeleton), findsNothing,
        reason: 'must not flash back to the loading shimmer');
    expect(
      videoThumbnailCache.keys,
      ['https://b.s3.amazonaws.com/raw/uid/clip.mp4'],
      reason: 'cached under the unsigned key only',
    );

    // A genuinely different clip still extracts.
    await tester.pumpWidget(host(
        'https://b.s3.amazonaws.com/raw/uid/other.mp4?X-Amz-Signature=aaaa'));
    await tester.pumpAndSettle();
    expect(callCount, 2);
  });

  // The network-thumbnail path (thumbnailUrl set) is what the user actually
  // sees reload on every screen: the old Image.network keyed its cache on the
  // full presigned URL, so a re-signed URL = cache miss = re-download +
  // shimmer. CachedNetworkImage keys on `cacheKey` (the unsigned URL), so the
  // key stays put across re-signs even though `imageUrl` changes.
  testWidgets('re-signed thumbnailUrl keeps a stable CachedNetworkImage '
      'cacheKey', (tester) async {
    const path =
        'https://bucket.s3.amazonaws.com/challenge-thumbnails/uid/t.jpg';

    Widget host(String sig) => MaterialApp(
          home: SizedBox(
            width: 60,
            height: 60,
            child: VideoThumbnailWidget(
              videoUrl: 'https://x/v.mp4',
              thumbnailUrl: '$path?X-Amz-Signature=$sig',
            ),
          ),
        );

    await tester.pumpWidget(host('aaaa'));
    await tester.pump();

    var img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.cacheKey, assetCacheKey('$path?X-Amz-Signature=aaaa'));
    expect(img.cacheKey, path);
    expect(img.imageUrl, endsWith('Signature=aaaa'));

    // Background SWR refresh hands the card a freshly signed URL.
    await tester.pumpWidget(host('zzzz'));
    await tester.pump();

    img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.cacheKey, path,
        reason: 'cacheKey unchanged across the re-sign — a disk/mem hit '
            'instead of a fresh download + shimmer on every screen revisit');
    expect(img.imageUrl, endsWith('Signature=zzzz'),
        reason: 'still fetches with a currently-valid signature if needed');
  });
}
