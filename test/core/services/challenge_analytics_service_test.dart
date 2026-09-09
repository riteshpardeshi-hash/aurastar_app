import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenge_analytics_service.dart';

// Regression coverage for the bug where the creator/brand analytics `views`
// and `shares` counters were permanently 0 no matter how much real activity
// a challenge got. Root cause: nothing in the app ever fired the events the
// backend builds those counters from. The live OpenAPI spec documents
// `POST /challenges/{id}/impression` ("Fired by the mobile app when this
// Challenge becomes visible inside the feed") and
// `POST /challenges/{id}/watch-progress` ("Fired repeatedly by the mobile
// app while a challenge's video is being watched"); grep for either across
// lib/ returned zero call sites. ChallengeAnalyticsService is the client
// side of that contract. See ADR 012.
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

  group('recordImpression', () {
    test('sends one POST to /challenges/{id}/impression', () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/challenges/chal-1/impression'));
      expect(sent.single.headers['Authorization'], 'Bearer token');
    });

    test('is deduped per session — a repeat for the same challenge is a no-op',
        () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-1');
      await settle();

      expect(sent, hasLength(1));
    });

    test('still fires for a different challenge', () async {
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordImpression('chal-2');
      await settle();

      expect(sent, hasLength(2));
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
    test('flush sends immediately, with sessionId + watched/total seconds',
        () async {
      ChallengeAnalyticsService().recordWatchProgress(
        'chal-1',
        watched: const Duration(milliseconds: 4500),
        total: const Duration(seconds: 15),
        flush: true,
      );
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.url.path, endsWith('/challenges/chal-1/watch-progress'));
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['watchedDuration'], 4.5);
      expect(body['videoDuration'], 15.0);
      expect(body['sessionId'], isNotEmpty);
    });

    test('throttles sub-threshold ticks — only the first crossing sends',
        () async {
      // First tick already past the 3s growth threshold → sends.
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 3));
      // +1s, well inside both the growth and the time-gap window → dropped.
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 4));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(milliseconds: 4200));
      await settle();

      expect(sent, hasLength(1));
      expect((jsonDecode(sent.single.body) as Map)['watchedDuration'], 3.0);
    });

    test('a flush always gets through even right after a throttled send',
        () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 3));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 5), flush: true);
      await settle();

      expect(sent, hasLength(2));
      expect((jsonDecode(sent.last.body) as Map)['watchedDuration'], 5.0);
    });

    test('keeps one stable sessionId until the session is ended', () async {
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 3));
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 9), flush: true);
      await settle();

      final s1 = (jsonDecode(sent[0].body) as Map)['sessionId'];
      final s2 = (jsonDecode(sent[1].body) as Map)['sessionId'];
      expect(s1, s2);

      ChallengeAnalyticsService().endWatchSession('chal-1');
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 2), flush: true);
      await settle();

      final s3 = (jsonDecode(sent[2].body) as Map)['sessionId'];
      expect(s3, isNot(s1));
    });

    test('zero / negative watched time sends nothing', () async {
      ChallengeAnalyticsService()
          .recordWatchProgress('chal-1', watched: Duration.zero, flush: true);
      await settle();
      expect(sent, isEmpty);
    });
  });

  group('recordShare', () {
    test('POSTs to /challenges/{id}/share with the platform when given',
        () async {
      ChallengeAnalyticsService()
          .recordShare('chal-1', platform: 'instagram_story');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/challenges/chal-1/share'));
      expect((jsonDecode(sent.single.body) as Map)['platform'],
          'instagram_story');
    });

    // The share endpoint is live (backend ADR 086/089); the no-platform path
    // is the common one (a plain OS share sheet) and must still POST.
    test('POSTs even without a platform, and omits the platform key', () async {
      ChallengeAnalyticsService().recordShare('chal-1');
      await settle();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/challenges/chal-1/share'));
      expect(sent.single.headers['Authorization'], 'Bearer token');
      expect((jsonDecode(sent.single.body) as Map).containsKey('platform'),
          isFalse);
    });

    test('an empty challenge id sends nothing', () async {
      ChallengeAnalyticsService().recordShare('');
      await settle();
      expect(sent, isEmpty);
    });
  });

  group('failures never surface', () {
    test('a 500 / thrown transport error does not propagate to the caller',
        () async {
      ApiClient.httpClient = MockClient((_) async => throw Exception('boom'));

      // None of these await, and none should throw.
      ChallengeAnalyticsService().recordImpression('chal-1');
      ChallengeAnalyticsService().recordWatchProgress('chal-1',
          watched: const Duration(seconds: 5), flush: true);
      ChallengeAnalyticsService().recordShare('chal-1');
      await settle();

      // Got here without an unhandled exception tearing the test down.
      expect(true, isTrue);
    });
  });
}
