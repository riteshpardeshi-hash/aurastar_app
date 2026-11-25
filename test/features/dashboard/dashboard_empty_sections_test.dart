import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';

// Found on device after blocking every creator and brand that had challenges: Home kept
// the "Brand Videos", "Trending videos" and "More Challenges" headings with nothing under
// them. Those sections now disappear when the challenge list loads empty.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  final requestedSourceTypes = <String?>[];

  void mockBackend(List<Map<String, dynamic>> challenges) {
    requestedSourceTypes.clear();
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
        // Brand Videos asks for brand challenges only (sourceType=Brand).
        final brandOnly = request.url.queryParameters['sourceType'] == 'Brand';
        final list = brandOnly
            ? challenges.where((c) => c['sourceType'] == 'Brand').toList()
            : challenges;
        requestedSourceTypes.add(request.url.queryParameters['sourceType']);
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'challenges': list}}),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  }

  Future<void> pumpHome(WidgetTester tester) async {
    // A tall screen so every Home section is built (slivers below the fold aren't).
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  const headings = ['Brand Videos', 'Trending videos', 'More Challenges'];

  testWidgets('no challenges: the challenge sections and their headings are gone', (tester) async {
    mockBackend([]);
    await pumpHome(tester);
    for (final h in headings) {
      expect(find.text(h), findsNothing, reason: '"$h" heading with nothing under it');
    }
  });

  // Client, 25 Nov 2026: Brand Videos shows only challenges brands posted, and no section
  // at all without any. It used to fill up with whatever challenges came first.
  testWidgets('challenges but none from a brand: no Brand Videos section', (tester) async {
    mockBackend([
      {'_id': 'c1', 'title': 'Dance Off', 'sourceType': 'Aura Original', 'starsCount': 12, 'submissionsCount': 3},
    ]);
    await pumpHome(tester);
    expect(find.text('Brand Videos'), findsNothing);
    expect(find.text('Trending videos'), findsOneWidget);
    expect(find.text('More Challenges'), findsOneWidget);
    expect(requestedSourceTypes, contains('Brand'));
  });

  testWidgets('with brand challenges: Brand Videos shows them, with the brand', (tester) async {
    mockBackend([
      {'_id': 'c1', 'title': 'Dance Off', 'sourceType': 'Aura Original', 'starsCount': 12, 'submissionsCount': 3},
      {
        '_id': 'b1',
        'title': 'Sip Challenge',
        'sourceType': 'Brand',
        'starsCount': 5,
        'submissionsCount': 1,
        'creatorId': {'_id': 'brand-1', 'displayName': 'Zesto', 'role': 'brand'},
      },
    ]);
    await pumpHome(tester);
    expect(find.text('Brand Videos'), findsOneWidget);
    expect(find.text('Z'), findsOneWidget); // the brand's badge (no logo uploaded → its initial)
  });
}
