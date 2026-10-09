import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/features/explore/screens/creator_profile_screen.dart';

import '../ai_ads/ai_ads_fake_backend.dart';

// A creator's own videos open in a full-screen viewer from their profile. That viewer had
// no way to report the video (backend ADR 117) — only the profile's ⋯ could report the
// whole account.
void main() {
  late FakeAiAdsBackend backend;
  setUp(() {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 't',
      'api_refresh_token': 'r',
      'api_user_id': 'me',
    });
    backend = FakeAiAdsBackend();
    backend.on('GET /creators/u9', {'creator': {'_id': 'u9', 'displayName': 'Riya'}});
    backend.on('GET /creators/u9/videos', [
      {'_id': 'v42', 'videoUrl': 'https://example.com/v.mp4', 'thumbnailUrl': 'https://example.com/t.jpg', 'aiScore': 71},
    ]);
    backend.on('GET /creators/u9/followers', {'responses': [], 'totalCount': 0});
    backend.on('GET /challenges', {'responses': []});
  });
  tearDown(FakeAiAdsBackend.reset);

  testWidgets("someone else's video has a flag that reports that video", (tester) async {
    backend.on('POST /videos/v42/report', {'alreadyReported': false}, status: 201);
    await pumpAiScreen(tester, const CreatorProfileScreen(creatorId: 'u9'));
    tester.takeException(); // thumbnails can't load in tests

    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'VideoThumbnailWidget').first);
    await settle(tester);
    tester.takeException(); // no video plugin in tests

    await tester.tap(find.byKey(const Key('video-safety-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-report-video')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-reason-inappropriate')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('safety-report-send')));
    await settle(tester);

    expect(backend.calls('POST', '/videos/v42/report').single.body, {'reason': 'inappropriate'});
  });

  testWidgets('your own video has no report flag', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'api_access_token': 't', 'api_refresh_token': 'r', 'api_user_id': 'u9'});
    await pumpAiScreen(tester, const CreatorProfileScreen(creatorId: 'u9'));
    tester.takeException();

    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'VideoThumbnailWidget').first);
    await settle(tester);
    tester.takeException();

    expect(find.byKey(const Key('video-safety-menu')), findsNothing);
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    return _nextPlayerId++;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return Stream.value(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 5),
        size: const Size(1920, 1080),
      ),
    );
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
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}
