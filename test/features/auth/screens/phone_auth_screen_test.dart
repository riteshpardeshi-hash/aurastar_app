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

  final phoneField = find.byKey(const Key('phone-field'));
  final getOtp = find.byKey(const Key('get-otp'));
  final codeField = find.byKey(const Key('otp-code-field'));
  final verifyButton = find.byKey(const Key('verify'));

  http.Response ok(Map<String, dynamic> data) =>
      http.Response(jsonEncode({'status': 'success', 'data': data}), 200);
  http.Response fail(String message, int status) =>
      http.Response(jsonEncode({'status': 'fail', 'message': message}), status);

  /// Lets the step switch animation finish (no pumpAndSettle: the orb spins forever).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openScreen(WidgetTester tester, {SmsOtpAutofill? sms, bool phoneSize = true}) async {
    if (phoneSize) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
      home: PhoneAuthScreen(smsAutofill: sms ?? _FakeSmsAutofill()),
    ));
  }

  /// Number typed, Terms ticked, Get OTP tapped.
  Future<void> requestCode(WidgetTester tester, {String phone = '9876543210'}) async {
    await tester.enterText(phoneField, phone);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(getOtp);
    await settle(tester);
  }

  Future<void> closeScreen(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: SizedBox()));

  // ── The reported bug (2026-10-19) ──────────────────────────────────────────

  testWidgets('the code cannot be typed before a code was requested', (tester) async {
    await openScreen(tester);
    expect(phoneField, findsOneWidget);
    expect(codeField, findsNothing, reason: 'no code box next to a "Get OTP" button');
    await closeScreen(tester);
  });

  // The send succeeded server-side but its answer was lost (USB / weak network); the
  // retry hit the 60 s cooldown. The user must land on code entry, not stay stuck.
  testWidgets('a cooldown 429 after a lost answer goes straight to code entry', (tester) async {
    var requests = 0;
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        requests++;
        if (requests == 1) {
          throw TimeoutException('Future not completed', const Duration(seconds: 15));
        }
        return fail('Please wait 25 seconds before requesting another OTP.', 429);
      }
      return fail('not found', 404);
    });

    await openScreen(tester);
    await requestCode(tester);
    expect(find.textContaining("Couldn't reach Aura's servers"), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);

    await tester.tap(getOtp);
    await settle(tester);

    expect(codeField, findsOneWidget);
    expect(find.textContaining('We already sent a code to +91 98765 43210'), findsOneWidget);
    expect(find.text('Resend code in 0:25'), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets('after a lost answer, "Already got a code?" opens code entry', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        throw TimeoutException('Future not completed', const Duration(seconds: 15));
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);

    await tester.tap(find.byKey(const Key('have-code')));
    await settle(tester);
    expect(codeField, findsOneWidget);
    expect(find.byKey(const Key('resend')), findsOneWidget, reason: 'resend allowed straight away');
    await closeScreen(tester);
  });

  // ── Sending ────────────────────────────────────────────────────────────────

  testWidgets('a pasted "+91 98765 43210" becomes the 10-digit number', (tester) async {
    await openScreen(tester);
    await tester.enterText(phoneField, '+91 98765 43210');
    await tester.pump();
    expect(tester.widget<TextField>(phoneField).controller!.text, '9876543210');
    await closeScreen(tester);
  });

  testWidgets('an invalid number is explained and nothing is sent', (tester) async {
    var requests = 0;
    ApiClient.httpClient = MockClient((request) async {
      requests++;
      return ok({});
    });
    await openScreen(tester);
    await requestCode(tester, phone: '12345');
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(requests, 0);
    await closeScreen(tester);
  });

  testWidgets('the OTP is never auto-filled from the request response', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return ok({'otp': '482910', 'validitySeconds': 180});
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty,
        reason: 'no direct auto-fill — the code arrives via SMS autofill');
    await closeScreen(tester);
  });

  testWidgets('the request cap message reaches the user verbatim', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return fail(
            'Too many OTP requests. You can request at most 5 codes every 15 minutes. Try again in 300 seconds.',
            429);
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    expect(find.textContaining('Too many OTP requests'), findsOneWidget);
    expect(find.byKey(const Key('have-code')), findsOneWidget);
    await closeScreen(tester);
  });

  // Backend ADR 121: inside Message Central's own timer no new SMS goes out.
  testWidgets('a reused code says so instead of claiming a new one was sent', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        return ok({
          'message': 'We already sent a code to this number. Please enter that code.',
          'validitySeconds': 200,
          'resent': false,
        });
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    expect(find.textContaining('We already sent a code'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets('resend is gated by a 60 s countdown, then requests a new code', (tester) async {
    var requests = 0;
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        requests++;
        return ok({'validitySeconds': 180});
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);

    expect(requests, 1);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
    expect(find.byKey(const Key('resend')), findsNothing);

    await tester.pump(const Duration(seconds: 61));
    expect(find.byKey(const Key('resend')), findsOneWidget);

    await tester.tap(find.byKey(const Key('resend')));
    await settle(tester);
    expect(requests, 2);
    expect(find.textContaining('A new code is on its way'), findsOneWidget);
    await closeScreen(tester);
  });

  // ── Verifying ──────────────────────────────────────────────────────────────

  // Regression: the post-login landing must be a MainShell (bottom-nav tabs are wired
  // through MainShellController, which only listens while a MainShell is mounted).
  Future<void> signInWithSmsCode(WidgetTester tester,
      {required bool isNewUser, bool isProfileComplete = true}) async {
    SharedPreferences.setMockInitialValues({});
    ScreenCache.clear();
    VideosService.resetLocallyMirroredForTest();
    addTearDown(ScreenCache.clear);

    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      if (path.endsWith('/auth/otp/verify')) {
        return ok({
          'accessToken': 'a',
          'refreshToken': 'r',
          'user': {'id': 'u1', 'isProfileComplete': isProfileComplete},
          'isNewUser': isNewUser,
        });
      }
      return ok({
        'user': {'_id': 'u1', 'displayName': 'Test User'},
        'challenges': [],
        'categories': [],
        'leaderboard': [],
        'responses': [],
        'items': [],
      });
    });

    // Default test viewport: these check where sign-in lands, not the Dashboard's layout.
    await openScreen(tester, sms: _FakeSmsAutofill(code: '123456'), phoneSize: false);
    await requestCode(tester);
    await tester.pump(); // verify resolves
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 500)); // nav transition
  }

  testWidgets('a returning user lands on MainShell (bottom-nav tabs work)', (tester) async {
    await signInWithSmsCode(tester, isNewUser: false);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(Dashboard, skipOffstage: false), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets('a new user whose profile is already complete also lands on MainShell', (tester) async {
    await signInWithSmsCode(tester, isNewUser: true, isProfileComplete: true);
    expect(find.byType(MainShell), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets('a code read from the SMS fills the boxes and auto-submits', (tester) async {
    String? sentOtp;
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      if (path.endsWith('/auth/otp/verify')) {
        sentOtp = (jsonDecode(request.body) as Map<String, dynamic>)['otp'] as String?;
        return fail('Incorrect OTP.', 400);
      }
      return fail('not found', 404);
    });
    await openScreen(tester, sms: _FakeSmsAutofill(code: '482910'));
    await requestCode(tester);
    await settle(tester);
    expect(sentOtp, '482910');
    await closeScreen(tester);
  });

  // Regression: a returning user whose profile was never completed must go back to
  // onboarding, not to a Dashboard whose requireProfileComplete-gated tabs all fail.
  testWidgets('typing the code auto-submits; an incomplete profile goes to onboarding', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      if (path.endsWith('/auth/otp/verify')) {
        return ok({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'isNewUser': false,
          'user': {'id': 'user-1', 'phone': '9876543210', 'countryCode': '+91', 'isProfileComplete': false},
        });
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    await tester.enterText(codeField, '482910');
    await settle(tester);
    expect(find.byType(ProfileSetupScreen), findsOneWidget);
    expect(find.byType(Dashboard), findsNothing);
    await closeScreen(tester);
  });

  testWidgets('a wrong code is explained and the boxes are cleared for another try', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      if (path.endsWith('/auth/otp/verify')) return fail('Incorrect OTP.', 400);
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    await tester.enterText(codeField, '111111');
    await settle(tester);

    expect(find.textContaining("That code isn't right"), findsOneWidget);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
    expect(codeField, findsOneWidget, reason: 'still on the code step');
    await closeScreen(tester);
  });

  testWidgets('an expired code offers Resend straight away', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      if (path.endsWith('/auth/otp/verify')) {
        return fail('OTP not found or expired. Please request a new one.', 400);
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    await tester.enterText(codeField, '111111');
    await settle(tester);
    expect(find.textContaining('This code has expired'), findsOneWidget);
    expect(find.byKey(const Key('resend')), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets('Verify with an incomplete code asks for all six digits', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) return ok({'validitySeconds': 180});
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    await tester.enterText(codeField, '123');
    await tester.tap(verifyButton);
    await tester.pump();
    expect(find.text('Enter the 6-digit code from the SMS'), findsOneWidget);
    await closeScreen(tester);
  });

  // ── Changing the number ────────────────────────────────────────────────────

  testWidgets('Edit returns to the number (kept), clears the code, and a new number can be sent',
      (tester) async {
    final sentTo = <String>[];
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) {
        sentTo.add((jsonDecode(request.body) as Map<String, dynamic>)['phone'] as String);
        return ok({});
      }
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    await tester.enterText(codeField, '12');
    await tester.tap(find.byKey(const Key('edit-number')));
    await settle(tester);

    expect(codeField, findsNothing);
    expect(tester.widget<TextField>(phoneField).controller!.text, '9876543210');

    await tester.enterText(phoneField, '9876543211');
    await tester.tap(getOtp);
    await settle(tester);
    expect(sentTo, ['9876543210', '9876543211']);
    expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
    await closeScreen(tester);
  });

  testWidgets('system back on the code step returns to the number instead of leaving',
      (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/otp/request')) return ok({});
      return fail('not found', 404);
    });
    await openScreen(tester);
    await requestCode(tester);
    expect(codeField, findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(codeField, findsNothing);
    expect(phoneField, findsOneWidget);
    await closeScreen(tester);
  });

  // App Store guideline 1.2: users must actively agree to the Terms (which state the
  // no-tolerance policy) before registering or logging in.
  group('Terms agreement (guideline 1.2)', () {
    testWidgets('Get OTP does nothing until the Terms box is ticked', (tester) async {
      var otpRequests = 0;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/otp/request')) otpRequests++;
        return ok({});
      });

      await openScreen(tester);
      await tester.enterText(phoneField, '9876543210');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await tester.tap(getOtp);
      await tester.pump();
      expect(otpRequests, 0, reason: 'no OTP may be requested before the user agrees');
      expect(find.textContaining('agree to the Terms of Service'), findsWidgets);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(getOtp);
      await settle(tester);
      expect(otpRequests, 1, reason: 'ticking the box unlocks Get OTP');
      await closeScreen(tester);
    });

    testWidgets('the checkbox text states the no-tolerance policy and links the Terms and Privacy Policy',
        (tester) async {
      await openScreen(tester);
      final consent = find.byWidgetPredicate((w) =>
          w is RichText &&
          w.text.toPlainText().contains('no tolerance for objectionable content or abusive users'));
      expect(consent, findsOneWidget);
      final text = tester.widget<RichText>(consent).text.toPlainText();
      expect(text, contains('Terms of Service'));
      expect(text, contains('Privacy Policy'));
      await closeScreen(tester);
    });
  });

  testWidgets('fits a small 320 px-wide phone without overflow', (tester) async {
    ApiClient.httpClient = MockClient((request) async => ok({}));
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PhoneAuthScreen(smsAutofill: _FakeSmsAutofill())));
    await requestCode(tester);
    expect(tester.takeException(), isNull);
    expect(codeField, findsOneWidget);
    await closeScreen(tester);
  });
}
