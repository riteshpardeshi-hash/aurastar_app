import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/settings_screen.dart';

// Regression coverage for the "Deactivate Account" tile added under
// Settings → Danger Zone (ADR 022 — reversible any time by logging back in,
// unlike Delete Account, so it's a single confirm dialog rather than a
// typed-confirmation flow).
//
// Same boundary as the pre-existing Logout / Logout of All Devices / Delete
// Account tiles: the network call (AuthApiService().deactivateAccount(),
// which also calls FirebaseAuth.instance.signOut()) isn't exercised here,
// since this test bundle has no Firebase app initialized. This covers the
// confirm dialog itself.
void main() {
  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    final tile = find.text('Deactivate Account');
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  testWidgets('shows a confirm dialog explaining it is reversible by logging back in',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Deactivate Account'), findsWidgets);
    expect(
      find.textContaining('Log back in any time to reactivate'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel closes the dialog without navigating away',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    // The confirm dialog's own "Deactivate" action button is gone once
    // dismissed — only the Settings tile (also labelled "Deactivate
    // Account") remains.
    expect(find.widgetWithText(TextButton, 'Deactivate'), findsNothing);
  });
}
