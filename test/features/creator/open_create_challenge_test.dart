import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/category_store.dart';
import 'package:aura_app/features/creator/open_create_challenge.dart';
import 'package:aura_app/features/creator/screens/create_challenge.dart';
import 'package:aura_app/features/creator/screens/creator_activity_screen.dart';
import 'package:aura_app/features/creator/screens/creator_challenge_draft_screen.dart';
import 'package:aura_app/features/creator/screens/creator_challenges_screen.dart';

// "Create challenge" (Creator Activity) and "My Challenges → New" used to open two
// different screens: the old record flow without scoring criteria, and the draft page.
// Both must now open the same page for a creator.
void main() {
  setUp(() {
    CategoryStore.instance.resetForTest();
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'creator-1',
    });
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  void backendAs(String role) {
    ApiClient.httpClient = MockClient((req) async {
      final path = req.url.path;
      Map<String, dynamic> data = {};
      if (path.endsWith('/profile')) {
        data = {'user': {'_id': 'creator-1', 'role': role}};
      } else if (path.endsWith('/categories')) {
        data = {'categories': []};
      } else if (path.endsWith('/creator/challenges/submissions')) {
        data = {'responses': [], 'totalCount': 0};
      }
      return http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapOpen(WidgetTester tester, {Future<String?> Function()? loadRole}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openCreateChallenge(context, loadRole: loadRole),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('a creator gets the create page with scoring criteria', (tester) async {
    backendAs('creator');
    await tapOpen(tester, loadRole: () async => 'creator');
    expect(find.byType(CreatorChallengeDraftScreen), findsOneWidget);
    expect(find.byType(CreateChallenge), findsNothing);
  });

  testWidgets('an unknown role (profile failed to load) still gets the creator page', (tester) async {
    backendAs('creator');
    await tapOpen(tester, loadRole: () async => null);
    expect(find.byType(CreatorChallengeDraftScreen), findsOneWidget);
  });

  for (final role in ['brand', 'admin', 'super_admin']) {
    testWidgets('a $role gets the record flow (creator endpoints reject that role)', (tester) async {
      backendAs(role);
      await tapOpen(tester, loadRole: () async => role);
      expect(find.byType(CreateChallenge), findsOneWidget);
      expect(find.byType(CreatorChallengeDraftScreen), findsNothing);
    });
  }

  testWidgets('Creator Activity → Create challenge opens the same page as My Challenges → New',
      (tester) async {
    backendAs('creator');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: CreatorActivityScreen()));
    await tester.pump();
    await tester.tap(find.text('Create challenge'));
    await settle(tester);
    expect(find.byType(CreatorChallengeDraftScreen), findsOneWidget);

    // Fresh tree, so the page pushed above doesn't carry over.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: CreatorChallengesScreen()));
    await settle(tester);
    await tester.tap(find.text('New Challenge'));
    await settle(tester);
    expect(find.byType(CreatorChallengeDraftScreen), findsOneWidget);
  });
}
