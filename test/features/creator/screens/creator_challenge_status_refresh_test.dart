import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/features/creator/screens/creator_challenge_status_screen.dart';

// Regression: the review happens in the admin panel, so this screen's status
// went stale — it kept showing "In Review" after the admin approved, until the
// creator closed and reopened it. It now re-fetches on app resume and on
// pull-to-refresh, so "Publish Challenge" shows up without leaving the screen.
void main() {
  late String serverStatus;

  setUp(() {
    serverStatus = 'PENDING_REVIEW';
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'test-access-token',
      'api_refresh_token': 'test-refresh-token',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});

    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/creator/challenges/ch-1')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'challenge': {
                '_id': 'ch-1',
                'title': 'Plank',
                'description': 'Hold a plank.',
                'difficulty': 'Easy',
                'submissionStatus': serverStatus,
                if (serverStatus == 'APPROVED') 'auraScore': 50,
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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: CreatorChallengeStatusScreen(challengeId: 'ch-1')));
    await settle(tester);
    expect(find.text('Cancel Submission'), findsOneWidget);
    expect(find.text('Publish Challenge'), findsNothing);
  }

  testWidgets('returning to the app picks up the admin approval', (tester) async {
    await open(tester);

    serverStatus = 'APPROVED';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('Publish Challenge'), findsOneWidget);
  });

  testWidgets('pull-to-refresh picks up the admin approval', (tester) async {
    await open(tester);

    serverStatus = 'APPROVED';
    await tester.fling(find.byType(SingleChildScrollView).first,
        const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Publish Challenge'), findsOneWidget);
  });
}
