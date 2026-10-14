import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/leaderboard_consent_service.dart';
import 'package:aura_app/features/account/widgets/leaderboard_consent_tile.dart';

// Apple 5.1.2 (backend ADR 129): Settings → "Show me on leaderboards" reflects the
// stored consent and lets the user withdraw (or give) it at any time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> puts;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    LeaderboardConsentService.instance.reset();
    puts = [];
    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        puts.add(body);
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'leaderboardConsent': {
                'status': body['granted'] == true ? 'granted' : 'declined',
              },
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'user': {
              'id': 'user-1',
              'leaderboardConsent': {'status': 'granted'},
            },
          },
        }),
        200,
      );
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    LeaderboardConsentService.instance.reset();
  });

  testWidgets('shows the stored choice and turning it off withdraws consent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LeaderboardConsentTile())),
    );
    await tester.pumpAndSettle();

    SwitchListTile tile() => tester.widget<SwitchListTile>(
      find.byKey(const Key('leaderboard-consent-switch')),
    );
    expect(tile().value, isTrue);

    await tester.tap(find.byKey(const Key('leaderboard-consent-switch')));
    await tester.pumpAndSettle();

    expect(puts, [
      {'granted': false},
    ]);
    expect(tile().value, isFalse);
    expect(
      find.text("You've been removed from public leaderboards."),
      findsOneWidget,
    );
  });
}
