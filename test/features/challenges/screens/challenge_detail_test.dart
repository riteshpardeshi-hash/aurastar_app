import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/challenges/screens/challenge_detail.dart';

// Regression coverage for "ghost mode isn't playing for some videos".
// Nearly every list screen (home feed, dashboard, trending, etc.) constructs
// ChallengeDetail with a videoUrl it already had lying around, and
// ChallengeDetail only overwrote that with the freshly-fetched value from
// GET /challenges/{id} `if (_videoUrl.isEmpty)`. Per openapi.yaml,
// Challenge.videoUrl is a presigned (expiring) URL while the reference video
// is still processing — so a videoUrl handed down from a list screen the
// user briefly browsed earlier can outlive its signature by the time they
// open the challenge, and the old code kept using that stale value forever
// instead of the live one this screen just fetched. That same value is
// handed straight to CameraScreen's ghost overlay, which then silently fails
// to initialize for any challenge still processing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVideoPlayerPlatform fakeVideoPlayer;

  // .m3u8 URLs short-circuit both VideoThumbnailWidget's frame extraction
  // (VideoThumbnail plugin isn't available/mocked here, and leaves a pending
  // 12s timer if it runs) and VideoCacheService's disk caching — neither is
  // under test, only which videoUrl string ends up passed to the video
  // player platform.
  const staleVideoUrl =
      'https://raw-bucket.s3.amazonaws.com/raw/uid/stale-expired/hls.m3u8?sig=old';
  const freshVideoUrl =
      'https://processed-bucket.s3.amazonaws.com/processed/uid/fresh/hls.m3u8';

  setUp(() {
    fakeVideoPlayer = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakeVideoPlayer;
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/challenges/challenge-1')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenge': {
                '_id': 'challenge-1',
                'title': 'Test Challenge',
                'instructions': '',
                'videoUrl': freshVideoUrl,
                'thumbnailUrl': '',
                'starsCount': 10,
                'submissionsCount': 0,
                'category': 'dance',
                'difficulty': 'Easy',
                'sourceType': 'Aura Original',
                'creatorId': 'system',
                'isActive': true,
              },
            },
          }),
          200,
        );
      }
      // Submissions lookups aren't under test — ChallengesService already
      // swallows any failure here and returns [] / null.
      return http.Response('', 500);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'a freshly-fetched videoUrl replaces a stale one the caller already had',
      (tester) async {
    // This screen's Stack/Positioned layout is tuned for a phone aspect
    // ratio; the default 800x600 test surface makes an unrelated overlay
    // cover the video thumbnail's hit-test area.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Test Challenge',
        instructions: '',
        videoUrl: staleVideoUrl,
        challengeId: 'challenge-1',
      ),
    ));

    // Let _fetchChallengeData's GET resolve and setState apply.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      fakeVideoPlayer.lastUri,
      freshVideoUrl,
      reason: 'the on-screen preview (and, identically, the videoUrl handed '
          'to CameraScreen\'s ghost overlay) must use the freshly-fetched '
          'videoUrl, not the possibly-expired one the calling list screen '
          'already had',
    );
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  String? lastUri;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    lastUri = options.dataSource.uri;
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
