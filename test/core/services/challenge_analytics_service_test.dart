import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenge_analytics_service.dart';

// Client side of the engagement-reporting contract (mobile ADR 012 → 018 →
// 019, canonical definitions in backend ADR 090 / this repo's
// docs/features/engagement-reporting.md):
//
//  * impression  — POST /challenges/{id}/impression, fired on EVERY on-screen
//                  sighting (no per-session de-dup — that used to live here
//                  and was removed in ADR 018).
//  * view        — POST /challenges/{id}/watch-progress with a stable
//                  sessionId per play; the first ping leaves as soon as ≥1s
//                  has been watched so a short view still lands, later pings
//                  are throttled.
//  * share       — POST /challenges/{id}/share (+ optional platform).
//
// Every method is fire-and-forget: a transport failure must never surface.
void main() {
  late List<http.Request> sent;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    ChallengeAnalyticsService().resetForTest();
    sent = [];
    ApiClient.httpClient = MockClient((request) async {
      sent.add(request);
      return http.Response(jsonEncode({'status': 'success'}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ChallengeAnalyticsService().resetForTest();
  });

  // Lets the fire-and-forget (unawaited) POST inside the service run.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  Map<String, dynamic> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  group('recordImpression', () {
    test('sends one POST to /challenges/{id}/impression', () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/challenges/chal-1/impression'));
      expect(sent.single.headers['Authorization'], 'Bearer token');
    });

    test('fires on every call for the same challenge — no per-session de-dup',
        () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-1');
      await settle();

      // Every on-screen sighting is an impression (backend ADR 090). The old
      // "deduped per session" behaviour was removed in ADR 018 — reverting
      // that change makes this expect 1.
      expect(sent, hasLength(3));
      expect(
        sent.map((r) => r.url.path.split('/challenges/').last),
        everyElement('chal-1/impression'),
      );
    });

    test('fires independently per challenge', () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-2');
      await settle();

      expect(sent.map((r) => r.url.path.split('/challenges/').last),
          ['chal-1/impression', 'chal-2/impression']);
    });

    test('an empty challenge id sends nothing', () async {
      ChallengeAnalyticsService().recordImpression('');
      await settle();
      expect(sent, isEmpty);
    });
  });

  group('recordWatchProgress', () {
    test('first ping leaves as soon as ≥1s is watched — no flush needed',
        () async {
      ChallengeAnalyticsService().recordWatchProgress(
        'chal-1',
        watched: const Duration(milliseconds: 1200),
        total: const Duration(seconds: 15),
      );
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.url.path, endsWith('/challenges/chal-1/watch-progress'));
      final body = bodyOf(sent.single);
      expect(body['watchedDuration'], closeTo(1.2, 1e-9));
      expect(body['videoDuration'], 15.0);
      expect(body['sessionId'], isNotEmpty);
    });

    test('under 1s and not flushed → nothing (below the view threshold)',
        () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(milliseconds: 800));
      await settle();
      expect(sent, isEmpty);
    });

    test('after the first ping, sub-threshold ticks are throttled', () async {
      // 1.0s → first ping (view threshold).
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 1));
      // +1.0s and +1.8s: inside both the 3s growth and the 5s gap window → dropped.
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 2));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(milliseconds: 2800));
      await settle();

      expect(sent, hasLength(1));
      expect(bodyOf(sent.single)['watchedDuration'], 1.0);
    });

    // The steady-state throttle is "grown ≥3s AND ≥5s since the last send" —
    // the 5s wall-clock half can't be exercised without fake time, so it is
    // not unit-tested here; `flush` (below) is the escape hatch that matters
    // for correctness (the dispose-time final position).

    test('flush always gets through, even right after a throttled send and even below 1s',
        () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 1));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(milliseconds: 1500), flush: true);
      await settle();

      expect(sent, hasLength(2));
      expect(bodyOf(sent.last)['watchedDuration'], 1.5);
    });

    test('keeps one stable sessionId for a play; a new play gets a new one',
        () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 1));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 9), flush: true);
      await settle();

      final s1 = bodyOf(sent[0])['sessionId'];
      expect(bodyOf(sent[1])['sessionId'], s1);

      // endWatchSession = the player was disposed; the next play is a new view.
      ChallengeAnalyticsService().endWatchSession('chal-1');
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 2), flush: true);
      await settle();

      expect(bodyOf(sent[2])['sessionId'], isNot(s1));
    });

    test('zero / negative watched time sends nothing even with flush', () async {
      ChallengeAnalyticsService()
          .recordWatchProgress('chal-1', watched: Duration.zero, flush: true);
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: -1), flush: true);
      await settle();
      expect(sent, isEmpty);
    });

    test('omits videoDuration when total is null or zero', () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 2));
      await settle();
      expect(bodyOf(sent.single).containsKey('videoDuration'), isFalse);
    });
  });

  group('recordShare', () {
    test('POSTs to /challenges/{id}/share with the platform when given',
        () async {
      ChallengeAnalyticsService()
          .recordShare('chal-1', platform: 'instagram_story');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.url.path, endsWith('/challenges/chal-1/share'));
      expect(bodyOf(sent.single)['platform'], 'instagram_story');
    });

    test('POSTs even without a platform, and omits the platform key', () async {
      ChallengeAnalyticsService().recordShare('chal-1');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.headers['Authorization'], 'Bearer token');
      expect(bodyOf(sent.single).containsKey('platform'), isFalse);
    });

    test('fires every time — shares are a raw count, no de-dup', () async {
      ChallengeAnalyticsService().recordShare('chal-1');
      ChallengeAnalyticsService().recordShare('chal-1');
      await settle();
      expect(sent, hasLength(2));
    });

    test('an empty challenge id sends nothing', () async {
      ChallengeAnalyticsService().recordShare('');
      await settle();
      expect(sent, isEmpty);
    });
  });

  group('failures never surface', () {
    test('a thrown transport error does not propagate to any caller', () async {
      ApiClient.httpClient = MockClient((_) async => throw Exception('boom'));

      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 5), flush: true);
      ChallengeAnalyticsService().recordShare('chal-1');
      await settle();

      // Reached here with no unhandled exception tearing the test down.
      expect(true, isTrue);
    });

    test('a 500 response does not propagate either', () async {
      ApiClient.httpClient = MockClient((_) async => http.Response('nope', 500));

      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 2));
      await settle();

      expect(true, isTrue);
    });
  });
}
