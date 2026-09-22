import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/account/screens/my_account_screen.dart';

// Regression coverage: the level badge on the profile screen used to be a
// plain static circle with no indication of progress toward the next level.
// GET /profile now returns a server-computed `levelProgress` object (backend
// ADR: "Video Delete..." — see profile.controller.js#getProfile); the badge's
// own circular edge should render that progress, and a caption should say
// exactly how many Aura points remain.
void main() {
  Future<void> pumpWithProfile(
    WidgetTester tester,
    Map<String, dynamic>? levelProgress,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'user-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/profile')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'user': {
                '_id': 'user-1',
                'displayName': 'Test User',
                'auraPoints': 727,
                'level': 7,
                'tier': 'rookie',
                if (levelProgress != null) 'levelProgress': levelProgress,
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: MyAccountScreen()));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('shows a determinate progress ring and the Aura remaining, from the server-computed levelProgress',
      (tester) async {
    await pumpWithProfile(tester, {
      'level': 7,
      'auraIntoLevel': 27,
      'auraToNextLevel': 73,
      'pct': 0.27,
    });

    expect(tester.takeException(), isNull);

    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('levelProgressRing')),
    );
    expect(ring.value, 0.27,
        reason: 'the badge circle\'s own edge must reflect the server pct, '
            'not an indeterminate spinner');

    expect(find.text('73 Aura to Level 8'), findsOneWidget);
  });

  testWidgets('shows an empty ring and no caption when levelProgress is absent (older cached profile)',
      (tester) async {
    await pumpWithProfile(tester, null);

    expect(tester.takeException(), isNull);

    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const Key('levelProgressRing')),
    );
    expect(ring.value, 0.0,
        reason: 'missing levelProgress must fall back to an empty ring, '
            'never a guessed value');

    expect(find.textContaining('Aura to Level'), findsNothing);
  });

  testWidgets('shows "Ready to level up!" when auraToNextLevel is 0',
      (tester) async {
    await pumpWithProfile(tester, {
      'level': 7,
      'auraIntoLevel': 100,
      'auraToNextLevel': 0,
      'pct': 1.0,
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Ready to level up!'), findsOneWidget);
  });
}
