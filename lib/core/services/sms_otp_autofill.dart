import 'dart:async';
import 'dart:io';

import 'package:smart_auth/smart_auth.dart';

/// Auto-reads the 6-digit login OTP out of the incoming Message Central SMS so
/// the user never has to type it (ADR 004).
///
/// Two Google Play services APIs are started together and whichever produces a
/// code first wins:
///
/// * **SMS Retriever API** — fully seamless, no user interaction. Only fires
///   when the SMS body ends with this app's 11-char signature hash, which
///   Message Central has to append in its template. Until that template change
///   lands it simply never fires, and the User Consent path below covers it.
/// * **SMS User Consent API** — shows a one-tap system dialog ("Allow this app
///   to read the message?"), then hands over the body to extract the code.
///   Needs no app hash and no backend coordination, so it is the path that
///   actually works today.
///
/// Neither API needs an SMS permission. Android only — on iOS there is no
/// SMS-read API (the OS surfaces the code through the keyboard's QuickType bar
/// instead, wired via [AutofillHints.oneTimeCode] on the field), so every
/// method here is a no-op and [waitForCode] resolves to `null` immediately.
class SmsOtpAutofill {
  SmsOtpAutofill({SmartAuth? smartAuth})
      : _smartAuth = smartAuth ?? SmartAuth.instance;

  final SmartAuth _smartAuth;

  /// The backend OTP is always exactly 6 digits (`^\d{6}$` in the OpenAPI
  /// spec), so constrain extraction rather than using the package default of
  /// `\d{4,8}` which could latch onto an unrelated number in the message.
  static const _codeMatcher = r'\d{6}';

  bool _cancelled = false;

  /// Starts both listeners and completes with the first 6-digit code read from
  /// an SMS, or `null` if listening was cancelled, timed out, or the platform
  /// has no SMS-read API. Safe to call again after [cancel] — each call starts
  /// a fresh listen.
  Future<String?> waitForCode() {
    if (!Platform.isAndroid) return Future.value(null);
    _cancelled = false;
    final completer = Completer<String?>();

    void deliver(String? code) {
      if (_cancelled || completer.isCompleted) return;
      if (code == null || code.length != 6) return;
      completer.complete(code);
    }

    _smartAuth
        .getSmsWithRetrieverApi(matcher: _codeMatcher)
        .then((r) => deliver(r.hasData ? r.requireData.code : null))
        .catchError((_) {});
    _smartAuth
        .getSmsWithUserConsentApi(matcher: _codeMatcher)
        .then((r) => deliver(r.hasData ? r.requireData.code : null))
        .catchError((_) {});

    return completer.future;
  }

  /// Stops both listeners. Call when leaving the screen or once the code has
  /// been consumed so a later unrelated SMS can't trigger the consent dialog.
  void cancel() {
    _cancelled = true;
    if (!Platform.isAndroid) return;
    _smartAuth.removeSmsRetrieverApiListener();
    _smartAuth.removeUserConsentApiListener();
  }
}
