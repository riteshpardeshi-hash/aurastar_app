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

  void mockBackend(List<Map<String, dynamic>> challenges) {
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
        return http.Response(
          jsonEncode({'status': 'success', 'data': {'challenges': challenges}}),
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

  testWidgets('with challenges: the sections show', (tester) async {
    mockBackend([
      {'_id': 'c1', 'title': 'Dance Off', 'starsCount': 12, 'submissionsCount': 3},
    ]);
    await pumpHome(tester);
    expect(find.text('Brand Videos'), findsOneWidget);
    expect(find.text('Trending videos'), findsOneWidget);
    expect(find.text('More Challenges'), findsOneWidget);
  });
}
