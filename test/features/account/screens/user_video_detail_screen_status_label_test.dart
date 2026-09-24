import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/features/account/screens/user_video_detail_screen.dart';

// Regression coverage: a submission whose AI scoring failed (backend status
// 'failed' → client 'ai_error') goes to manual admin review. The profile grid
// labels it "Review", but this detail screen treated every non-approved,
// non-pending status as "Rejected" — telling the user their video was
// rejected when it was only waiting on a human (found on-device 2026-09-24).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDetail(WidgetTester tester, String status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserVideoDetailScreen(
          videoNumber: 1,
          auraPoints: 0,
          // .m3u8 short-circuits VideoThumbnailWidget's frame extraction.
          videoUrl: 'https://example.com/video.m3u8',
          videoId: 'video-abc',
          status: status,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('an ai_error video shows "Under review", never "Rejected"', (
    tester,
  ) async {
    await pumpDetail(tester, 'ai_error');

    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
  });

  testWidgets('a genuinely rejected video still shows "Rejected"', (
    tester,
  ) async {
    await pumpDetail(tester, 'rejected');

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Under review'), findsNothing);
  });

  testWidgets('an approved video still shows "Approved"', (tester) async {
    await pumpDetail(tester, 'approved');

    expect(find.text('Approved'), findsOneWidget);
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
