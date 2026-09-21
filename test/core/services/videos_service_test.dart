import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/videos_service.dart';

// VideosService used to carry two client-side workarounds for backend gaps:
// - docs/backend-issues/002-profile-videos-returns-soft-deleted-videos.md —
//   GET /profile/videos kept listing a video after DELETE /videos/{id}
//   soft-deleted it, so the client tracked deleted ids itself and filtered
//   them out.
// - docs/backend-issues/003-video-delete-does-not-reverse-aura-points.md —
//   the backend didn't debit Aura on delete, so the client kept a local
//   running offset and subtracted it from every displayed balance.
// Both are now resolved server-side (see backend ADR 098's companion fix and
// video.service.js#deleteVideo's aura-reversal cascade), so both workarounds
// — and their tests — were removed per each doc's own "delete this once the
// backend ships" instruction / ADR 008. `deleteVideo` is left with exactly
// one remaining responsibility: call the endpoint, and treat a 404 (the
// video is already gone server-side) as an already-satisfied delete rather
// than an error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  test('a successful delete completes without throwing', () async {
    ApiClient.httpClient = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, endsWith('/videos/vid-1'));
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    await VideosService().deleteVideo('vid-1');
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
  });
}
