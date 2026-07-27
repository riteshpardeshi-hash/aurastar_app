import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/challenges/screens/category_challenges_screen.dart';

// Regression coverage: GET /challenges' `category` filter is the category's
// ObjectId, not its display name — confirmed against the live backend,
// which rejects a name with a 400 ("Category ID must be a valid 24-character
// ID"). CategoryChallengesScreen (and every screen that navigates into it)
// used to pass the bare display name, so tapping into any real category
// (e.g. "Freestyle Football") always landed on the "No challenges yet"
// empty state, even when real challenges existed for it.
//
// The header's fixed 6-category icon lookup (Dance/Fitness/Fashion/Sports/
// Comedy/Skill) also never matched any of the real backend's 9 categories,
// so it always showed the same generic fallback icon — removed per explicit
// user request rather than reconciled against the real category list.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets(
      'fetches challenges using the category id, not its display name',
      (tester) async {
    String? capturedCategoryParam;

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/challenges')) {
        capturedCategoryParam = request.url.queryParameters['category'];
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenges': [
                {
                  '_id': 'challenge-1',
                  'title': 'Freestyle Trick Shot',
                  'videoUrl': '',
                  'starsCount': 5,
                  'creatorId': 'system',
                },
              ],
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(
      home: CategoryChallengesScreen(
        categoryId: '6a3b7c6f443e944c5ea60370',
        categoryName: 'Freestyle Football',
      ),
    ));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(capturedCategoryParam, '6a3b7c6f443e944c5ea60370',
        reason: 'must send the category ObjectId, not the display name '
            '"Freestyle Football"');
    expect(find.text('Freestyle Trick Shot'), findsOneWidget,
        reason: 'a real challenge for this category must render, not the '
            'empty state');
    expect(find.textContaining('No Freestyle Football challenges'),
        findsNothing);

    // The header no longer shows a category icon at all (removed per user
    // request) — in particular the old generic fallback glyph, which used
    // to render for every real category since none matched the hardcoded
    // 6-category icon map.
    expect(find.byIcon(Icons.category_outlined), findsNothing);
  });
}
