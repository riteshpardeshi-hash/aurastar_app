import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/challenges_service.dart';

// Regression coverage for a bug where AuraSubmittedPopup, PostScoreAction-
// Screen, MyAccountScreen and AllVideosScreen all compared a submission's
// `verdict` against the literal strings 'PASS'/'FAIL' to decide whether it
// was approved. Per the live backend spec (openapi.yaml Submission schema),
// `status` is actually `pending | scored | failed | flagged` and `verdict`
// is `EXCELLENT | GOOD | AVERAGE | WEAK | INVALID` — the API never sends
// "PASS" or "FAIL" anywhere (confirmed: zero occurrences in the fetched
// spec). That made every genuinely approved, points-awarding submission
// fall through to the "ai_error"/"rejected" branch: AuraSubmittedPopup got
// stuck polling forever (never satisfied its own PASS/FAIL/approved/
// rejected/ai_error check), and PostScoreActionScreen showed "Keep trying —
// you'll get it!" on a submission that had, in fact, already earned Auras.
void main() {
  group('submissionStatusFromApi', () {
    test('a scored submission with a real verdict value is approved', () {
      // Mirrors the openapi.yaml example response for a successful,
      // points-awarding submission (POST /challenges/{id}/submissions).
      expect(
        submissionStatusFromApi({
          'status': 'scored',
          'verdict': 'AVERAGE',
          'aiScore': 78,
          'isBestForChallenge': true,
          'netAurasAwarded': 78,
        }),
        'approved',
      );
    });

    for (final verdict in ['EXCELLENT', 'GOOD', 'AVERAGE', 'WEAK']) {
      test('scored + verdict $verdict is approved', () {
        expect(
          submissionStatusFromApi({'status': 'scored', 'verdict': verdict}),
          'approved',
        );
      });
    }

    test('scored + INVALID verdict (zero-condition matched) is rejected', () {
      expect(
        submissionStatusFromApi({'status': 'scored', 'verdict': 'INVALID'}),
        'rejected',
      );
    });

    test('a content-safety-flagged submission is rejected', () {
      expect(submissionStatusFromApi({'status': 'flagged'}), 'rejected');
    });

    test('a failed submission maps to ai_error', () {
      expect(submissionStatusFromApi({'status': 'failed'}), 'ai_error');
    });

    test('a still-processing submission is pending', () {
      expect(submissionStatusFromApi({'status': 'pending'}), 'pending');
    });

    test('a missing status defaults to pending, not a crash', () {
      expect(submissionStatusFromApi({}), 'pending');
      expect(submissionStatusFromApi({'status': null}), 'pending');
    });

    test('an unrecognised status maps to ai_error — never approved/rejected, '
        'and never a silent pending', () {
      // The documented enum is pending|scored|failed|flagged. Anything else
      // is a server-side state the client can't interpret. It must not be
      // special-cased into approved/rejected (the old dead PASS/FAIL
      // assumption), and it must not fall through to 'pending' either — that
      // left AuraSubmittedPopup polling forever and stranded the user on a
      // blank PostScoreActionScreen. ai_error routes it to manual review and
      // keeps the result UI's dismiss/exit path working.
      expect(
        submissionStatusFromApi({'status': 'PASS', 'verdict': 'PASS'}),
        'ai_error',
      );
      expect(
        submissionStatusFromApi({'status': 'FAIL', 'verdict': 'FAIL'}),
        'ai_error',
      );
      expect(submissionStatusFromApi({'status': 'processing'}), 'ai_error');
      expect(submissionStatusFromApi({'status': 'error'}), 'ai_error');
    });
  });

  group('normaliseSubmissionEntry', () {
    // GET /challenges/{id}/submissions — confirmed against the live backend —
    // populates `userId` as a `{_id, displayName?, avatar?}` object (or, for
    // older records, a bare id string); the OpenAPI schema still types it as
    // a plain string and is stale. `displayName` is only present when the
    // user set one. starsCount IS a real field on the live Submission record
    // (undocumented in the stale schema, confirmed present in production).
    test('extracts id from a populated {_id} userId object', () {
      final e = normaliseSubmissionEntry({
        'userId': {'_id': 'user-42'},
        'aiScore': 67,
        'starsCount': 3,
      });
      expect(e['id'], 'user-42');
      expect(e['score'], 67);
      expect(e['stars'], 3);
    });

    test('extracts id from a bare userId string', () {
      final e = normaliseSubmissionEntry({
        'userId': 'user-7',
        'aiScore': 40,
        'starsCount': 0,
      });
      expect(e['id'], 'user-7');
    });

    test('surfaces the real displayName when the populated userId carries one',
        () {
      final e = normaliseSubmissionEntry({
        'userId': {'_id': 'user-1', 'displayName': 'Tushar'},
        'aiScore': 50,
      });
      expect(e['name'], 'Tushar');
    });

    test('leaves name blank (for a rank fallback) when userId has no name', () {
      final e = normaliseSubmissionEntry({
        'userId': {'_id': 'user-1'},
        'aiScore': 50,
      });
      expect(e['name'], '');
      expect(e['username'], '');
    });

    test('missing aiScore/starsCount default to 0, not a crash', () {
      final e = normaliseSubmissionEntry({'userId': 'user-1'});
      expect(e['score'], 0);
      expect(e['stars'], 0);
    });
  });

  group('leaderboardFromSubmissions', () {
    // Regression coverage: the per-challenge leaderboard listed every public
    // submission, so a user who submitted several videos to one challenge
    // showed up on several consecutive rows (once per attempt) and pushed
    // everyone else's rank down. It must collapse to one row per user at
    // their best score — matching the backend's own "personal best only"
    // Aura rule.
    test('keeps one row per user, at their highest score, re-ranked desc', () {
      final rows = leaderboardFromSubmissions([
        {'userId': {'_id': 'a', 'displayName': 'Aditi'}, 'aiScore': 79},
        {'userId': {'_id': 'a', 'displayName': 'Aditi'}, 'aiScore': 70},
        {'userId': {'_id': 'b', 'displayName': 'Bharat'}, 'aiScore': 78},
        {'userId': {'_id': 'a', 'displayName': 'Aditi'}, 'aiScore': 61},
        {'userId': {'_id': 'b', 'displayName': 'Bharat'}, 'aiScore': 56},
      ]);
      expect(rows.map((e) => e['id']).toList(), ['a', 'b']);
      expect(rows.map((e) => e['score']).toList(), [79, 78]);
    });

    test('rows with no resolvable user id are never merged together', () {
      final rows = leaderboardFromSubmissions([
        {'userId': null, 'aiScore': 40},
        {'userId': null, 'aiScore': 30},
      ]);
      expect(rows.length, 2);
    });
  });

  // POST /challenges/{id}/submissions returns `data.submission` plus, for the
  // few submissions that win one, coupons in two arrays: `data.levelUpOffers`
  // and `data.leaderboardOffers` (backend ADRs 082–084). createSubmission
  // concatenates them into `coupons` so the capture flow can show the
  // "you won N coupons" sheet. `data.grantedVouchers` is the pre-rename name
  // for `leaderboardOffers` and is still accepted.
  group('createSubmission', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({
        'api_access_token': 'token',
        'api_refresh_token': 'refresh',
        'api_user_id': 'user-1',
      });
    });

    tearDown(() {
      ApiClient.httpClient = http.Client();
    });

    test('concatenates levelUpOffers then leaderboardOffers into coupons',
        () async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submission': {'_id': 'sub-1', 'status': 'scored', 'aiScore': 82},
              'auraBalance': 1240,
              'levelUp': {'leveledUp': true, 'oldLevel': 7, 'newLevel': 8},
              'levelUpOffers': [
                {
                  'grantId': 'g0',
                  'offerName': 'Level 8 Reward',
                  'sourcing': 'CATALOG',
                  'code': 'AJIO60',
                  'merchantName': 'AJIO',
                  'level': 8,
                },
              ],
              'leaderboardOffers': [
                {
                  'grantId': 'g1',
                  'offerName': 'Summer Top 10',
                  'sourcing': 'POOL',
                  'code': 'K7Q2M9X4RT',
                  'rank': 6,
                  'redeemUrl': 'https://brand.example.com/redeem',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result =
          await ChallengesService().createSubmission('chal-1', 'vid-1');

      expect(result.submission['_id'], 'sub-1');
      expect(result.auraBalance, 1240);
      expect(result.levelUp?['newLevel'], 8);
      expect(result.coupons, hasLength(2));
      expect(result.coupons.first['code'], 'AJIO60'); // level-up first
      expect(result.coupons.last['code'], 'K7Q2M9X4RT');
    });

    test('accepts the pre-rename grantedVouchers key as leaderboardOffers',
        () async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submission': {'_id': 'sub-1b', 'status': 'scored'},
              'grantedVouchers': [
                {'grantId': 'g1', 'code': 'K7Q2M9X4RT', 'rank': 6},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result =
          await ChallengesService().createSubmission('chal-1', 'vid-1');

      expect(result.coupons, hasLength(1));
      expect(result.coupons.single['code'], 'K7Q2M9X4RT');
    });

    test('coupons defaults to [] when no offer arrays are present', () async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'submission': {'_id': 'sub-2', 'status': 'scored'},
            },
          }),
          200,
        );
      });

      final result =
          await ChallengesService().createSubmission('chal-1', 'vid-1');

      expect(result.submission['_id'], 'sub-2');
      expect(result.coupons, isEmpty);
      expect(result.auraBalance, isNull);
      expect(result.levelUp, isNull);
    });

    test('throws the backend message on a non-success response', () async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'fail', 'message': 'Challenge is not live.'}),
          400,
        );
      });

      expect(
        () => ChallengesService().createSubmission('chal-1', 'vid-1'),
        throwsA('Challenge is not live.'),
      );
    });
  });
}
