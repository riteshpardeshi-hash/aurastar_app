import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/auth_api_service.dart';
import 'package:aura_app/features/auth/phone_auth_controller.dart';

// Every rule of the two-step phone sign-in (phone → code), independent of the UI.
// Regression context (2026-10-19): a send whose answer was lost left the old screen on
// "Get OTP" while the SMS had arrived; the retry then hit the 60 s cooldown and the user
// was stuck with a valid code and no way to enter it.

OtpRequest sent({bool resent = true, String message = 'OTP sent successfully.'}) =>
    (validitySeconds: 180, expiresAt: null, resent: resent, message: message);

AuthResult signedIn() => (
      accessToken: 'a',
      refreshToken: 'r',
      user: <String, dynamic>{'id': 'u1', 'isProfileComplete': true},
      isNewUser: false,
      deletionCancelled: false,
    );

class _Backend {
  final requests = <String>[];
  final verifies = <String>[];
  Object? requestError;
  Object? verifyError;
  OtpRequest response = sent();
  Completer<OtpRequest>? pendingRequest;

  Future<OtpRequest> request(String phone) async {
    requests.add(phone);
    if (pendingRequest != null) return pendingRequest!.future;
    if (requestError != null) throw requestError!;
    return response;
  }

  Future<AuthResult> verify(String phone, String otp) async {
    verifies.add('$phone:$otp');
    if (verifyError != null) throw verifyError!;
    return signedIn();
  }
}

void main() {
  // HapticFeedback on a wrong code goes through a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Backend backend;
  late PhoneAuthController auth;

  setUp(() {
    backend = _Backend();
    auth = PhoneAuthController(requestOtp: backend.request, verifyOtp: backend.verify);
  });
  tearDown(() => auth.dispose());

  /// Phone entered, terms ticked, code requested successfully.
  Future<void> onCodeStep() async {
    auth.setPhone('9876543210');
    auth.setTermsAccepted(true);
    expect(await auth.sendOtp(), isTrue);
    expect(auth.step, PhoneAuthStep.otp);
  }

  group('phone number', () {
    test('normalises typed and pasted formats to the 10-digit number', () {
      expect(PhoneAuthController.normalizePhone('98765 43210'), '9876543210');
      expect(PhoneAuthController.normalizePhone('+91 98765-43210'), '9876543210');
      expect(PhoneAuthController.normalizePhone('+919876543210'), '9876543210');
      expect(PhoneAuthController.normalizePhone('919876543210'), '9876543210');
      expect(PhoneAuthController.normalizePhone('09876543210'), '9876543210');
      expect(PhoneAuthController.normalizePhone('98765432101234'), '9876543210');
      expect(PhoneAuthController.normalizePhone('abc'), '');
      // A 10-digit number that happens to start with 91 is left alone.
      expect(PhoneAuthController.normalizePhone('9123456789'), '9123456789');
    });

    test('accepts Indian mobile numbers (6-9 prefix) and the App Store review number', () {
      expect(PhoneAuthController.isValidPhone('9876543210'), isTrue);
      expect(PhoneAuthController.isValidPhone('6000000000'), isTrue);
      expect(PhoneAuthController.isValidPhone('5876543210'), isFalse);
      expect(PhoneAuthController.isValidPhone('987654321'), isFalse);
      expect(PhoneAuthController.isValidPhone(''), isFalse);
      // Apple's reviewers sign in with 1234567890 (backend appReviewTestAccount.js).
      expect(PhoneAuthController.isValidPhone(PhoneAuthController.reviewPhone), isTrue);
    });

    test('formats the number for display', () {
      expect(PhoneAuthController.formatPhone('9876543210'), '+91 98765 43210');
    });

    test('reads the wait time out of the backend cooldown and rate-limit messages', () {
      expect(PhoneAuthController.waitSecondsFrom('Please wait 25 seconds before requesting another OTP.'), 25);
      expect(PhoneAuthController.waitSecondsFrom('Please wait 1 second before requesting another OTP.'), 1);
      expect(
        PhoneAuthController.waitSecondsFrom(
            'Too many OTP requests. You can request at most 5 codes every 15 minutes. Try again in 300 seconds.'),
        300,
      );
      expect(PhoneAuthController.waitSecondsFrom('Incorrect OTP.'), isNull);
    });

    test('editing the number clears the previous error', () async {
      auth.setTermsAccepted(true);
      auth.setPhone('12345');
      await auth.sendOtp();
      expect(auth.phoneError, isNotNull);
      auth.setPhone('98765');
      expect(auth.phoneError, isNull);
    });
  });

  group('sending the code', () {
    test('nothing is sent until the Terms are accepted', () async {
      auth.setPhone('9876543210');
      expect(await auth.sendOtp(), isFalse);
      expect(backend.requests, isEmpty);
      expect(auth.termsError, isTrue);

      auth.setTermsAccepted(true);
      expect(auth.termsError, isFalse);
      expect(await auth.sendOtp(), isTrue);
      expect(backend.requests, ['9876543210']);
    });

    test('an invalid number is caught before any request', () async {
      auth.setTermsAccepted(true);
      auth.setPhone('5555');
      expect(await auth.sendOtp(), isFalse);
      expect(auth.phoneError, contains('valid 10-digit'));
      expect(backend.requests, isEmpty);
    });

    test('success moves to the code step with a fresh resend countdown', () async {
      await onCodeStep();
      expect(auth.resendIn, 60);
      expect(auth.canResend, isFalse);
      expect(auth.otpInfo, isNull);
    });

    test('a reused code says so (backend ADR 121) and still moves on', () async {
      backend.response = sent(
        resent: false,
        message: 'We already sent a code to this number. Please enter that code.',
      );
      await onCodeStep();
      expect(auth.otpInfo, contains('already sent a code'));
    });

    test('the cooldown 429 means a code was just sent: go and enter it (lost answer / app restart)', () async {
      backend.requestError = 'Please wait 25 seconds before requesting another OTP.';
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);

      expect(await auth.sendOtp(), isTrue);
      expect(auth.step, PhoneAuthStep.otp);
      expect(auth.resendIn, 25);
      expect(auth.otpInfo, contains('+91 98765 43210'));
    });

    test('a lost answer (network error) offers "I already have a code"', () async {
      backend.requestError = const SocketException('Connection reset');
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);

      expect(await auth.sendOtp(), isFalse);
      expect(auth.step, PhoneAuthStep.phone);
      expect(auth.phoneError, contains("Couldn't reach Aura's servers"));
      expect(auth.canEnterExistingCode, isTrue);

      auth.enterExistingCode();
      expect(auth.step, PhoneAuthStep.otp);
      expect(auth.resendIn, 0, reason: 'unknown when the code was sent, so resend is allowed');
    });

    test('a timeout behaves like a lost answer', () async {
      backend.requestError = TimeoutException('Future not completed', const Duration(seconds: 15));
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      await auth.sendOtp();
      expect(auth.phoneError, isNot(contains('TimeoutException')));
      expect(auth.canEnterExistingCode, isTrue);
    });

    test('the request cap shows the backend message and offers the code already received', () async {
      backend.requestError =
          'Too many OTP requests. You can request at most 5 codes every 15 minutes. Try again in 300 seconds.';
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      expect(await auth.sendOtp(), isFalse);
      expect(auth.phoneError, contains('Too many OTP requests'));
      expect(auth.canEnterExistingCode, isTrue);
    });

    test('any other error is shown as-is and does not offer code entry', () async {
      backend.requestError = 'Phone must be a valid phone number';
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      expect(await auth.sendOtp(), isFalse);
      expect(auth.phoneError, 'Phone must be a valid phone number');
      expect(auth.canEnterExistingCode, isFalse);
    });

    test('a second tap while sending sends nothing more', () async {
      backend.pendingRequest = Completer<OtpRequest>();
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      final first = auth.sendOtp();
      expect(auth.sending, isTrue);
      expect(await auth.sendOtp(), isFalse);
      backend.pendingRequest!.complete(sent());
      await first;
      expect(backend.requests, hasLength(1));
    });

    test('changing the number hides "I already have a code" (it was for the old number)', () async {
      backend.requestError = const SocketException('reset');
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      await auth.sendOtp();
      expect(auth.canEnterExistingCode, isTrue);
      auth.setPhone('9876543211');
      expect(auth.canEnterExistingCode, isFalse);
    });
  });

  group('the code step', () {
    test('Edit number goes back with the number kept and the countdown stopped', () async {
      await onCodeStep();
      final resets = auth.codeResetCount;
      auth.editNumber();
      expect(auth.step, PhoneAuthStep.phone);
      expect(auth.phone, '9876543210');
      expect(auth.resendIn, 0);
      expect(auth.codeResetCount, greaterThan(resets), reason: 'the typed code is cleared');
    });

    test('an incomplete code is not sent', () async {
      await onCodeStep();
      expect(await auth.verify('123'), isNull);
      expect(auth.otpError, contains('6-digit'));
      expect(backend.verifies, isEmpty);
    });

    test('a correct code signs in', () async {
      await onCodeStep();
      final result = await auth.verify('123456');
      expect(result, isNotNull);
      expect(backend.verifies, ['9876543210:123456']);
      expect(auth.otpError, isNull);
    });

    test('a wrong code clears the boxes, shakes and explains', () async {
      await onCodeStep();
      backend.verifyError = 'Incorrect OTP.';
      final resets = auth.codeResetCount;
      final shakes = auth.shakeCount;
      expect(await auth.verify('111111'), isNull);
      expect(auth.otpError, contains("isn't right"));
      expect(auth.codeResetCount, resets + 1);
      expect(auth.shakeCount, shakes + 1);
      expect(auth.resendIn, greaterThan(0), reason: 'a wrong code does not unlock resend early');
    });

    test('an expired code unlocks resend straight away', () async {
      await onCodeStep();
      backend.verifyError = 'OTP not found or expired. Please request a new one.';
      await auth.verify('111111');
      expect(auth.otpError, contains('expired'));
      expect(auth.resendIn, 0);
      expect(auth.canResend, isTrue);
    });

    test('too many wrong attempts asks for a new code and unlocks resend', () async {
      await onCodeStep();
      backend.verifyError = 'Too many incorrect attempts. Please request a new OTP.';
      await auth.verify('111111');
      expect(auth.otpError, contains('Too many wrong attempts'));
      expect(auth.canResend, isTrue);
    });

    test('a network error keeps the code so it can simply be retried', () async {
      await onCodeStep();
      backend.verifyError = const SocketException('Network is unreachable');
      final resets = auth.codeResetCount;
      await auth.verify('123456');
      expect(auth.otpError, contains("Couldn't reach Aura's servers"));
      expect(auth.codeResetCount, resets, reason: 'the code is not cleared');

      backend.verifyError = null;
      expect(await auth.verify('123456'), isNotNull);
    });

    test('a code can only be verified on the code step', () async {
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      expect(await auth.verify('123456'), isNull);
      expect(backend.verifies, isEmpty);
    });

    test('typing again clears the error', () async {
      await onCodeStep();
      backend.verifyError = 'Incorrect OTP.';
      await auth.verify('111111');
      auth.clearOtpError();
      expect(auth.otpError, isNull);
    });
  });

  group('resend', () {
    testWidgets('counts down every second, then allows a resend', (tester) async {
      await onCodeStep();
      expect(auth.resendIn, 60);
      await tester.pump(const Duration(seconds: 1));
      expect(auth.resendIn, 59);
      await tester.pump(const Duration(seconds: 59));
      expect(auth.resendIn, 0);
      expect(auth.canResend, isTrue);
      auth.dispose();
      auth = PhoneAuthController(requestOtp: backend.request, verifyOtp: backend.verify);
    });

    testWidgets('resend sends a new code, clears the boxes and restarts the countdown', (tester) async {
      backend.requestError = 'Please wait 2 seconds before requesting another OTP.';
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      await auth.sendOtp();
      await tester.pump(const Duration(seconds: 2));
      expect(auth.canResend, isTrue);

      backend.requestError = null;
      final resets = auth.codeResetCount;
      await auth.resend();
      expect(backend.requests, hasLength(2));
      expect(auth.otpInfo, contains('new code is on its way'));
      expect(auth.codeResetCount, resets + 1);
      expect(auth.resendIn, 60);
      auth.dispose();
      auth = PhoneAuthController(requestOtp: backend.request, verifyOtp: backend.verify);
    });

    test('resend is ignored during the countdown', () async {
      await onCodeStep();
      await auth.resend();
      expect(backend.requests, hasLength(1));
    });

    test('a resend refused by the cooldown shows why and restarts the countdown', () async {
      auth.setPhone('9876543210');
      auth.setTermsAccepted(true);
      auth.enterExistingCode();
      backend.requestError = 'Please wait 40 seconds before requesting another OTP.';
      await auth.resend();
      expect(auth.otpError, contains('Please wait 40 seconds'));
      expect(auth.resendIn, 40);
    });
  });

  test('nothing is notified after dispose (no setState on a closed screen)', () async {
    final local = PhoneAuthController(requestOtp: backend.request, verifyOtp: backend.verify);
    backend.pendingRequest = Completer<OtpRequest>();
    local.setPhone('9876543210');
    local.setTermsAccepted(true);
    final pending = local.sendOtp();
    local.dispose();
    backend.pendingRequest!.complete(sent());
    expect(await pending, isFalse);
  });
}
