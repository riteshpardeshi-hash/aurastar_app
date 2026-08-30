import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
