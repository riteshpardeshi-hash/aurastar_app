import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/models/creator_rubric.dart';
import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creator_challenges_service.dart';

// Scoring criteria client (backend ADR 137). Generating is an AI call on the reference
// video (25–90 s in production), and submit / resubmit / publish can run the same call
// when the challenge has no criteria yet — none of them may give up at the 15 s default.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'creator-token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });
  tearDown(() => ApiClient.httpClient = http.Client());

  Map<String, dynamic> view({bool has = true}) => {
        'status': 'success',
        'data': {
          'hasRubric': has,
          'editable': true,
          'source': 'ai',
          'categories': has
              ? [
                  {'key': 'landing', 'name': 'Landing', 'maxPoints': 15},
                ]
              : [],
        },
      };

  test('generate posts the notes to the generate endpoint', () async {
    late http.Request sent;
    ApiClient.httpClient = MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode(view()), 200);
    });

    final rubric = await CreatorChallengesService().generateRubric('c1', notes: '  stricter landing ');

    expect(sent.method, 'POST');
    expect(sent.url.path, endsWith('/creator/challenges/c1/rubric/generate'));
    expect(jsonDecode(sent.body), {'notes': 'stricter landing'});
    expect(rubric.categories.single.name, 'Landing');
  });

  test('update PUTs the edited categories', () async {
    late http.Request sent;
    ApiClient.httpClient = MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode(view()), 200);
    });

    await CreatorChallengesService().updateRubric('c1', const [
      RubricCategory(key: 'landing', name: 'Landing', description: 'Feet together', maxPoints: 15),
      RubricCategory(name: 'Arms', maxPoints: 14),
    ]);

    expect(sent.method, 'PUT');
    expect(sent.url.path, endsWith('/creator/challenges/c1/rubric'));
    expect(jsonDecode(sent.body), {
      'categories': [
        {'key': 'landing', 'name': 'Landing', 'description': 'Feet together', 'maxPoints': 15},
        {'name': 'Arms', 'maxPoints': 14},
      ],
    });
  });

  test("a failed save surfaces the backend's message", () async {
    ApiClient.httpClient = MockClient((_) async => http.Response(
        jsonEncode({'status': 'fail', 'message': 'Your categories add up to 80 points'}), 400));
    expect(
      CreatorChallengesService().updateRubric('c1', const []),
      throwsA('Your categories add up to 80 points'),
    );
  });

  Future<Object?> slowCall(WidgetTester tester, Future<Object?> Function() call) async {
    ApiClient.httpClient = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 40));
      return http.Response(
          jsonEncode({'status': 'success', 'data': view()['data']..['status'] = 'PENDING_REVIEW'}), 200);
    });
    Object? error;
    call().catchError((Object e) {
      error = e;
      return null;
    });
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    return error;
  }

  testWidgets('generate waits for a 40 s AI call', (tester) async {
    expect(await slowCall(tester, () => CreatorChallengesService().generateRubric('c1')), isNull);
  });

  testWidgets('submit waits for a 40 s AI call (criteria generated on submit)', (tester) async {
    expect(await slowCall(tester, () => CreatorChallengesService().submit('c1')), isNull);
  });

  testWidgets('resubmit waits for a 40 s AI call', (tester) async {
    expect(await slowCall(tester, () => CreatorChallengesService().resubmit('c1')), isNull);
  });

  testWidgets('publish waits for a 40 s AI call', (tester) async {
    expect(await slowCall(tester, () => CreatorChallengesService().publish('c1')), isNull);
  });
}
