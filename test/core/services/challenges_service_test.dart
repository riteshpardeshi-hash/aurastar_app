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
}
