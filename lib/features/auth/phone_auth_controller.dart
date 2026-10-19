import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_api_service.dart';
import '../../core/utils/error_message.dart';

/// The two steps of phone sign-in. The code can only be entered on [otp], so a
/// typed code can never sit next to a "Get OTP" button again (the 2026-10-19
/// bug: a send whose answer was lost left the screen on "Get OTP" while the
/// SMS had arrived).
enum PhoneAuthStep { phone, otp }

/// State and rules for phone + OTP sign-in, kept out of the widget so every
/// edge case is unit-testable. The screen renders it and reacts to
/// [PhoneAuthController.codeResetCount] / [shakeCount].
class PhoneAuthController extends ChangeNotifier {
  PhoneAuthController({
    required Future<OtpRequest> Function(String phone) requestOtp,
    required Future<AuthResult> Function(String phone, String otp) verifyOtp,
    this.resendCooldownSeconds = 60,
  })  : _requestOtp = requestOtp,
        _verifyOtp = verifyOtp;

  final Future<OtpRequest> Function(String phone) _requestOtp;
  final Future<AuthResult> Function(String phone, String otp) _verifyOtp;

  /// Matches the backend's default `otp.resend_cooldown_seconds` (ADR 080).
  /// The backend enforces its own cooldown; this only keeps the button from
  /// offering a resend it would reject.
  final int resendCooldownSeconds;

  /// The App Store review account (backend `appReviewTestAccount.js`). It isn't
  /// a real mobile number, so it is allowed past the 6–9 prefix rule.
  static const reviewPhone = '1234567890';

  static const termsMessage =
      'Please agree to the Terms of Service and Privacy Policy to continue.';

  PhoneAuthStep _step = PhoneAuthStep.phone;
  String _phone = '';
  bool _termsAccepted = false;
  bool _sending = false;
  bool _verifying = false;
  String? _phoneError;
  bool _termsError = false;
  String? _otpError;
  String? _otpInfo;
  bool _canEnterExistingCode = false;
  int _resendIn = 0;
  int _codeResetCount = 0;
  int _shakeCount = 0;
  bool _disposed = false;
  Timer? _resendTimer;

  PhoneAuthStep get step => _step;
  String get phone => _phone;
  bool get termsAccepted => _termsAccepted;
  bool get sending => _sending;
  bool get verifying => _verifying;
  bool get busy => _sending || _verifying;
  String? get phoneError => _phoneError;
  bool get termsError => _termsError;
  String? get otpError => _otpError;
  String? get otpInfo => _otpInfo;
  int get resendIn => _resendIn;
  bool get canResend => _resendIn <= 0 && !busy;

  /// True after a send failed in a way where the SMS may still have gone out
  /// (lost answer, rate limit) — the phone step then offers "I already have a
  /// code".
  bool get canEnterExistingCode => _canEnterExistingCode;

  /// Bumped whenever the code boxes must be emptied (new code, wrong code).
  int get codeResetCount => _codeResetCount;

  /// Bumped whenever the code boxes should shake (wrong / expired code).
  int get shakeCount => _shakeCount;

  bool get phoneValid => isValidPhone(_phone);

  /// "+91 98765 43210" for display.
  String get displayPhone => formatPhone(_phone);

  // ─── Pure helpers ────────────────────────────────────────────────────────

  static bool isValidPhone(String phone) =>
      phone == reviewPhone || RegExp(r'^[6-9]\d{9}$').hasMatch(phone);

  /// Reduces whatever was typed or pasted ("+91 98765-43210", "098765 43210")
  /// to the 10-digit national number, keeping at most 10 digits.
  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10 && digits.startsWith('91') && raw.contains('+')) {
      digits = digits.substring(2);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  static String formatPhone(String phone) =>
      phone.length == 10 ? '+91 ${phone.substring(0, 5)} ${phone.substring(5)}' : '+91 $phone';

  /// The seconds in the backend's cooldown / rate-limit messages ("Please wait
  /// 25 seconds…", "Try again in 300 seconds."), or null.
  static int? waitSecondsFrom(String message) {
    final match = RegExp(r'(?:wait|in) (\d+) seconds?', caseSensitive: false).firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // ─── Phone step ──────────────────────────────────────────────────────────

  void setPhone(String raw) {
    final next = normalizePhone(raw);
    if (next == _phone && _phoneError == null) return;
    _phone = next;
    _phoneError = null;
    _canEnterExistingCode = false;
    _notify();
  }

  void setTermsAccepted(bool value) {
    _termsAccepted = value;
    if (value) _termsError = false;
    _notify();
  }

  /// Returns true when the screen moved to the code step.
  Future<bool> sendOtp() async {
    if (busy) return false;
    if (!_termsAccepted) {
      _termsError = true;
      _notify();
      return false;
    }
    if (!phoneValid) {
      _phoneError = 'Enter a valid 10-digit mobile number';
      _notify();
      return false;
    }
    _sending = true;
    _phoneError = null;
    _canEnterExistingCode = false;
    _notify();
    try {
      final sent = await _requestOtp(_phone);
      if (_disposed) return false;
      _sending = false;
      // Inside Message Central's own timer no new SMS goes out (backend ADR
      // 121) — say so rather than claim a fresh code is on its way.
      _goToCode(info: sent.resent ? null : sent.message, cooldown: resendCooldownSeconds);
      return true;
    } catch (e) {
      if (_disposed) return false;
      _sending = false;
      final message = humanizeError(e);
      final wait = waitSecondsFrom(message);
      if (wait != null && message.toLowerCase().contains('please wait')) {
        // The resend cooldown only applies when a live code was sent to this
        // number moments ago (the previous answer was lost, or the app
        // restarted) — so go and enter it.
        _goToCode(
          info: 'We already sent a code to $displayPhone. Enter it below.',
          cooldown: wait,
        );
        return true;
      }
      _phoneError = message;
      // The SMS may still have arrived: a lost answer or a request cap after
      // earlier sends.
      _canEnterExistingCode = isNetworkError(e) || wait != null;
      _notify();
      return false;
    }
  }

  /// "I already have a code" after a send whose outcome is unknown.
  void enterExistingCode() {
    if (!phoneValid) return;
    _goToCode(info: 'Enter the code we sent to $displayPhone.', cooldown: 0);
  }

  /// Back to the phone step ("Edit number" / system back). The number is kept.
  void editNumber() {
    if (_verifying) return;
    _resendTimer?.cancel();
    _resendIn = 0;
    _step = PhoneAuthStep.phone;
    _otpError = null;
    _otpInfo = null;
    _codeResetCount++;
    _notify();
  }

  // ─── Code step ───────────────────────────────────────────────────────────

  void clearOtpError() {
    if (_otpError == null) return;
    _otpError = null;
    _notify();
  }

  /// Returns the signed-in result, or null with [otpError] set.
  Future<AuthResult?> verify(String code) async {
    if (busy || _step != PhoneAuthStep.otp) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _otpError = 'Enter the 6-digit code from the SMS';
      _notify();
      return null;
    }
    if (!_termsAccepted) {
      _otpError = termsMessage;
      _notify();
      return null;
    }
    _verifying = true;
    _otpError = null;
    _notify();
    try {
      final result = await _verifyOtp(_phone, code);
      if (_disposed) return result;
      _verifying = false;
      _resendTimer?.cancel();
      _notify();
      return result;
    } catch (e) {
      if (_disposed) return null;
      _verifying = false;
      final raw = humanizeError(e);
      final lower = raw.toLowerCase();
      if (isNetworkError(e)) {
        // Keep the code so the creator can simply retry.
        _otpError = raw;
      } else if (lower.contains('too many')) {
        _otpError = 'Too many wrong attempts. Request a new code.';
        _resendNowAllowed();
        _resetCode(shake: true);
      } else if (lower.contains('expired') || lower.contains('not found')) {
        _otpError = 'This code has expired. Request a new one.';
        _resendNowAllowed();
        _resetCode(shake: true);
      } else if (lower.contains('incorrect')) {
        _otpError = 'That code isn\'t right. Check the SMS and try again.';
        _resetCode(shake: true);
      } else {
        _otpError = raw;
      }
      _notify();
      return null;
    }
  }

  Future<void> resend() async {
    if (!canResend || _step != PhoneAuthStep.otp) return;
    _sending = true;
    _otpError = null;
    _notify();
    try {
      final sent = await _requestOtp(_phone);
      if (_disposed) return;
      _sending = false;
      _otpInfo = sent.resent ? 'A new code is on its way to $displayPhone.' : sent.message;
      _resetCode(shake: false);
      _startCooldown(resendCooldownSeconds);
    } catch (e) {
      if (_disposed) return;
      _sending = false;
      final message = humanizeError(e);
      _otpError = message;
      final wait = waitSecondsFrom(message);
      if (wait != null) _startCooldown(wait);
    }
    _notify();
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  void _goToCode({required String? info, required int cooldown}) {
    _step = PhoneAuthStep.otp;
    _otpInfo = info;
    _otpError = null;
    _resetCode(shake: false);
    _startCooldown(cooldown);
    _notify();
  }

  void _resetCode({required bool shake}) {
    _codeResetCount++;
    if (shake) {
      _shakeCount++;
      HapticFeedback.mediumImpact();
    }
  }

  void _resendNowAllowed() {
    _resendTimer?.cancel();
    _resendIn = 0;
  }

  void _startCooldown(int seconds) {
    _resendTimer?.cancel();
    _resendIn = seconds;
    if (seconds <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _resendIn -= 1;
      if (_resendIn <= 0) {
        _resendIn = 0;
        t.cancel();
      }
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resendTimer?.cancel();
    super.dispose();
  }
}
