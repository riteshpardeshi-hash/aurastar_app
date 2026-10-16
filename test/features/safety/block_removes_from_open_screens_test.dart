import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/safety_service.dart';
import 'package:aura_app/features/search/search_screen.dart';

// Apple guideline 1.2 — blocking someone must remove their content at once. Screens that
// stay mounted (the shell's tabs, open search results) used to keep showing a blocked
// account until a manual refresh. They now reload on SafetyService.changes.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({
        'api_access_token': 't',
        'api_refresh_token': 'r',
        'api_user_id': 'me',
      }));
  tearDown(() => ApiClient.httpClient = http.Client());

  testWidgets('open search results drop an account as soon as it is blocked', (tester) async {
    var blocked = false;
    var searches = 0;
    ApiClient.httpClient = MockClient((r) async {
      final ok = (Object data) => http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
      if (r.url.path.endsWith('/search/recent')) return ok({'items': []});
      if (r.url.path.endsWith('/search')) {
        searches++;
        return ok({
          'docs': [
            if (!blocked) {'_id': 'u9', 'displayName': 'Riya', 'username': 'riya', 'avatar': ''},
          ],
          'pagination': {'page': 1, 'pages': 1, 'total': blocked ? 0 : 1, 'limit': 20},
        });
      }
      if (r.method == 'POST' && r.url.path.endsWith('/users/u9/block')) {
        blocked = true;
        return ok({'blocked': true});
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.tap(find.text('Creators'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'riya');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Riya'), findsOneWidget);
    final before = searches;

    // Blocked from somewhere else (e.g. their profile, pushed over these results).
    await tester.runAsync(() => SafetyService().block('u9'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(searches, before + 1);
    expect(find.text('Riya'), findsNothing);
  });
}
