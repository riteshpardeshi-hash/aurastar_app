import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';

// Client, 25 Nov 2026: Home shows "Top Creators", the creators with the most followers
// (the backend ranks them, ADR 149), and always exactly 4, whatever the screen width.
void main() {
  String? requestedLimit;

  setUp(() {
    requestedLimit = null;
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
      if (path.endsWith('/home/trending-creators')) {
        requestedLimit = request.url.queryParameters['limit'];
        // Already ranked by the backend; one more than fits, to check only 4 show.
        final creators = [
          for (final (i, f) in [(1, 2400), (2, 312), (3, 40), (4, 1), (5, 0)].indexed)
            {'_id': 'cr${f.$1}', 'displayName': 'Creator ${f.$1}', 'avatar': '', 'followersCount': f.$2, 'n': i},
        ];
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'creators': creators}}), 200);
      }
      if (path.endsWith('/challenges')) {
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'challenges': []}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  Future<void> pumpHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Dashboard()));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  // (Headings use the test font's wide block glyphs, so a narrow test screen overflows the
  // section titles; the phone check covers narrow screens.)
  for (final size in const [Size(1080, 8000), Size(1440, 8000)]) {
    testWidgets('Top Creators: exactly 4, in the ranked order, with followers (width ${size.width})',
        (tester) async {
      await pumpHome(tester, size);
      expect(find.text('Top Creators'), findsOneWidget);
      expect(find.text('Creator Profiles'), findsNothing);
      expect(requestedLimit, '4');
      for (final n in [1, 2, 3, 4]) {
        expect(find.byKey(Key('top-creator-cr$n')), findsOneWidget);
      }
      expect(find.byKey(const Key('top-creator-cr5')), findsNothing);
      // Left to right in the backend's order.
      final xs = [for (final n in [1, 2, 3, 4]) tester.getCenter(find.byKey(Key('top-creator-cr$n'))).dx];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(find.text('2.4K followers'), findsOneWidget);
      expect(find.text('1 follower'), findsOneWidget);
    });
  }
}
