import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creator_challenges_service.dart';

// Regression coverage: pickString (used across notifications_service.dart
// and several creator screens to read fields from Swagger-undocumented,
// best-guess responses) used to delegate to pickField, which only checks
// "present and non-null" — so a present-but-empty string candidate (e.g. a
// notification with body: '') was returned as-is, never falling through to
// a later, populated candidate like title. A notification with a real title
// but an empty body rendered as a blank row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fetchMyChallenges', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        'api_access_token': 'token',
        'api_refresh_token': 'refresh',
        'api_user_id': 'user-1',
      });
    });
    tearDown(() => ApiClient.httpClient = http.Client());

    // Regression: the filter was sent as `submissionStatus`, but the spec
    // names it `status`, so the "In Review (1)" tab listed nothing.
    test("sends the status filter as the spec's `status` query param", () async {
      Uri? url;
      ApiClient.httpClient = MockClient((request) async {
        url = request.url;
        return http.Response(
            jsonEncode({'status': 'success', 'data': {'responses': []}}), 200);
      });

      await CreatorChallengesService()
          .fetchMyChallenges(submissionStatus: 'PENDING_REVIEW');

      expect(url!.queryParameters['status'], 'PENDING_REVIEW');
      expect(url!.queryParameters.containsKey('submissionStatus'), isFalse);
    });

    // Regression: failures used to become [], shown as "No challenges yet".
    test('throws on a failed response instead of returning an empty list',
        () async {
      ApiClient.httpClient = MockClient((_) async => http.Response(
          jsonEncode({'status': 'error', 'message': 'boom'}), 500));

      expect(CreatorChallengesService().fetchMyChallenges(), throwsException);
    });
  });

  group('pickString', () {
    test('falls through a present-but-empty candidate to a later populated one', () {
      expect(
        pickString({'body': '', 'title': 'Real title'}, ['body', 'title']),
        'Real title',
      );
    });

    test('returns the first non-empty candidate found', () {
      expect(
        pickString({'message': 'Hi', 'body': '', 'title': 'Ignored'},
            ['message', 'body', 'text', 'title']),
        'Hi',
      );
    });

    test('falls back when every candidate is missing or empty', () {
      expect(
        pickString({'body': ''}, ['message', 'body', 'text', 'title'],
            fallback: 'default'),
        'default',
      );
    });

    test('a missing map key is skipped same as an empty one', () {
      expect(
        pickString({'title': 'Only title'}, ['message', 'body', 'title']),
        'Only title',
      );
    });
  });
}
