import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/account/screens/settings_screen.dart';

// Regression coverage for the "Delete Account" tile added under Settings →
// Danger Zone (App Store Guideline 5.1.1(v) / Google Play account-deletion
// requirement — self-service, in-app, no support ticket).
//
// The destructive network call itself (AuthApiService().deleteAccount(),
// which also calls FirebaseAuth.instance.signOut()) isn't exercised here —
// same boundary as the pre-existing Logout / Logout of All Devices tiles,
// neither of which has test coverage past the confirm dialog, since this
// test bundle has no Firebase app initialized. This test covers the actual
// new surface: the two-step confirm dialog's own logic — typed "DELETE" is
// required, case-insensitively, before the destructive action is enabled.
void main() {
  Future<void> openDialog(WidgetTester tester) async {
    // Settings is a long ListView — the default 800x600 test window is
    // narrower than a real phone and can misplace tap targets after
    // scrolling. Match a real device instead.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    final tile = find.text('Delete Account');
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  testWidgets('Delete Forever is disabled until the user types DELETE',
      (tester) async {
    await openDialog(tester);

    TextButton deleteButton() => tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Delete Forever'));

    expect(deleteButton().onPressed, isNull,
        reason: 'must start disabled — no accidental irreversible deletes');

    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(deleteButton().onPressed, isNotNull,
        reason: 'the confirmation phrase is case-insensitive');

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.pump();
    expect(deleteButton().onPressed, isNull,
        reason: 'must re-lock if the field no longer matches');
  });

  testWidgets('Cancel closes the dialog without navigating away',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Account'), findsOneWidget,
        reason: 'back on the Settings screen, dialog dismissed');
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
