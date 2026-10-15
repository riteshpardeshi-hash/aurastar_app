import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenge_create_flow.dart';
import 'package:aura_app/core/services/challenges_service.dart';
import 'package:aura_app/core/services/creator_challenges_service.dart';

// Regression (2026-10-15): a create request whose answer was lost is retried with the same
// uploaded video. The backend answers 409 "This video has already been claimed." — the app must
// read that real error envelope as "your earlier attempt created it", for BOTH create endpoints,
// instead of showing an error (or, before this fix, crashing on a null `data`).
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

  /// First create: connection drops (server still creates). Retry: real backend 409 envelope.
  void serveLostThenAlreadyClaimed(List<String> log) {
    var creates = 0;
    ApiClient.httpClient = MockClient((req) async {
      log.add('${req.method} ${req.url.path}');
      if (++creates == 1) throw const SocketException('Connection reset by peer');
      return http.Response(
        jsonEncode({'status': 'error', 'statusCode': 409, 'message': 'This video has already been claimed.'}),
        409,
      );
    });
  }

  ChallengeCreateFlow flowWith(Future<void> Function(String videoId) create) => ChallengeCreateFlow(
        presign: () async => const ChallengeVideoUpload(uploadUrl: 'https://s3/u', videoId: 'v1'),
        upload: (url, video, onProgress) async {},
        create: create,
      );

  test('draft flow (POST /creator/challenges): retry after a lost answer → created earlier, no duplicate', () async {
    final log = <String>[];
    serveLostThenAlreadyClaimed(log);
    final flow = flowWith((id) => CreatorChallengesService()
        .createDraft(title: 'talk', category: 'cat1', difficulty: 'Medium', videoId: id));
    final video = File('/tmp/talk.mp4');

    await expectLater(flow.run(video), throwsA(anything));
    expect(await flow.run(video), ChallengeCreateOutcome.createdEarlier);
    expect(log, everyElement(endsWith('/creator/challenges')));
  });

  test('record flow (POST /challenges): retry after a lost answer → created earlier, no duplicate', () async {
    final log = <String>[];
    serveLostThenAlreadyClaimed(log);
    final flow = flowWith((id) => ChallengesService()
        .createChallenge(title: 'rec', description: 'd', categoryId: 'cat1', difficulty: 'Medium', videoId: id));
    final video = File('/tmp/rec.mp4');

    await expectLater(flow.run(video), throwsA(anything));
    expect(await flow.run(video), ChallengeCreateOutcome.createdEarlier);
    expect(log, everyElement(endsWith('/challenges')));
  });

  test('a server error on create surfaces the server message, not a type error', () async {
    ApiClient.httpClient = MockClient((req) async => http.Response(
          jsonEncode({'status': 'error', 'statusCode': 400, 'message': 'Category not found.'}),
          400,
        ));
    await expectLater(
      ChallengesService()
          .createChallenge(title: 't', description: 'd', categoryId: 'x', difficulty: 'Medium', videoId: 'v'),
      throwsA(predicate((e) => e.toString().contains('Category not found.'))),
    );
    await expectLater(
      CreatorChallengesService().createDraft(title: 't', category: 'x', difficulty: 'Medium', videoId: 'v'),
      throwsA(predicate((e) => e.toString().contains('Category not found.'))),
    );
  });
}
