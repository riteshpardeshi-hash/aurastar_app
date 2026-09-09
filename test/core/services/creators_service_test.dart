import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenges_service.dart';
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

  test(
      'fetchCreatorChallenges hits GET /challenges filtered by creatorId + '
      'sourceType and unwraps data.challenges', () async {
    // Regression: the creator profile used to have no authored-challenge feed
    // at all — its "Challenges" stat was the length of the (always-empty,
    // backend-issues/005) /creators/{id}/videos list, so every creator profile
    // showed "0 Challenges" and an empty grid. This is the endpoint that
    // populates both now.
    String? requestedPath;
    String? requestedQuery;
    ApiClient.httpClient = MockClient((request) async {
      requestedPath = request.url.path;
      requestedQuery = request.url.query;
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'challenges': [
              {'_id': 'ch1', 'title': 'Wink', 'thumbnailUrl': 't1'},
              {'_id': 'ch2', 'title': 'Smile'},
            ],
            'pagination': {'total': 2, 'hasNextPage': false},
          },
        }),
        200,
      );
    });

    final list = await CreatorsService().fetchCreatorChallenges('c1');

    expect(requestedPath!.endsWith('/challenges'), isTrue,
        reason: 'expected GET /challenges, got $requestedPath');
    expect(requestedQuery, contains('creatorId=c1'));
    expect(requestedQuery, contains('sourceType=Creator'));
    expect(list, hasLength(2));
    expect(normaliseChallenge(list.first)['id'], 'ch1');
    expect(normaliseChallenge(list.first)['title'], 'Wink');
  });

  test('fetchCreatorChallenges returns [] when the request is not successful',
      () async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'fail', 'message': 'nope'}),
        403,
      );
    });

    expect(await CreatorsService().fetchCreatorChallenges('c1'), isEmpty);
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
