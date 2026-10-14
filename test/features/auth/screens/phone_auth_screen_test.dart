import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/screen_cache.dart';
import 'package:aura_app/core/services/sms_otp_autofill.dart';
import 'package:aura_app/core/services/videos_service.dart';
import 'package:aura_app/features/auth/screens/phone_auth_screen.dart';
import 'package:aura_app/features/auth/screens/profile_setup_screen.dart';
import 'package:aura_app/features/dashboard/dashboard.dart';
import 'package:aura_app/features/shell/main_shell.dart';

/// Test double for the Android SMS-read path — never touches a platform
/// channel. `code` is what an incoming SMS would yield (null = nothing read).
class _FakeSmsAutofill extends SmsOtpAutofill {
  _FakeSmsAutofill({this.code});

  final String? code;
  int cancelCount = 0;

  @override
  Future<String?> waitForCode() async => code;

  @override
  void cancel() => cancelCount++;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
  });

  // Regression coverage: a network failure sending the OTP used to show the
  // raw exception text (e.g. "TimeoutException after 0:00:15.000000: ...")
  // directly in the snackbar via `_snack(e.toString())`, instead of a message
  // a user could act on. Routed through the existing humanizeError() helper
  // (already used elsewhere for exactly this) instead.
  testWidgets('a network timeout sending the OTP shows a humanized message, '
      'not raw exception text', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        throw TimeoutException(
            'Future not completed', const Duration(seconds: 15));
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(const MaterialApp(home: PhoneAuthScreen()));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('TimeoutException'), findsNothing,
        reason: 'the raw Dart exception text must never reach the user');
    expect(
      find.textContaining("Couldn't reach Aura's servers"),
      findsOneWidget,
      reason: 'humanizeError() should turn a timeout into an actionable, '
          'friendly message that doesn\'t assert a specific cause (no '
          'internet vs. server unreachable) the app can\'t actually verify',
    );
  });

  // The OTP is now delivered only by SMS (Message Central, ADR 004). Even if a
  // console/dev backend echoes the code in the response, the client must not
  // pre-fill it — that shortcut is gone.
  testWidgets('the OTP is never auto-filled from the request response',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'otp': '482910', 'validitySeconds': 180},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    final otpField =
        tester.widgetList<TextField>(find.byType(TextField)).elementAt(1);
    expect(otpField.controller!.text, isEmpty,
        reason: 'no direct auto-fill — the code arrives via SMS autofill');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  // The backend now enforces a resend cooldown / request cap and returns 429
  // with a ready-to-show message (ADR 080). That message must reach the user
  // verbatim, not as a generic failure.
  testWidgets('a 429 resend cooldown surfaces the backend wait message',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'fail',
            'message': 'Please wait 58 seconds before requesting another OTP.',
          }),
          429,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Please wait 58 seconds'), findsOneWidget);
  });

  // Backend ADR 121: inside Message Central's own timer no new SMS goes out;
  // the screen must say so rather than claim a fresh code was sent.
  testWidgets('a reused code says so instead of "OTP sent successfully"',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'message':
                  'We already sent a code to this number. Please enter that code.',
              'validitySeconds': 200,
              'resent': false,
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('We already sent a code'), findsOneWidget);
    expect(find.text('OTP sent successfully'), findsNothing);
    // Still moves on to code entry — the earlier code is valid.
    expect(find.textContaining('Resend OTP in'), findsOneWidget);
  });

  testWidgets('resend is gated by a 60s countdown, then requests a new OTP',
      (tester) async {
    var requests = 0;
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        requests++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'validitySeconds': 180},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(requests, 1);
    expect(find.textContaining('Resend OTP in'), findsOneWidget);
    expect(find.text('Resend OTP'), findsNothing);

    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Resend OTP'), findsOneWidget);

    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    await tester.pump();
    expect(requests, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  // Regression: after the "Unify bottom nav" rework the four bottom-nav tabs
  // switch by pushing to MainShellController, whose only listener is a mounted
  // MainShell. These post-login paths still navigated to a bare Dashboard()
  // widget, so users who signed in this session (vs. booting with a saved
  // session, which goes through main.dart -> MainShell) landed on a Dashboard
  // with no MainShell above it — every bottom-nav tab was dead. The landing
  // must be a MainShell.
  Future<void> pumpAndVerifyOtp(WidgetTester tester,
      {required bool isNewUser, bool isProfileComplete = true}) async {
    SharedPreferences.setMockInitialValues({});
    ScreenCache.clear();
    VideosService.resetLocallyMirroredForTest();
    addTearDown(ScreenCache.clear);

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'validitySeconds': 180},
          }),
          200,
        );
      }
      if (path.endsWith('/auth/otp/verify')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'accessToken': 'a',
              'refreshToken': 'r',
              'user': {'id': 'u1', 'isProfileComplete': isProfileComplete},
              'isNewUser': isNewUser,
            },
          }),
          200,
        );
      }
      // Keep the landed tab screens calm — generic empty success.
      return http.Response(
        jsonEncode({
          'status': 'success',
          'data': {
            'user': {'_id': 'u1', 'displayName': 'Test User'},
            'challenges': [],
            'categories': [],
            'leaderboard': [],
            'responses': [],
            'items': [],
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill(code: '123456')),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump(); // requestOtp resolves
    await tester.pump(); // waitForCode resolves -> fills field, calls _verifyOtp
    await tester.pump(); // verifyOtp resolves
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 500)); // nav transition
  }

  testWidgets('a returning user lands on MainShell (bottom-nav tabs work)',
      (tester) async {
    await pumpAndVerifyOtp(tester, isNewUser: false);

    expect(find.byType(MainShell), findsOneWidget,
        reason: 'tab taps go through MainShellController, which is only wired '
            'up while a MainShell is mounted — a bare Dashboard here means all '
            'four bottom-nav tabs are dead');
    // Dashboard is still present, but embedded inside the shell.
    expect(find.byType(Dashboard, skipOffstage: false), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets(
      'a new user whose profile is already complete also lands on MainShell',
      (tester) async {
    await pumpAndVerifyOtp(tester, isNewUser: true, isProfileComplete: true);

    expect(find.byType(MainShell), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('a code read from the SMS auto-submits without the user typing',
      (tester) async {
    var verifyCalled = false;
    String? sentOtp;
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'validitySeconds': 180},
          }),
          200,
        );
      }
      if (path.endsWith('/auth/otp/verify')) {
        verifyCalled = true;
        sentOtp = (jsonDecode(request.body) as Map<String, dynamic>)['otp']
            as String?;
        return http.Response(
          jsonEncode({
            'status': 'fail',
            'message': 'Incorrect OTP. Please try again.',
          }),
          400,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill(code: '482910')),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump(); // requestOtp resolves
    await tester.pump(); // waitForCode resolves -> fills field, calls _verifyOtp
    await tester.pump(); // verifyOtp resolves
    await tester.pump();

    expect(verifyCalled, isTrue);
    expect(sentOtp, '482910');
    final otpField =
        tester.widgetList<TextField>(find.byType(TextField)).elementAt(1);
    expect(otpField.controller!.text, '482910');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  // Regression coverage: a *returning* user (isNewUser: false — true only on
  // account creation, not on every login) whose profile was never completed
  // used to be sent straight to Dashboard regardless of what the server
  // said, with isProfileComplete force-written true into local prefs. Every
  // backend endpoint the Dashboard's tabs call is gated by
  // requireProfileComplete and 403s for an incomplete profile, so the tab
  // bar itself still worked (IndexedStack still switched pages) but every
  // tab's content silently failed to load — reading identically to "the
  // bottom nav doesn't respond" from the outside, and reported as exactly
  // that more than once. Only the onboarding-vs-Dashboard destination on a
  // *new* user (isNewUser: true) had ever actually been driven by the
  // server's isProfileComplete value.
  testWidgets(
      'a returning user with an incomplete profile is sent to onboarding, '
      'not straight to Dashboard', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {'validitySeconds': 180},
          }),
          200,
        );
      }
      if (path.endsWith('/auth/otp/verify')) {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'isNewUser': false,
              'user': {
                'id': 'user-1',
                'phone': '9876543210',
                'countryCode': '+91',
                'isProfileComplete': false,
              },
            },
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump(); // requestOtp resolves
    await tester.pump(); // OTP field appears
    await tester.enterText(find.byType(TextField).at(1), '482910');
    await tester.tap(find.text('Get Started'));
    await tester.pump(); // verifyOtp resolves
    await tester.pump(); // navigation settles

    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    expect(find.byType(Dashboard), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  // App Store guideline 1.2: users must actively agree to the Terms (which
  // state the no-tolerance policy) before registering or logging in. The old
  // passive "by continuing you agree" line let Get OTP proceed with no
  // agreement at all.
  group('Terms agreement (guideline 1.2)', () {
    testWidgets('Get OTP does nothing until the Terms box is ticked',
        (tester) async {
      var otpRequests = 0;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/otp/request')) otpRequests++;
        return http.Response(jsonEncode({'status': 'success', 'data': {}}), 200);
      });

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PhoneAuthScreen()),
      ));
      await tester.enterText(find.byType(TextField).first, '9876543210');

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await tester.tap(find.text('Get OTP'));
      await tester.pump();

      expect(otpRequests, 0,
          reason: 'no OTP may be requested before the user agrees');
      expect(find.textContaining('agree to the Terms of Service'),
          findsWidgets,
          reason: 'the user is told why nothing happened');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Get OTP'));
      await tester.pump();
      await tester.pump();

      expect(otpRequests, 1, reason: 'ticking the box unlocks Get OTP');
    });

    testWidgets('the checkbox text states the no-tolerance policy and links '
        'the Terms and Privacy Policy', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PhoneAuthScreen()));

      final consent = find.byWidgetPredicate((w) =>
          w is RichText &&
          w.text.toPlainText().contains('no tolerance for objectionable '
              'content or abusive users'));
      expect(consent, findsOneWidget);
      final text = tester.widget<RichText>(consent).text.toPlainText();
      expect(text, contains('Terms of Service'));
      expect(text, contains('Privacy Policy'));
    });
  });

  // Regression: after requesting an OTP, editing the phone number left the
  // screen on the verify step ("Get Started", resend cooldown), so a code could
  // never be requested for the new number.
  testWidgets('changing the phone number after sending an OTP resets to the '
      'Get OTP step', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return http.Response(
            jsonEncode({'status': 'success', 'data': {}}), 200);
      }
      return http.Response(jsonEncode({'status': 'fail'}), 404);
    });

    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill()),
    ));
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Get Started'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '9876543211');
    await tester.pump();

    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Get OTP'), findsOneWidget);
    expect(find.textContaining('Resend OTP'), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
