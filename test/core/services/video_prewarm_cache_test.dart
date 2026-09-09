import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/video_prewarm_cache.dart';

// VideoPrewarmCache lets a list screen (home feed, a creator's video grid)
// build and initialize a video's player in the background, ahead of the
// user tapping into it — the screen that actually plays it (ChallengeDetail,
// VideoPlayerWidget) then takes the already-ready controller instead of
// starting a cold load. These tests pin down the cache's own contract in
// isolation, independent of either of those call sites.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });

  test('prewarm() builds and initializes a controller that take() returns',
      () async {
    VideoPrewarmCache.prewarm('https://example.com/prewarm-a.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final controller =
        VideoPrewarmCache.take('https://example.com/prewarm-a.mp4');
    expect(controller, isNotNull);
    expect(controller!.value.isInitialized, isTrue,
        reason: 'take() should only ever hand back a controller that has '
            'already finished initializing — that\'s the whole point');
    controller.dispose();
  });

  test('take() returns null for a URL that was never prewarmed', () {
    expect(VideoPrewarmCache.take('https://example.com/never-prewarmed.mp4'),
        isNull);
  });

  test('take() removes the entry, so a second take() for the same URL '
      'returns null', () async {
    VideoPrewarmCache.prewarm('https://example.com/prewarm-b.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final first = VideoPrewarmCache.take('https://example.com/prewarm-b.mp4');
    expect(first, isNotNull);
    first!.dispose();

    expect(VideoPrewarmCache.take('https://example.com/prewarm-b.mp4'), isNull,
        reason: 'the caller that takes a prewarmed controller now owns it — '
            'a second consumer must not get the same (now-disposed) instance');
  });

  test('prewarming past the cap evicts the oldest still-ready entry',
      () async {
    const urls = [
      'https://example.com/evict-1.mp4',
      'https://example.com/evict-2.mp4',
      'https://example.com/evict-3.mp4',
      'https://example.com/evict-4.mp4',
    ];
    for (final url in urls) {
      VideoPrewarmCache.prewarm(url);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(VideoPrewarmCache.take(urls[0]), isNull,
        reason: 'the cap is 3 ready entries — the oldest (first prewarmed) '
            'must have been evicted once a 4th landed, so this app can\'t '
            'accumulate an unbounded number of live, buffering players just '
            'because a list screen prewarmed a long scroll of videos');

    for (final url in urls.skip(1)) {
      VideoPrewarmCache.take(url)?.dispose();
    }
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
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
