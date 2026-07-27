import 'dart:async';

/// Signals that `SplashScreen`'s own post-boot navigation (its
/// `pushReplacement` to Dashboard/ProfileSetup/PhoneAuth, fired once the
/// onboarding carousel or fast-boot check finishes) has happened.
///
/// `Navigator.pushReplacement` always replaces whichever route currently
/// sits on top of the stack — not specifically Splash's own route. So if a
/// challenge deep link resolved and pushed its screen while Splash was still
/// showing, Splash's later `pushReplacement` would silently discard it.
/// Deep-link handling awaits [done] before pushing, so it always lands after
/// Splash's own navigation instead of racing it.
class SplashGate {
  static Completer<void> _completer = Completer<void>();

  static Future<void> get done => _completer.future;

  static void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Test-only: the app boots once per process, so production code never
  /// needs to reset this.
  static void resetForTest() => _completer = Completer<void>();
}
