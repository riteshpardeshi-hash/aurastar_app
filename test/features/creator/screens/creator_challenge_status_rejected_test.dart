import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/creator_challenge_status_screen.dart';

// Regression: a REJECTED challenge fell through to `default: return []`, so
// the creator had no way to fix it and send it back. After a rejection the
// creator edits the challenge and resubmits it for review, exactly as after
// changes were requested (the backend allows both — PUT and /resubmit).
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/creator/challenges/ch-1')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenge': {
                '_id': 'ch-1',
                'title': 'Rejected Plank',
                'description': 'Hold a plank.',
                'difficulty': 'Easy',
                'submissionStatus': 'REJECTED',
                'adminFeedback': 'Video too dark',
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  testWidgets('a rejected challenge offers Edit and Resubmit for Review',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        const MaterialApp(home: CreatorChallengeStatusScreen(challengeId: 'ch-1')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Rejected Plank'), findsWidgets);
    expect(find.text('Resubmit for Review'), findsOneWidget);
    expect(find.text('Edit Draft'), findsOneWidget);
  });
}
