import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/category_store.dart';
import 'package:aura_app/features/creator/screens/creator_challenge_draft_screen.dart';
import 'package:aura_app/features/creator/screens/creator_challenges_screen.dart';

// Regression (2026-10-15): after creating a challenge, My Challenges reloaded the list but not
// the status-chip counts — device QA showed "Draft (2)" above four drafts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CategoryStore.instance.resetForTest();
    // Categories are saved on the device now (CategoryStore).
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'creator-token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('creating a challenge refreshes the status chip counts, not just the list', (tester) async {
    var drafts = 2;
    ApiClient.httpClient = MockClient((req) async {
      final path = req.url.path;
      Map<String, dynamic> data;
      if (path.endsWith('/creator/challenges/status-summary')) {
        data = {'total': drafts, 'byStatus': {'DRAFT': drafts}};
      } else if (path.endsWith('/creator/challenges/submissions')) {
        data = {
          'challenges': [
            for (var i = 0; i < drafts; i++) {'_id': 'c$i', 'title': 'Draft $i', 'submissionStatus': 'DRAFT'},
          ],
        };
      } else if (path.endsWith('/categories')) {
        data = {'categories': <dynamic>[]};
      } else {
        data = {};
      }
      return http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
    });

    await tester.pumpWidget(const MaterialApp(home: CreatorChallengesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Draft (2)'), findsOneWidget);

    await tester.tap(find.text('New Challenge'));
    await tester.pumpAndSettle();
    drafts = 3; // the draft screen created one
    Navigator.of(tester.element(find.byType(CreatorChallengeDraftScreen))).pop(true);
    await tester.pumpAndSettle();

    expect(find.text('Draft (3)'), findsOneWidget);
    expect(find.text('All (3)'), findsOneWidget);
  });
}
