import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/challenges/screens/all_general_challenges_screen.dart';

// Client, 25 Nov 2026: the challenges grid shows each challenge once (see also
// all_general_challenges_screen_test.dart). It used
// to wrap back to page 1 after the last page and scroll forever through the
// same challenges again.
Map<String, dynamic> _challenge(int i) => {
      '_id': 'c$i',
      'title': 'Challenge $i',
      'videoUrl': '',
      'starsCount': 5,
      'creatorId': 'system',
    };

void main() {
  final requestedPages = <String>[];

  setUp(() {
    requestedPages.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    ApiClient.httpClient = MockClient((request) async {
      if (!request.url.path.endsWith('/challenges')) {
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'categories': []}}), 200);
      }
      final page = request.url.queryParameters['page'] ?? '1';
      requestedPages.add(page);
      final list = switch (page) {
        '1' => [for (var i = 0; i < 20; i++) _challenge(i)],
        '2' => [_challenge(19), _challenge(20)], // c19 shifted onto page 2
        _ => <Map<String, dynamic>>[],
      };
      return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'challenges': list}
          }),
          200);
    });
  });

  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('scrolling to the end stops there: no starting over, no repeats',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AllGeneralChallengesScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(requestedPages.where((p) => p == '1'), hasLength(1));
    expect(requestedPages.where((p) => p == '2'), hasLength(1));
    // 21 distinct challenges: the one that shifted onto page 2 isn't doubled.
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect((grid.delegate as SliverChildBuilderDelegate).childCount, 21);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
