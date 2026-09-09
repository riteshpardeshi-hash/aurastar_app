import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/videos_service.dart';

// Regression coverage: a user deletes a video, but it stays in the "My
// Videos" grid — GET /profile/videos keeps returning it after
// DELETE /videos/{id} soft-deletes it, and the server-side "deleted" marker
// the client used to filter on (top-level status: "inactive") was observed
// missing on a still-listed deleted video. Re-deleting then 404s ("video
// not found"). The fix: remember deleted ids for the session and treat a
// 404 as an already-satisfied delete.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
    VideosService.resetLocallyDeletedForTest();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    VideosService.resetLocallyDeletedForTest();
  });

  test('a successful delete makes isDeletedVideo true for that id', () async {
    ApiClient.httpClient = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, endsWith('/videos/vid-1'));
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    await VideosService().deleteVideo('vid-1');

    expect(VideosService.isDeletedVideo({'videoId': 'vid-1'}), isTrue);
    expect(VideosService.isDeletedVideo({'_id': 'vid-1'}), isTrue);
    expect(VideosService.isDeletedVideo({'_id': 'other'}), isFalse);
  });

  test('a deleted id survives an app relaunch (persisted, not session-only)',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    await VideosService().deleteVideo('vid-relaunch');
    expect(VideosService.isDeletedVideo({'_id': 'vid-relaunch'}), isTrue);

    // Simulate a cold start: in-memory set + hydration future are gone, but
    // SharedPreferences (the mock store) persists across the "relaunch".
    VideosService.resetLocallyDeletedForTest();
    expect(VideosService.isDeletedVideo({'_id': 'vid-relaunch'}), isFalse,
        reason: 'nothing in memory yet before hydrate()');

    await VideosService.hydrate();
    expect(VideosService.isDeletedVideo({'_id': 'vid-relaunch'}), isTrue,
        reason: 'hydrate() must restore the id deleted before the relaunch');
  });

  test('deleting before the grid is opened keeps ids persisted earlier',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    // First launch: delete A, then relaunch.
    await VideosService().deleteVideo('vid-A');
    VideosService.resetLocallyDeletedForTest();

    // Second launch: delete B straight from a video detail screen, without
    // ever opening the grid (so hydrate() wasn't called first by a caller).
    await VideosService().deleteVideo('vid-B');

    VideosService.resetLocallyDeletedForTest();
    await VideosService.hydrate();
    expect(VideosService.isDeletedVideo({'_id': 'vid-A'}), isTrue,
        reason: 'deleteVideo must not overwrite ids from an earlier launch');
    expect(VideosService.isDeletedVideo({'_id': 'vid-B'}), isTrue);
  });

  test('a "video not found" response is treated as an already-done delete, '
      'not an error', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'fail', 'message': 'Video not found.'}),
        404,
      );
    });

    // Must not throw — re-deleting a still-listed soft-deleted video is a
    // no-op success from the user's point of view.
    await VideosService().deleteVideo('vid-2');

    expect(VideosService.isDeletedVideo({'videoId': 'vid-2'}), isTrue);
  });

  test('a genuine failure (ownership / reference video) still throws', () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'fail',
          'message': 'This action requires ownership of the video.',
        }),
        403,
      );
    });

    await expectLater(
      VideosService().deleteVideo('vid-3'),
      throwsA(isA<String>()),
    );
    expect(VideosService.isDeletedVideo({'videoId': 'vid-3'}), isFalse);
  });

  group('deleted-video Aura offset', () {
    // The backend doesn't debit Aura when a user deletes their own video
    // (openapi.yaml: DELETE /videos/{id} is a bare soft-delete). VideosService
    // tracks the lost points locally and subtracts them from displayed
    // balances until the backend catches up. See ADR 008 /
    // docs/backend-issues/003-*.
    MockClient okDelete() =>
        MockClient((_) async => http.Response('{"status":"success"}', 200));

    test('deleting an approved video subtracts its points from a balance',
        () async {
      ApiClient.httpClient = okDelete();

      expect(VideosService.deletedVideoAuraOffset, 0);
      expect(VideosService.adjustBalanceForDeletedVideos(1000), 1000);

      await VideosService().deleteVideo('vid-a', auraPoints: 48);

      expect(VideosService.deletedVideoAuraOffset, 48);
      expect(VideosService.adjustBalanceForDeletedVideos(1000), 952);
    });

    test('a video that earned nothing leaves the balance untouched', () async {
      ApiClient.httpClient = okDelete();

      await VideosService().deleteVideo('vid-none', auraPoints: 0);

      expect(VideosService.deletedVideoAuraOffset, 0);
      expect(VideosService.adjustBalanceForDeletedVideos(1000), 1000);
    });

    test('the adjusted balance is floored at zero, never negative', () async {
      ApiClient.httpClient = okDelete();

      await VideosService().deleteVideo('vid-big', auraPoints: 5000);

      expect(VideosService.adjustBalanceForDeletedVideos(1000), 0);
    });

    test('the offset survives an app relaunch (persisted)', () async {
      ApiClient.httpClient = okDelete();

      await VideosService().deleteVideo('vid-relaunch', auraPoints: 30);
      expect(VideosService.deletedVideoAuraOffset, 30);

      VideosService.resetLocallyDeletedForTest();
      expect(VideosService.deletedVideoAuraOffset, 0,
          reason: 'nothing loaded before hydrate()');

      await VideosService.hydrate();
      expect(VideosService.deletedVideoAuraOffset, 30,
          reason: 'hydrate() must restore the offset from a previous launch');
    });

    test('re-deleting a still-listed soft-deleted video does not stack the '
        'deduction', () async {
      var call = 0;
      ApiClient.httpClient = MockClient((_) async {
        call++;
        return call == 1
            ? http.Response('{"status":"success"}', 200)
            : http.Response(
                jsonEncode(
                    {'status': 'fail', 'message': 'Video not found.'}),
                404);
      });

      await VideosService().deleteVideo('vid-dup', auraPoints: 25);
      await VideosService().deleteVideo('vid-dup', auraPoints: 25);

      expect(VideosService.deletedVideoAuraOffset, 25);
    });

    test('the offset is stable across balance swings and relaunches — an '
        'unrelated server-balance drop must not erode it', () async {
      // Regression: the offset used to be auto-reconciled — any drop in the
      // server balance shrank it, on the theory the backend had debited the
      // deleted video. But the balance also drops for unrelated reasons (the
      // daily-valid-score-limit replacement, reward redemptions, two call
      // sites reading different balance endpoints), and each false positive
      // permanently eroded the offset until the deleted video's Aura
      // reappeared a session later. The offset now only changes on delete.
      ApiClient.httpClient = okDelete();

      await VideosService().deleteVideo('vid-stable', auraPoints: 48);
      expect(VideosService.deletedVideoAuraOffset, 48);

      // Balance dips (e.g. a daily-score replacement) then recovers — the
      // offset is untouched throughout.
      expect(VideosService.adjustBalanceForDeletedVideos(940), 892);
      expect(VideosService.adjustBalanceForDeletedVideos(1000), 952);
      expect(VideosService.deletedVideoAuraOffset, 48);

      // Relaunch: the same 48 comes back from prefs, not a decayed value.
      VideosService.resetLocallyDeletedForTest();
      await VideosService.hydrate();
      expect(VideosService.deletedVideoAuraOffset, 48);
      expect(VideosService.adjustBalanceForDeletedVideos(1000), 952);
    });

    test('hydrate clears the retired reconcile-baseline pref key', () async {
      SharedPreferences.setMockInitialValues({
        'videos_service.deleted_video_aura': 20,
        'videos_service.deleted_video_aura_baseline': 900,
      });
      VideosService.resetLocallyDeletedForTest();

      await VideosService.hydrate();

      expect(VideosService.deletedVideoAuraOffset, 20);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('videos_service.deleted_video_aura_baseline'),
          isFalse);
    });
  });

  group('applyDeletedVideoOffsetToLeaderboard', () {
    // The server ranks the current user on their pre-deletion Aura total, so
    // the Leaderboard kept showing the stale score AND the stale (too-high)
    // position even after the dashboard/wallet had dropped. This re-scores
    // and re-positions just the user's own row. See ADR 008 / backend-issue
    // 003.
    MockClient okDelete() =>
        MockClient((_) async => http.Response('{"status":"success"}', 200));

    List<Map<String, dynamic>> board() => [
          {'id': 'a', 'score': 1500},
          {'id': 'b', 'score': 1200},
          {'id': 'me', 'score': 1100},
          {'id': 'c', 'score': 900},
          {'id': 'd', 'score': 400},
        ];

    test('no offset: the list is returned unchanged', () {
      final input = board();
      expect(
        VideosService.applyDeletedVideoOffsetToLeaderboard(input, 'me'),
        same(input),
      );
    });

    test('drops the user row to the rank their post-deletion score earns',
        () async {
      ApiClient.httpClient = okDelete();
      await VideosService().deleteVideo('vid-x', auraPoints: 300); // 1100 -> 800

      final out =
          VideosService.applyDeletedVideoOffsetToLeaderboard(board(), 'me');

      expect(out.map((e) => e['id']), ['a', 'b', 'c', 'me', 'd'],
          reason: 'me (800) now sits below c (900), above d (400)');
      expect(out.firstWhere((e) => e['id'] == 'me')['score'], 800);
      // Every other row keeps its server order and score.
      expect(out.where((e) => e['id'] != 'me').map((e) => e['score']),
          [1500, 1200, 900, 400]);
    });

    test('a large offset floors the score at 0 and sinks the row to last',
        () async {
      ApiClient.httpClient = okDelete();
      await VideosService().deleteVideo('vid-big', auraPoints: 9999);

      final out =
          VideosService.applyDeletedVideoOffsetToLeaderboard(board(), 'me');

      expect(out.last['id'], 'me');
      expect(out.last['score'], 0);
    });

    test('no-op when the current user is not in the loaded page', () async {
      ApiClient.httpClient = okDelete();
      await VideosService().deleteVideo('vid-y', auraPoints: 300);

      final input = board().where((e) => e['id'] != 'me').toList();
      final out =
          VideosService.applyDeletedVideoOffsetToLeaderboard(input, 'me');
      expect(out.map((e) => e['id']), ['a', 'b', 'c', 'd']);
    });

    test('no-op when there is no current user id', () async {
      ApiClient.httpClient = okDelete();
      await VideosService().deleteVideo('vid-z', auraPoints: 300);

      final input = board();
      expect(
        VideosService.applyDeletedVideoOffsetToLeaderboard(input, null),
        same(input),
      );
    });
  });

  group('isDeletedVideo server-side markers', () {
    test('top-level status "inactive" (the 2026-08-05 marker)', () {
      expect(VideosService.isDeletedVideo({'_id': 'v', 'status': 'inactive'}),
          isTrue);
    });

    test('status "deleted"', () {
      expect(VideosService.isDeletedVideo({'_id': 'v', 'status': 'deleted'}),
          isTrue);
    });

    test('isDeleted: true', () {
      expect(VideosService.isDeletedVideo({'_id': 'v', 'isDeleted': true}),
          isTrue);
    });

    test('a non-null deletedAt', () {
      expect(
        VideosService.isDeletedVideo(
            {'_id': 'v', 'deletedAt': '2026-08-27T18:00:00.000Z'}),
        isTrue,
      );
    });

    test('a live, active video is not treated as deleted', () {
      expect(
        VideosService.isDeletedVideo({
          '_id': 'v',
          'status': 'active',
          'isDeleted': false,
          'deletedAt': null,
        }),
        isFalse,
      );
    });
  });
}
