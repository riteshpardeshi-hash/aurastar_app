import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/video/screens/preview_screen.dart';

// Regression coverage: a network drop mid-upload puts the screen into the
// `failed` state and arms an auto-retry timer. Because
// `_upload()` had no re-entrancy guard, that timer firing and a manual tap
// of "Retry Upload" could both be mid-flight at once (the race window is
// the `await` before either call updates `_uploadState`) — each running
// its own presign + S3 PUT + create-submission sequence. Whichever finished
// last simply overwrote `_uploadState`, so a successful upload could get
// clobbered back to `failed`, leaving the user stuck on an error screen
// despite (possibly duplicate) submissions having gone through.
//
// A fake VideoPlayerPlatform stands in for the plugin (no platform channel
// is registered in `flutter test`) so PreviewScreen's real initState/build
// path runs unmodified.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

  late File videoFile;
  late int presignCalls;
  late int s3PutCalls;
  late int createSubmissionCalls;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});

    videoFile = File(
        '${Directory.systemTemp.path}/preview_screen_test_${DateTime.now().microsecondsSinceEpoch}.mp4');
    await videoFile.writeAsBytes(List<int>.filled(256, 1));

    presignCalls = 0;
    s3PutCalls = 0;
    createSubmissionCalls = 0;

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'PUT' &&
          request.url.host == 'mock-upload.example') {
        s3PutCalls++;
        return http.Response('', 200);
      }
      if (request.url.path.endsWith('/submissions/presign')) {
        presignCalls++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'uploadUrl': 'https://mock-upload.example/put',
              'videoId': 'video-$presignCalls',
            },
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/submissions')) {
        createSubmissionCalls++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submission': {'_id': 'submission-$createSubmissionCalls'},
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });

  tearDown(() async {
    ApiClient.httpClient = http.Client();
    if (await videoFile.exists()) await videoFile.delete();
  });

  testWidgets(
      'tapping Submit twice back-to-back only runs one upload, not two',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PreviewScreen(
        videoPath: videoFile.path,
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
      ),
    ));
    // Let initState's video initialization settle.
    await tester.pump();
    await tester.pump();

    final submitButton = find.text('Submit for Aura Score');
    expect(submitButton, findsOneWidget);

    // Two taps fired back-to-back reproduce the real race: the first tap's
    // _upload() sets the in-flight guard synchronously before its first
    // await, so the second tap's _upload() call must see it and bail —
    // exactly the same guard that has to hold between the auto-retry timer
    // and a manual "Retry Upload" tap in `failed` state. Wrapped in
    // runAsync() because UploadQueueService.hasInternet() does a real DNS
    // lookup, which needs the real event loop (not the fake-clock zone
    // `pump()` runs in) to ever resolve.
    await tester.runAsync(() async {
      await tester.tap(submitButton);
      await tester.tap(submitButton);
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();

    expect(presignCalls, 1,
        reason: 'a second concurrent tap must not start its own upload '
            'while one is already in flight');
    expect(s3PutCalls, 1);
    expect(createSubmissionCalls, 1);
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
    return Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(1920, 1080),
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
