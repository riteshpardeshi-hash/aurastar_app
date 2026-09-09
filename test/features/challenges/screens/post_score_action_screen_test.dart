import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/challenges/screens/post_score_action_screen.dart';

// Regression coverage: this screen used to show a banner claiming a
// non-best submission "has been archived automatically and will be deleted
// in 7 days" — nothing on any reachable path ever archives or deletes a
// submission server-side (the Submission schema has no isArchived field).
// The score card right above the banner already correctly said "Not your
// best — no Auras earned", so the banner was both false and redundant; the
// fix removes it entirely rather than rephrasing a duplicate.
void main() {
  testWidgets(
      'a non-best approved submission never claims archival/auto-deletion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PostScoreActionScreen(
        submissionId: 'sub-1',
        challengeTitle: 'Test Challenge',
        challengeId: 'challenge-1',
        submissionData: {
          'status': 'scored',
          'verdict': 'GOOD',
          'aiScore': 55,
          'netAurasAwarded': 0,
          'isBestForChallenge': false,
        },
      ),
    ));
    await tester.pump();

    expect(find.textContaining('archived'), findsNothing,
        reason: 'submissions are never actually archived server-side');
    expect(find.textContaining('deleted in 7 days'), findsNothing);
    expect(find.text('Not your best — no Auras earned'), findsOneWidget);
  });
}
