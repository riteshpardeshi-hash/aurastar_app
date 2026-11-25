import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';

// Client, 25 Nov 2026: Home's "More Challenges" grid showed the first 20
// challenges repeated up to 9000 tiles, an endless loop of the same videos.
// It now shows every challenge once (loading the next page near the bottom)
// and ends with "You've seen all the challenges".
Map<String, dynamic> _challenge(int i) =>
    {'_id': 'c$i', 'title': 'Challenge $i', 'starsCount': 5, 'submissionsCount': 0};

void main() {
  final requestedPages = <String>[];

  setUp(() {
    requestedPages.clear();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1', 'displayName': 'QA', 'avatar': '', 'auraPoints': 0,
                'level': 1, 'tier': 'rookie', 'isProfileComplete': true,
              },
            },
          }),
          200,
        );
      }
      if (path.endsWith('/challenges')) {
        final page = request.url.queryParameters['page'] ?? '1';
        requestedPages.add(page);
        final list = switch (page) {
          '1' => [for (var i = 0; i < 20; i++) _challenge(i)],
          '2' => [_challenge(18), _challenge(19), _challenge(20)], // two shifted
          _ => <Map<String, dynamic>>[],
        };
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'challenges': list}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('More Challenges shows each challenge once, then ends', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    for (var i = 0; i < 25; i++) {
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -1500));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    // 21 distinct challenges: c18/c19 (shifted onto page 2) aren't doubled.
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid).last);
    expect((grid.delegate as SliverChildBuilderDelegate).childCount, 21);
    expect(find.byKey(const Key('home-challenges-end')), findsOneWidget);
    // Page 1 once (no starting over), and nothing asked for past the end.
    expect(requestedPages.where((p) => p == '1'), hasLength(1));
    expect(requestedPages.where((p) => p == '3'), isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
