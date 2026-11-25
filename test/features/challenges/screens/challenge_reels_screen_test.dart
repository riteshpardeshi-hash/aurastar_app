import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/challenges/screens/challenge_reels_screen.dart';

// Client, 25 Nov 2026: the reels feed (centre star button) shows each video
// once. It used to wrap back to page 1 after the last page, so 100 videos
// scrolled forever, the same 100 again and again. Now it ends after the last
// one, and a video that shifts onto a later page is never shown twice.
Map<String, dynamic> _challenge(int i) => {
      '_id': 'c$i',
      'title': 'Challenge $i',
      'videoUrl': 'https://cdn.test/v$i.mp4',
      'submissionsCount': 0,
      'creatorId': 'system',
    };

void main() {
  final requestedPages = <String>[];

  setUp(() {
    requestedPages.clear();
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    // 21 challenges: page 1 has c0..c19, page 2 has c18 and c19 again (new
    // challenges shifted them) plus c20. Pages past 2 are empty.
    ApiClient.httpClient = MockClient((request) async {
      if (!request.url.path.endsWith('/challenges')) {
        return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
      }
      final page = request.url.queryParameters['page'] ?? '1';
      requestedPages.add(page);
      final list = switch (page) {
        '1' => [for (var i = 0; i < 20; i++) _challenge(i)],
        '2' => [_challenge(18), _challenge(19), _challenge(20)],
        _ => <Map<String, dynamic>>[],
      };
      return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'challenges': list}
          }),
          200);
    });
  });

  tearDown(() => ApiClient.httpClient = http.Client());

  PageController controllerOf(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!;

  testWidgets('the feed ends after the last video: no repeats, no starting over',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChallengeReelsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Near the end of page 1, page 2 loads.
    controllerOf(tester).jumpToPage(18);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 21 distinct videos + one "all caught up" page; c18/c19 aren't added twice.
    final view = tester.widget<PageView>(find.byType(PageView));
    final delegate = view.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 22);

    controllerOf(tester).jumpToPage(21);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("You're all caught up"), findsOneWidget);

    // Never asks for page 1 again (the old feed wrapped back to it).
    expect(requestedPages.where((p) => p == '1'), hasLength(1));
    expect(delegate.childCount, 22);

    // Let the screen's timers (analytics flush, playback) finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _nextPlayerId++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 5),
        size: const Size(1080, 1920),
      ));

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
