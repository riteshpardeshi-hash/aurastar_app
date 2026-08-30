import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/challenges/screens/all_general_challenges_screen.dart';

// Regression coverage for endless scroll: the Challenges tab used to fetch a
// single fixed page (limit: 20) of /challenges and never request more, so a
// user scrolling past the first 20 challenges just hit the end of the grid
// even when the backend had more. Now the grid listens for the scroll
// position nearing the bottom and fetches the next `page`, appending to what
// was already shown — and once the backend itself runs out of pages, it
// wraps back around to page 1 instead of stopping, so the grid never
// dead-ends.
Map<String, dynamic> _challenge(String id, {String? createdAt}) => {
      '_id': id,
      'title': 'Challenge $id',
      'videoUrl': '',
      'starsCount': 1,
      'creatorId': 'system',
      if (createdAt != null) 'createdAt': createdAt,
    };

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

  testWidgets('scrolling near the bottom fetches and appends the next page',
      (tester) async {
    final capturedPages = <String?>[];

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/challenges')) {
        final page = request.url.queryParameters['page'];
        capturedPages.add(page);
        // Page 1 returns a full page (20) so `_hasMore` stays true; page 2
        // returns fewer than the page size, signalling the real end.
        final items = page == '2'
            ? [_challenge('p2-1')]
            : List.generate(20, (i) => _challenge('p1-$i'));
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'challenges': items},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/categories')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'categories': []},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(
      home: AllGeneralChallengesScreen(),
    ));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(capturedPages, ['1'],
        reason: 'only the first page should load up front');

    // Drag the scrollable to its end to trigger the near-bottom load-more.
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, -20000), 3000);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(capturedPages, contains('2'),
        reason:
            'scrolling to the bottom must request page 2 instead of stopping '
            'at the first 20 challenges');

    // Page 2 is the backend's real last page (fewer than `limit` items), so
    // once it's been consumed the grid should keep going by wrapping back
    // to page 1 instead of dead-ending — that's what makes the scroll
    // endless rather than stopping once every challenge has been seen.
    final afterLastPage =
        capturedPages.sublist(capturedPages.indexOf('2') + 1);
    expect(afterLastPage, contains('1'),
        reason:
            'once the backend runs out of pages, the grid must loop back to '
            'page 1 instead of the scroll simply ending');
  });
}
