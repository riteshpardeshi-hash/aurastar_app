import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/account/screens/user_video_detail_screen.dart';

// Regression coverage: deleting a video used to run a Firestore transaction
// against a `submissions` document that no longer exists post-migration
// (submissions/videos now live in the REST/Mongo backend, not Firestore).
// That transaction always threw NOT_FOUND, so every delete silently failed
// with "Delete failed. Please try again." — regardless of what the confirm
// dialog claimed about Aura deduction. The fix routes delete through the
// real `DELETE /videos/{id}` endpoint (confirmed in the live OpenAPI spec)
// instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

  late int deleteCalls;
  late String? deletedPath;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });

    deleteCalls = 0;
    deletedPath = null;

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'DELETE' &&
          request.url.path.endsWith('/videos/video-abc')) {
        deleteCalls++;
        deletedPath = request.url.path;
        return http.Response(jsonEncode({'status': 'success'}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'tapping Delete + confirming calls DELETE /videos/{videoId} and pops "deleted"',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserVideoDetailScreen(
                      videoNumber: 1,
                      auraPoints: 50,
                      // .m3u8 short-circuits VideoThumbnailWidget's frame
                      // extraction (real 12s plugin-channel timeout
                      // otherwise), keeping this test scoped to delete.
                      videoUrl: 'https://example.com/video.m3u8',
                      videoId: 'video-abc',
                      status: 'approved',
                    ),
                  ),
                );
                deletedResultHolder.value = result as String?;
              },
              child: const Text('Open Detail'),
            ),
          ),
        ),
      ),
    ));

    // Not pumpAndSettle(): VideoThumbnailSkeleton runs a repeating
    // AnimationController while `_loading` is true, which schedules frames
    // forever and would make pumpAndSettle() time out by design.
    await tester.tap(find.text('Open Detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // finish push transition

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // finish dialog transition

    expect(find.text('Delete Video'), findsOneWidget);
    // The DELETE call goes through package:http's real async machinery even
    // when mocked, which needs the real event loop (not fake-clock pump()
    // alone) to ever resolve — same reasoning as preview_screen_test.dart's
    // upload-race regression test.
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // finish pop transition

    expect(deleteCalls, 1,
        reason: 'delete must go through the real REST endpoint, not a '
            'Firestore transaction against a document that no longer exists');
    expect(deletedPath, endsWith('/videos/video-abc'));
    expect(find.text('Open Detail'), findsOneWidget,
        reason: 'a successful delete should pop back to the caller');
    expect(deletedResultHolder.value, 'deleted');
  });

  // Regression coverage: a failed delete used to show a hardcoded "Delete
  // failed. Please try again." regardless of *why* it failed — swallowing
  // DELETE /videos/{id}'s own documented, specific failure reasons (403
  // "requires ownership", 400 "this is a challenge's reference video", a
  // 404, ...). The snackbar must now surface the backend's actual message
  // so a real failure is diagnosable instead of always looking identical.
  testWidgets(
      'a failed delete shows the backend\'s actual reason, not a generic '
      'message', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'DELETE' &&
          request.url.path.endsWith('/videos/video-abc')) {
        return http.Response(
          jsonEncode({
            'status': 'fail',
            'message': 'You do not have permission to delete this video.',
          }),
          403,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(
      home: UserVideoDetailScreen(
        videoNumber: 1,
        auraPoints: 50,
        videoUrl: 'https://example.com/video.m3u8',
        videoId: 'video-abc',
        status: 'rejected',
      ),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(
        find.text('You do not have permission to delete this video.'),
        findsOneWidget,
        reason: 'the real backend reason must reach the user instead of '
            'the old one-size-fits-all "Delete failed. Please try again."');
    expect(find.text('Delete failed. Please try again.'), findsNothing);
  });

  // Regression coverage: star/like used to read and write a Firestore
  // `submissions` document (`starredBy`/`starsCount` fields, plus an owner
  // `starsReceived` counter) that no longer exists post-migration — the
  // initial load silently no-opped (`if (!doc.exists) return`, so it always
  // showed unstarred/0) and every tap threw, always showing "Could not
  // update star." The fix reads initial state from `GET /videos/{id}` and
  // toggles via the real `POST /videos/{id}/like` endpoint.
  testWidgets(
      'loads initial like state from GET and toggles via POST /videos/{id}/like',
      (tester) async {
    var likeCalls = 0;
    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/videos/video-abc')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'isLiked': false, 'likesCount': 3},
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/videos/video-abc/like')) {
        likeCalls++;
        return http.Response(jsonEncode({'status': 'success'}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(
      home: UserVideoDetailScreen(
        videoNumber: 1,
        auraPoints: 50,
        videoUrl: 'https://example.com/video.m3u8',
        videoId: 'video-abc',
        status: 'approved',
      ),
    ));

    // Not pumpAndSettle(): see the repeating-animation note above.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('3'), findsOneWidget,
        reason: 'initial count must come from GET /videos/{id}, not a '
            'silently-skipped Firestore read that always defaulted to 0');
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.star_outline_rounded));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // Duration pump (not zero) so _StarButton's AnimatedSwitcher finishes
    // its crossfade instead of leaving both icons in the tree mid-transition.
    await tester.pump(const Duration(milliseconds: 250));

    expect(likeCalls, 1,
        reason: 'toggling must call the real POST /videos/{id}/like '
            'endpoint, not throw against a nonexistent Firestore document');
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}

// Simple holder so the test can read the value Navigator.push resolved to,
// without needing a StatefulWidget just for this one assertion.
class _ResultHolder {
  String? value;
}

final deletedResultHolder = _ResultHolder();

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
