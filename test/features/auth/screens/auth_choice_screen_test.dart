import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:aura_app/features/auth/screens/auth_choice_screen.dart';
import 'package:aura_app/features/auth/screens/phone_auth_screen.dart';

// Regression coverage: the backend has no email/password login endpoint for
// players (only phone OTP, Google, Apple, Facebook — email/password exists
// solely for the separate admin system, per the live OpenAPI spec). This
// screen used to offer "Continue with Email", which routed to a LoginScreen
// that only ever talked to Firebase and could never create a real REST
// session. The fix removes that dead option entirely.
void main() {
  testWidgets('has no email login option, and Phone still navigates to PhoneAuthScreen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_v1_accepted': true});
    await tester.pumpWidget(const MaterialApp(home: AuthChoiceScreen()));
    await tester.pump();

    expect(find.textContaining('Email'), findsNothing);

    await tester.tap(find.text('Continue with Phone'));
    await tester.pumpAndSettle();

    expect(find.byType(PhoneAuthScreen), findsOneWidget);
  });

  // Regression coverage: "Privacy Policy" and "Terms of Service" in the
  // first-run privacy sheet used to be dead TapGestureRecognizers (no-op
  // onTap) — an App Store 5.1.1(v) / Play Store rejection risk since the
  // links never actually opened anything. They must now open the hosted
  // policy page's respective tab.
  testWidgets('Privacy Policy and Terms of Service links open the hosted policy page',
      (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_v1_accepted': false});
    final mockLauncher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = mockLauncher;

    // The privacy sheet's content doesn't scroll internally — give it a
    // taller test surface (like a real device) so it doesn't overflow the
    // default 800x600 test window and mask the actual assertions below.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AuthChoiceScreen()));
    await tester.pumpAndSettle();

    final privacySpan = tester.widget<RichText>(
      find.byWidgetPredicate((w) =>
          w is RichText && _spanText(w.text).contains('By continuing you agree')),
    );
    final spans = (privacySpan.text as TextSpan).children!;

    final privacyRecognizer =
        (spans.firstWhere((s) => (s as TextSpan).text == 'Privacy Policy') as TextSpan)
                .recognizer
            as TapGestureRecognizer;
    privacyRecognizer.onTap!();
    await tester.pumpAndSettle();
    expect(mockLauncher.launchedUrls.single, endsWith('#privacy'));

    final termsRecognizer =
        (spans.firstWhere((s) => (s as TextSpan).text == 'Terms of Service') as TextSpan)
                .recognizer
            as TapGestureRecognizer;
    termsRecognizer.onTap!();
    await tester.pumpAndSettle();
    expect(mockLauncher.launchedUrls.last, endsWith('#terms'));
  });
}

String _spanText(InlineSpan span) {
  final buffer = StringBuffer();
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) buffer.write(s.text);
    return true;
  });
  return buffer.toString();
}

class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}
