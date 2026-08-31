import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aura_app/core/services/api_client.dart';
import 'package:aura_app/core/services/sms_otp_autofill.dart';
import 'package:aura_app/features/auth/screens/phone_auth_screen.dart';

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
    await tester.tap(find.text('Get OTP'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Please wait 58 seconds'), findsOneWidget);
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
}
