import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/settings_screen.dart';

// Regression coverage: the "Preview: Video Rejected" debug tile got stuck on
// an undismissable "Review Unavailable" popup — tapping OK / the ✕ / the
// barrier did nothing.
//
// Two compounding bugs, both in the tile's showDialog call:
//   1. It passed `initialResult: {'status': 'rejected'}`. 'rejected' is not a
//      real backend Submission.status (the enum is pending|scored|failed|
//      flagged), so submissionStatusFromApi() maps it to 'ai_error' and the
//      popup renders the "Review Unavailable" screen instead of the rejected
//      one the tile is named for.
//   2. It used `showDialog<bool>`, but every dismiss control in
//      AuraSubmittedPopup pops with the String 'continue'/'retry'. Popping a
//      DialogRoute<bool> with a String throws inside Route.didPop, so the pop
//      never completes and the dialog can't be closed.
void main() {
  testWidgets(
      'the "Preview: Video Rejected" debug tile shows the rejected screen and '
      'can be dismissed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    final tile = find.text('Preview: Video Rejected');
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);

    // The popup fires a post-frame callback to apply the initial result, then
    // runs non-terminating pulse animations — so pump manually, don't settle.
    await tester.pump(); // build
    await tester.pump(); // post-frame callback applies the result
    await tester.pump(const Duration(milliseconds: 700)); // enter scale/fade
    tester.takeException(); // test bundle has no image assets — unrelated

    // Bug 1: must be the rejected screen, not the AI-error one.
    expect(find.text('Review Unavailable'), findsNothing,
        reason: "'status': 'scored' + verdict 'INVALID' must resolve to a "
            'rejected verdict, not ai_error');
    expect(find.text('Dancing Girl'), findsOneWidget,
        reason: 'the rejected-video screen renders the challenge title');

    // Bug 2: the dismiss control actually closes the dialog. Pre-fix
    // (showDialog<bool>) this pop throws "String is not a subtype of bool?"
    // and the dialog stays put.
    final dismissImage = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName.contains('Asset 131'));
    expect(dismissImage, findsOneWidget);
    await tester.tap(
      find.ancestor(of: dismissImage, matching: find.byType(GestureDetector)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.takeException(); // missing image assets again — still unrelated

    expect(find.text('Dancing Girl'), findsNothing,
        reason: 'the popup must be gone after tapping dismiss');
  });
}
