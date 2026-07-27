import 'package:flutter_test/flutter_test.dart';

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
    });

    test('the literal strings PASS/FAIL are never treated specially — the '
        'API never sends them', () {
      // Guards against reintroducing the old dead-code assumption: a
      // 'PASS'/'FAIL' verdict with no recognised `status` must NOT be
      // special-cased into 'approved'/'rejected'.
      expect(
        submissionStatusFromApi({'status': 'PASS', 'verdict': 'PASS'}),
        'pending',
      );
      expect(
        submissionStatusFromApi({'status': 'FAIL', 'verdict': 'FAIL'}),
        'pending',
      );
    });
  });

  group('normaliseSubmissionEntry', () {
    // Regression coverage: the challenge leaderboard (leaderboard_screen.dart
    // and challenge_detail.dart's Top Submissions tile) used to read
    // sub['user']?['displayName'] and sub['starsCount']/'stars' loosely, but
    // GET /challenges/{id}/submissions — confirmed against the live
    // backend — never includes a joined display name, and its `userId` field
    // is populated with only `{_id}` (or comes back as a bare id string).
    // starsCount IS a real field on the live Submission record (undocumented
    // in the stale OpenAPI schema, confirmed present in production data),
    // read directly here rather than guessed at through multiple fallback keys.
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

    test('never fabricates a name — leaves name/username blank for the '
        'caller to apply an honest fallback', () {
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
}
