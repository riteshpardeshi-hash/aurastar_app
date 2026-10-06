import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/account/screens/all_videos_screen.dart';

// Regression coverage: the profile grid (my_account_screen.dart) labels an
// 'ai_error' submission (AI scoring failed, waiting on manual admin review)
// "Review", but this screen labelled the same video "Error" — two different
// words for one state, and "Error" reads like the app broke.
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
                  'submission': {'status': 'failed'},
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
    'an ai_error video is labelled "Review", matching the profile grid',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AllVideosScreen()));
      // Let _load()'s GET resolve and setState apply (the thumbnail keeps
      // animating, so pumpAndSettle would never settle).
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
    },
  );
}
