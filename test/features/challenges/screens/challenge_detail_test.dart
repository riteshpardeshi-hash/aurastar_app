import 'dart:async';
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
                'status': 'approved',
              },
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/challenges/challenge-participated')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenge': {
                '_id': 'challenge-participated',
                'title': 'Participated Challenge',
                'instructions': '',
                'videoUrl': freshVideoUrl,
                'thumbnailUrl': '',
                'starsCount': 0,
                'submissionsCount': 1,
                'category': 'dance',
                'difficulty': 'Easy',
                'sourceType': 'Aura Original',
                'creatorId': 'system',
                'isActive': true,
                'status': 'approved',
              },
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path
              .endsWith('/challenges/challenge-participated/submissions/me')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submissions': [
                {
                  '_id': 'sub-1',
                  'aiScore': 42,
                  'status': 'scored',
                  'verdict': 'GOOD',
                },
              ],
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/challenges/challenge-pending')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenge': {
                '_id': 'challenge-pending',
                'title': 'Pending Challenge',
                'instructions': '',
                'videoUrl': freshVideoUrl,
                'thumbnailUrl': '',
                'starsCount': 0,
                'submissionsCount': 0,
                'category': 'dance',
                'difficulty': 'Easy',
                'sourceType': 'Aura Original',
                'creatorId': 'system',
                'isActive': true,
                'status': 'pending',
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

  // Regression coverage: _isPaused used to be hardcoded to `false`, so a
  // challenge whose backend `status` isn't `approved` (POST
  // /challenges/{id}/submissions requires `approved` per openapi.yaml) still
  // showed the normal "Take Challenge" CTA. The user only found out the
  // challenge wasn't accepting submissions after recording a full take and
  // uploading it, when PreviewScreen surfaced the server's 400. This screen
  // must know up front instead.
  testWidgets(
      'a non-approved challenge shows "Submissions Paused" instead of the '
      'take-challenge CTA', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Pending Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-pending',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Submissions Paused'), findsOneWidget);
    expect(find.text('Take this Challenge'), findsNothing);
  });

  // Regression coverage: the previous fix above only checked _isPaused
  // *after* the fetch resolved. But _isPaused starts out `false` and the
  // "Take this Challenge" CTA was tappable on the very first frame, before
  // GET /challenges/{id} had a chance to come back — a real race on any
  // network slower than the test harness's synchronous mock. A user could
  // tap through to the camera, record, and upload before the paused status
  // was ever known client-side. The CTA must not appear until the status
  // check has actually resolved.
  testWidgets(
      'the take-challenge CTA is not shown before the status check resolves',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Pending Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-pending',
      ),
    ));

    // Single frame, before the mocked GET has resolved.
    await tester.pump();

    expect(find.text('Take this Challenge'), findsNothing);
  });

  // Regression coverage: fetchChallenge() swallows its own errors and
  // returns null (see ChallengesService), so a transient network failure
  // used to leave _isPaused at its `false` default forever — silently
  // failing open instead of blocking the CTA.
  testWidgets(
      'a failed status check does not fall back to the take-challenge CTA',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Unreachable Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-unreachable',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Take this Challenge'), findsNothing);
  });

  // Regression coverage: without `mixWithOthers: true`, ExoPlayer/
  // AVAudioSession request *exclusive* audio focus, and their default
  // focus-loss handling auto-pauses playback for any transient system sound
  // (a notification tone, a keyboard click, an incoming-call banner, a
  // Bluetooth chime, Assistant's hotword, ...) with no plugin-level signal
  // to auto-resume afterward. The app never even leaves the foreground, so
  // nothing else notices either — from the user's side, the reference video
  // just "randomly pauses itself." This is a short instructional demo clip,
  // not long-form content, so mixing with (rather than interrupting) other
  // audio is the right trade-off.
  testWidgets(
      'the reference video player opts in to mixWithOthers so a transient '
      'system sound cannot auto-pause it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Test Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fakeVideoPlayer.lastMixWithOthers, isTrue,
        reason: 'without this, the OS is free to auto-pause the reference '
            'video for any transient system sound, with no way for the app '
            'to auto-resume it afterward');
  });

  // Regression coverage for "video playback gets stuck with a loading
  // spinner and does not play smoothly": the reference clip streams over the
  // network (HLS can't be pre-cached locally), so a slow connection can
  // stall mid-playback. VideoPlayer itself gives no visual cue of that on
  // its own — it just silently holds the last decoded frame, which reads as
  // frozen/broken rather than "buffering, will resume."
  testWidgets(
      'shows a buffering indicator over the fullscreen player while its '
      'stream stalls, and hides it once buffering ends', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Test Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'playback just started cleanly, nothing should be buffering '
            'yet');

    fakeVideoPlayer.setBuffering(true);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'a mid-playback stall must show a buffering indicator, not '
            'silently hold the last frame with no explanation');

    fakeVideoPlayer.setBuffering(false);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the indicator must disappear again once buffering ends');
  });

  // Coverage for prefetching: the reference video's player should be built
  // and initialized in the background as soon as the screen loads, not
  // deferred until the user taps the play button — otherwise tapping play
  // still has to wait on the same load the prefetch was supposed to avoid.
  testWidgets(
      'the reference video player is created before the user ever taps '
      'play, and tapping play reuses it instead of creating a second one',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Test Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fakeVideoPlayer.createCount, 1,
        reason: 'the player should already be built and initializing in '
            'the background before the user does anything — this is the '
            'whole point of prefetching');
    expect(fakeVideoPlayer.lastUri, freshVideoUrl);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fakeVideoPlayer.createCount, 1,
        reason: 'tapping play should reuse the prefetched player, not '
            'build a second one from scratch');
    expect(find.byIcon(Icons.close), findsOneWidget,
        reason: 'fullscreen playback should have opened using the '
            'prefetched, already-initialized player');
  });

  // Regression coverage: "See Leaderboard" is always visible on every
  // challenge detail page, but tapping it before the viewer has actually
  // taken *this* challenge must not open the board — _mySubmission (set from
  // GET /challenges/{id}/submissions/me) is the only signal this screen has
  // for that. challenge-1's /submissions/me isn't mocked here, so it falls
  // through to the shared 500 catch-all, which fetchMySubmission swallows
  // into null, i.e. "not participated."
  testWidgets(
      'the See Leaderboard button is always visible, but tapping it before '
      'participating shows a locked notice instead of navigating',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Test Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-1',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('See Leaderboard'), findsOneWidget,
        reason: 'the button itself is unconditional — every challenge '
            'detail page shows it');

    await tester.tap(find.text('See Leaderboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Take this challenge at least once to see its leaderboard.'),
      findsOneWidget,
    );
    expect(find.byType(AppBar), findsNothing,
        reason: 'ChallengeDetail has no AppBar of its own — one appearing '
            'here would mean it wrongly navigated to the leaderboard screen '
            'despite no participation');
  });

  testWidgets(
      'the See Leaderboard button appears once the viewer has taken the '
      'challenge, and opens the per-challenge leaderboard on tap',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: ChallengeDetail(
        title: 'Participated Challenge',
        instructions: '',
        videoUrl: freshVideoUrl,
        challengeId: 'challenge-participated',
      ),
    ));

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('See Leaderboard'), findsOneWidget);

    await tester.tap(find.text('See Leaderboard'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Participated Challenge'),
      ),
      findsOneWidget,
      reason: 'the leaderboard screen shows the challenge title in its '
          'app bar (ChallengeDetail itself has no AppBar, so this can only '
          'match the pushed ChallengeLeaderboardScreen)',
    );
    expect(find.text('No scores yet'), findsOneWidget,
        reason: 'the submissions list is unmocked (500, swallowed to []) '
            'for this challenge, so the board renders its empty state');
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  int createCount = 0;
  String? lastUri;
  bool? lastMixWithOthers;
  // Kept open (unlike a one-shot Stream.value) so a test can push further
  // events — e.g. bufferingStart/bufferingEnd — after initialization.
  final Map<int, StreamController<VideoEvent>> _eventControllers = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    lastMixWithOthers = mixWithOthers;
  }

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    createCount++;
    lastUri = options.dataSource.uri;
    final id = _nextPlayerId++;
    final controller = StreamController<VideoEvent>();
    _eventControllers[id] = controller;
    controller.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1080, 1920),
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return _eventControllers[playerId]!.stream;
  }

  /// Simulates the reference clip's network stream stalling (or resuming)
  /// for the most recently created player.
  void setBuffering(bool buffering) {
    final id = _nextPlayerId - 1;
    _eventControllers[id]?.add(VideoEvent(
      eventType: buffering
          ? VideoEventType.bufferingStart
          : VideoEventType.bufferingEnd,
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
