import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/creators_service.dart';

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

  test('fetchCreator hits GET /creators/{id} and unwraps the creator map',
      () async {
    String? requestedPath;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'creator': {'_id': 'c1', 'displayName': 'Riya', 'username': 'riya'},
            'isFollowing': false,
          },
        }),
        200,
      );
    });

    final raw = await CreatorsService().fetchCreator('c1');

    expect(requestedPath!.endsWith('/creators/c1'), isTrue,
        reason: 'expected GET /creators/c1, got $requestedPath');
    final entry = normaliseCreator(raw!);
    expect(entry['id'], 'c1');
    expect(entry['displayName'], 'Riya');
  });

  test(
      'fetchCreator lifts the sibling isFollowing flag into the returned creator map',
      () async {
    // Live shape (verified 2026-08-27): the profile sits under `data.creator`
    // and `isFollowing` is a *sibling* of it, not a field inside it.
    // Regression: the old unwrap returned `data['creator']` verbatim,
    // dropping the flag, so CreatorProfileScreen always re-rendered "Follow"
    // after navigating away and back even when the user already followed.
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'creator': {'_id': 'c1', 'displayName': 'Riya'},
            'isFollowing': true,
          },
        }),
        200,
      );
    });

    final raw = await CreatorsService().fetchCreator('c1');

    expect(raw!['isFollowing'], isTrue);
    expect(normaliseCreator(raw)['isFollowing'], isTrue);
  });

  test('fetchCreatorFollowerCount reads the pagination total from a 1-item page',
      () async {
    String? requestedQuery;
    ApiClient.httpClient = MockClient((request) async {
      requestedQuery = request.url.query;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {'totalCount': 42, 'limit': 1, 'responses': []},
        }),
        200,
      );
    });

    final count = await CreatorsService().fetchCreatorFollowerCount('c1');

    expect(requestedQuery, contains('limit=1'));
    expect(count, 42);
  });

  test('followCreator POSTs to /creators/{id}/follow', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await CreatorsService().followCreator('c1');

    expect(requestedMethod, 'POST');
    expect(requestedPath!.endsWith('/creators/c1/follow'), isTrue,
        reason: 'expected POST /creators/c1/follow, got $requestedPath');
    expect(result, isTrue);
  });

  test('unfollowCreator DELETEs /creators/{id}/follow', () async {
    String? requestedPath;
    String? requestedMethod;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedMethod = request.method;
      return http.Response(jsonEncode({'status': 'success'}), 200);
    });

    final result = await CreatorsService().unfollowCreator('c1');

    expect(requestedMethod, 'DELETE');
    expect(requestedPath!.endsWith('/creators/c1/follow'), isTrue,
        reason: 'expected DELETE /creators/c1/follow, got $requestedPath');
    expect(result, isTrue);
  });
}
