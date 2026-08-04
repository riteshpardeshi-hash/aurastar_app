import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/friends_service.dart';

// Endpoint-shape coverage for the new (previously fully unintegrated)
// Friends tag. Swagger only documents these as generic SuccessEnvelope/
// PaginatedResponse wrappers with no per-item schema, so the request paths/
// bodies and the defensive normaliseFriendUser() field-guessing are the
// parts most likely to silently drift from the live backend.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  test('fetchFriends hits GET /friends and unwraps data.responses', () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'responses': [
              {'_id': 'u1', 'displayName': 'Alex', 'username': 'alexr'},
            ],
          },
        }),
        200,
      );
    });

    final raw = await FriendsService().fetchFriends();

    expect(requestedPath!.endsWith('/friends'), isTrue,
        reason: 'expected GET /friends, got $requestedPath');
    final entry = normaliseFriendUser(raw.single);
    expect(entry['id'], 'u1');
    expect(entry['name'], 'Alex');
    expect(entry['username'], 'alexr');
  });

  test('sendRequest POSTs receiverId to /friends/request', () async {
    String? requestedPath;
    Map<String, dynamic>? requestedBody;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'status': 'success'}), 201);
    });

    final result = await FriendsService().sendRequest('u2');

    expect(requestedPath!.endsWith('/friends/request'), isTrue,
        reason: 'expected POST /friends/request, got $requestedPath');
    expect(requestedBody?['receiverId'], 'u2');
    expect(result, isTrue);
  });

  test('respondToRequest PATCHes action=accept to /friends/request/{id}',
      () async {
    String? requestedPath;
    Map<String, dynamic>? requestedBody;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result =
        await FriendsService().respondToRequest('req-1', accept: true);

    expect(requestedPath!.endsWith('/friends/request/req-1'), isTrue,
        reason: 'expected PATCH /friends/request/req-1, got $requestedPath');
    expect(requestedBody?['action'], 'accept');
    expect(result, isTrue);
  });

  test('removeFriend DELETEs /friends/{friendId}', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await FriendsService().removeFriend('u3');

    expect(requestedMethod, 'DELETE');
    expect(requestedPath!.endsWith('/friends/u3'), isTrue,
        reason: 'expected DELETE /friends/u3, got $requestedPath');
    expect(result, isTrue);
  });

  test('normaliseFriendUser falls back across sender/requester/friend/flat shapes',
      () {
    expect(
      normaliseFriendUser({
        'requestId': 'req-9',
        'sender': {'_id': 'u9', 'name': 'Sam', 'username': 'sam9'},
      })['name'],
      'Sam',
    );
    expect(
      normaliseFriendUser({'id': 'u10', 'profileName': 'flatuser'})['username'],
      'flatuser',
    );
  });
}
