import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/archived_videos_screen.dart';

// Regression coverage: this screen used to query a Firestore `submissions`
// collection that no longer exists post-migration, via a StreamBuilder that
// only checked `snap.hasData` and never `snap.hasError` — so a
// permission-denied error (there's no Firebase Auth session backing this
// app anymore) left it spinning on a CircularProgressIndicator forever.
// There's also no REST equivalent (`Submission` has no `isArchived` field,
// and the only writer of that flag is itself unreachable admin tooling), so
// the fix drops the broken query entirely and always resolves straight to
// the empty state, which is the only state that's ever actually true.
void main() {
  testWidgets(
      'resolves immediately to the empty state, never spins indefinitely',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ArchivedVideosScreen()));

    // No pumpAndSettle needed: there is no async gap left to wait out. The
    // old, broken version would still be showing a spinner at this exact
    // point (a Firestore stream that never resolves in a test environment
    // with no Firebase app, and never would resolve in production either
    // since the query always errors and the error is never handled).
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the screen must never get stuck loading — there is no '
            'pending network call for it to be waiting on');
    expect(find.text('No archived videos'), findsOneWidget);
  });
}
