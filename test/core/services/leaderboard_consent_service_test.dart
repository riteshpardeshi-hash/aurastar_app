import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/leaderboard_consent_service.dart';

// Apple 5.1.2 (backend ADR 129): an account whose GET /profile says
// `leaderboardConsent.status: null` is asked once — Agree / Not now — and the
// answer is saved with PUT /profile/leaderboard-consent. Anyone who already
// answered, or an older backend with no `leaderboardConsent` key, is never asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> puts;

  void mockBackend(Object? consent, {bool includeKey = true}) {
    puts = [];
    ApiClient.httpClient = MockClient((request) async {
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/profile/leaderboard-consent')) {
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
              if (includeKey) 'leaderboardConsent': consent,
            },
          },
        }),
        200,
      );
    });
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
    LeaderboardConsentService.instance.reset();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    LeaderboardConsentService.instance.reset();
  });

  Future<void> pumpAsker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => LeaderboardConsentService.instance.askIfNeeded(
                        context,
                      ),
                  child: const Text('ask'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('an unanswered account is asked, and Agree saves granted', (
    tester,
  ) async {
    mockBackend({'status': null});
    await pumpAsker(tester);

    expect(find.byKey(const Key('leaderboard-consent-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('leaderboard-consent-agree')));
    await tester.pumpAndSettle();

    expect(puts, [
      {'granted': true},
    ]);
    expect(LeaderboardConsentService.instance.status.value, 'granted');
    expect(find.byKey(const Key('leaderboard-consent-dialog')), findsNothing);
  });

  testWidgets('Not now saves declined', (tester) async {
    mockBackend({'status': null});
    await pumpAsker(tester);

    await tester.tap(find.byKey(const Key('leaderboard-consent-not-now')));
    await tester.pumpAndSettle();

    expect(puts, [
      {'granted': false},
    ]);
    expect(LeaderboardConsentService.instance.status.value, 'declined');
  });

  testWidgets('the dialog cannot be dismissed by tapping outside it', (
    tester,
  ) async {
    mockBackend({'status': null});
    await pumpAsker(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leaderboard-consent-dialog')), findsOneWidget);
    expect(puts, isEmpty);
  });

  testWidgets('an account that already answered is never asked', (
    tester,
  ) async {
    mockBackend({'status': 'declined'});
    await pumpAsker(tester);

    expect(find.byKey(const Key('leaderboard-consent-dialog')), findsNothing);
    expect(puts, isEmpty);
  });

  testWidgets('an older backend without the field never prompts', (
    tester,
  ) async {
    mockBackend(null, includeKey: false);
    await pumpAsker(tester);

    expect(find.byKey(const Key('leaderboard-consent-dialog')), findsNothing);
    expect(LeaderboardConsentService.instance.known, isFalse);
  });
}
