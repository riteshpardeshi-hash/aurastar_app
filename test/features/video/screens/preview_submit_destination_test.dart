import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/video/screens/preview_screen.dart';

// Regression coverage for the "Review Unavailable" dead end: when the AI
// couldn't score a submission (backend status 'failed' → 'ai_error'), the
// result popup used to close straight into PostScoreActionScreen — a results
// screen with no score card, no primary CTA, and only an easily-missed
// AppBar '×' — leaving the user unable to navigate away. postSubmitDestination
// is the pure routing decision that now sends that case out of the capture
// flow instead.
void main() {
  group('postSubmitDestination', () {
    test('a "retry" popup action always goes back to the camera', () {
      expect(
        postSubmitDestination('retry', {'status': 'scored', 'verdict': 'GOOD'}),
        PostSubmitDestination.retake,
      );
      // retry wins even for an unscored submission.
      expect(
        postSubmitDestination('retry', {'status': 'failed'}),
        PostSubmitDestination.retake,
      );
    });

    test('a submission the AI could not score exits the flow', () {
      expect(
        postSubmitDestination('continue', {'status': 'failed'}),
        PostSubmitDestination.exitFlow,
      );
    });

    test('an unrecognised backend status also exits the flow, not into a '
        'blank result screen', () {
      expect(
        postSubmitDestination('continue', {'status': 'processing'}),
        PostSubmitDestination.exitFlow,
      );
    });

    test('a real approved verdict shows the result screen', () {
      expect(
        postSubmitDestination('continue', {
          'status': 'scored',
          'verdict': 'AVERAGE',
          'aiScore': 78,
        }),
        PostSubmitDestination.showResult,
      );
    });

    test('a rejected verdict (INVALID / flagged) still shows the result '
        'screen — it has a score card and feedback to show', () {
      expect(
        postSubmitDestination('continue', {
          'status': 'scored',
          'verdict': 'INVALID',
          'aiScore': 0,
        }),
        PostSubmitDestination.showResult,
      );
      expect(
        postSubmitDestination('continue', {'status': 'flagged'}),
        PostSubmitDestination.showResult,
      );
    });
  });
}
