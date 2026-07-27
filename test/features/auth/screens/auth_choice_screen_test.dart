import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/features/auth/screens/auth_choice_screen.dart';
import 'package:aura_app/features/auth/screens/phone_auth_screen.dart';

// Regression coverage: the backend has no email/password login endpoint for
// players (only phone OTP, Google, Apple, Facebook — email/password exists
// solely for the separate admin system, per the live OpenAPI spec). This
// screen used to offer "Continue with Email", which routed to a LoginScreen
// that only ever talked to Firebase and could never create a real REST
// session. The fix removes that dead option entirely.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'privacy_v1_accepted': true});
  });

  testWidgets('has no email login option, and Phone still navigates to PhoneAuthScreen',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthChoiceScreen()));
    await tester.pump();

    expect(find.textContaining('Email'), findsNothing);

    await tester.tap(find.text('Continue with Phone'));
    await tester.pumpAndSettle();

    expect(find.byType(PhoneAuthScreen), findsOneWidget);
  });
}
