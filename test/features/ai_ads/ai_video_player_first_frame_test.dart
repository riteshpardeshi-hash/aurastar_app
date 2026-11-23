import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/features/ai_ads/widgets/ai_video_player.dart';

// Tester report: after an AI video was generated, its box stayed blank until it was played —
// the player only loaded the video on tap. It now loads straight away so the first frame
// shows, but still never starts playing on its own.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  int plays = 0;
  int _next = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _next++;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 5),
        size: const Size(720, 1280),
      ));
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async => plays++;
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
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox(key: Key('video-frame'));
}

void main() {
  testWidgets('shows the first frame without a tap, and plays only when asked', (tester) async {
    final platform = _FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    tester.view.physicalSize = const Size(400, 1000); // the 9:16 player fits on screen
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AiVideoPlayer(url: 'https://example.com/ad.mp4'))),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byKey(const Key('ai-video-resume')), findsOneWidget); // paused, play button up
    expect(platform.plays, 0);

    await tester.tap(find.byKey(const Key('ai-video-toggle')));
    await tester.pump();
    expect(platform.plays, 1);
    await tester.pump(const Duration(seconds: 3)); // let the controls' hide timer finish
  });
}
