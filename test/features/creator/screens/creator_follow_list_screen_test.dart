import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creator_account_service.dart';
import 'package:aura_app/features/creator/screens/creator_follow_list_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 't',
      'api_refresh_token': 'r',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() => ApiClient.httpClient = http.Client());

  // Regression: a failed /creator/followers request was swallowed into an
  // empty list, so the screen said "No followers yet" next to a profile that
  // showed 2 followers.
  testWidgets('a failed followers request shows an error + Retry, not '
      '"No followers yet"', (tester) async {
    ApiClient.httpClient = MockClient((request) async => http.Response(
        jsonEncode({
          'status': 'fail',
          'message': 'Access denied. Requires one of: creator',
        }),
        403));

    await tester.pumpWidget(const MaterialApp(
        home: CreatorFollowListScreen(mode: FollowListMode.followers)));
    await tester.pump();
    await tester.pump();

    expect(find.text('No followers yet'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  // Regression: rows wrapped in `responses` (the backend's usual list shape)
  // instead of the spec's `data` were read as an empty list.
  test('follow entries are found under any known list wrapper', () {
    final row = {'followerId': 'a'};
    for (final data in [
      {'data': [row]},
      {'responses': [row]},
      {'followers': [row]},
      [row],
    ]) {
      expect(CreatorAccountService.extractFollowEntries(data), [row]);
    }
    expect(CreatorAccountService.extractFollowEntries({'pagination': {}}), isEmpty);
  });

  // The profile said "2 followers" while the list said "No followers yet".
  testWidgets('an empty list under a non-zero header count says it could not '
      'load, instead of claiming none', (tester) async {
    ApiClient.httpClient = MockClient((request) async => http.Response(
        jsonEncode({'status': 'success', 'data': {'pagination': {'total': 0}}}),
        200));

    await tester.pumpWidget(const MaterialApp(
        home: CreatorFollowListScreen(
            mode: FollowListMode.followers, expectedCount: 2)));
    await tester.pump();
    await tester.pump();

    expect(find.text('No followers yet'), findsNothing);
    expect(find.textContaining('shows 2'), findsOneWidget);
    expect(find.textContaining('keys: pagination'), findsOneWidget);
  });
}
