import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/videos_service.dart';
import 'package:aura_app/core/utils/asset_cache_key.dart';
import 'package:aura_app/features/account/screens/all_videos_screen.dart';

// Regression coverage: GET /profile/videos now returns a working
// `thumbnailUrl` (confirmed live by the backend team, 2026-08-14), but
// AllVideosScreen's _normaliseSubmission dropped that field on the floor —
// it was never read out of the raw response, so VideoThumbnailWidget was
// always constructed with only `videoUrl` and no `thumbnailUrl`. Since
// submission videoUrls are HLS (.m3u8) manifests, VideoThumbnailWidget's
// frame-extraction path short-circuits for those (video_thumbnail can't
// decode a manifest) straight to its purple fallback icon — which is
// exactly what showed up in the "My Videos" grid even after the backend
// fix, because the client never forwarded the thumbnail it was given.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const thumbnailUrl =
      'https://womaty-output-bucket.s3.us-east-1.amazonaws.com/processed/submission/2026/08/05/uid/vid/vidthumbnail.0000000.jpg';
  const videoUrl =
      'https://womaty-output-bucket.s3.us-east-1.amazonaws.com/processed/submission/2026/08/05/uid/vid/hls/vid.m3u8';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
    VideosService.resetLocallyDeletedForTest();

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/profile/videos')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'page': 1,
              'totalCount': 1,
              'totalPages': 1,
              'limit': 100,
              'responses': [
                {
                  '_id': 'video-1',
                  'videoUrl': videoUrl,
                  'thumbnailUrl': thumbnailUrl,
                  'processingStatus': 'completed',
                  'submission': {
                    'status': 'scored',
                    'aiScore': 43,
                    'verdict': 'WEAK',
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      return http.Response('', 500);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'a video with a backend thumbnailUrl renders it instead of falling '
      'back to the placeholder icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AllVideosScreen()));

    // Let _load()'s GET resolve and setState apply.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byWidgetPredicate((w) =>
          w is CachedNetworkImage &&
          w.imageUrl == thumbnailUrl &&
          // Cache is keyed on the unsigned URL so a re-signed variant is a
          // hit, not a re-download (ADR 014).
          w.cacheKey == assetCacheKey(thumbnailUrl)),
      findsOneWidget,
      reason: 'thumbnailUrl from GET /profile/videos must reach '
          'VideoThumbnailWidget so it can render the real thumbnail via '
          'CachedNetworkImage instead of extracting a frame from the (HLS, '
          'unextractable) videoUrl. (Whether that image request actually '
          'succeeds is irrelevant here and untestable in `flutter test` — '
          'it blocks all real dart:io HttpClient traffic — the fix is about '
          'the thumbnailUrl being wired through at all.)',
    );
  });
}
