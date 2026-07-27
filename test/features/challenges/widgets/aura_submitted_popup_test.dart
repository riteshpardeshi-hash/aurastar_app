import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/challenges/widgets/aura_submitted_popup.dart';

// Regression coverage: the "not your best" badge on the achievement-card
// view used to claim 'Not your best — archived (deletes in 7 days)'. No
// submission is ever actually archived or auto-deleted server-side (the
// Submission schema has no isArchived field, and nothing writes one on any
// reachable path — see archived_videos_screen.dart's fix). The badge now
// says the one thing that's actually true: no Auras were earned.
void main() {
  testWidgets(
      'the non-best badge on the card view never claims archival/deletion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuraSubmittedPopup(
          submissionId: 'sub-1',
          challengeTitle: 'Test Challenge',
          challengeId: 'challenge-1',
          initialResult: const {
            'status': 'scored',
            'verdict': 'GOOD',
            'aiScore': 60,
            'netAurasAwarded': 0,
            'isBestForChallenge': false,
          },
        ),
      ),
    ));

    // Not pumpAndSettle(): this widget has a repeating pulse
    // AnimationController that would make it time out by design.
    await tester.pump(); // build
    await tester.pump(); // postFrameCallback applies the initial result
    tester.takeException(); // unrelated: missing test-bundle image assets

    // Jump straight from the summary view to the card view via the
    // "card" icon button (third of the three summary actions).
    final cardButton = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName.endsWith('Asset 146.png'));
    expect(cardButton, findsOneWidget);
    await tester.tap(cardButton);
    await tester.pump();
    tester.takeException();

    expect(find.textContaining('archived'), findsNothing,
        reason: 'submissions are never actually archived server-side');
    expect(find.textContaining('deletes in 7 days'), findsNothing);
    expect(find.text('Not your best — no Auras earned'), findsOneWidget);
  });
}
