import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/video_prewarm_cache.dart';
import 'package:aura_app/features/video/widgets/video_player_widget.dart';

// Regression coverage for extending prefetching beyond ChallengeDetail: any
// screen that plays a video through VideoPlayerWidget (a creator's video
// grid, My Videos detail, admin review, ...) should transparently benefit
// from a list screen having called VideoPrewarmCache.prewarm ahead of
// navigation — VideoPlayerWidget must check the cache first and reuse an
// already-initialized controller instead of always starting a cold load.
//
// URLs below use .m3u8 — same reasoning as challenge_detail_test.dart's
// staleVideoUrl/freshVideoUrl: VideoPlayerWidget always renders
// VideoThumbnailWidget underneath the player, and a non-HLS URL makes that
// widget attempt real frame extraction, which throws (no video_thumbnail
// platform implementation in tests) but leaves a 30s .timeout() Timer
// pending regardless — .m3u8 short-circuits that path entirely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  testWidgets(
      'a prewarmed controller is reused instead of building a second one',
      (tester) async {
    const url = 'https://example.com/reused.m3u8';
    VideoPrewarmCache.prewarm(url);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    expect(fake.createCount, 1,
        reason: 'sanity check: prewarming alone should have built exactly '
            'one player');

    await tester.pumpWidget(const MaterialApp(home: VideoPlayerWidget(url)));
    // VideoPlayerWidget.initState() reuses the prewarmed controller
    // synchronously, so a single pump is enough to see it reflected.
    await tester.pump();

    expect(fake.createCount, 1,
        reason: 'VideoPlayerWidget must reuse the controller '
            'VideoPrewarmCache already built and initialized, not create a '
            'second one from scratch — that would defeat the entire point '
            'of prewarming');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a URL with nothing prewarmed still loads normally (no crash, no '
      'stuck spinner)', (tester) async {
    const url = 'https://example.com/cold.m3u8';

    await tester.pumpWidget(const MaterialApp(home: VideoPlayerWidget(url)));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(fake.createCount, 1,
        reason: 'with nothing prewarmed, VideoPlayerWidget must still fall '
            'back to building its own controller exactly as before');

    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  int createCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCount++;
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1080, 1920),
    ));
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}
