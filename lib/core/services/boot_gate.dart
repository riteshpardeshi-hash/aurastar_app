import 'dart:async';

/// Signals that the app's initial boot routing (main.dart's `_BootScreen`
/// deciding Dashboard/ProfileSetup/PhoneAuth and firing its
/// `pushReplacement`, once login-state/version checks resolve) has happened.
///
/// `Navigator.pushReplacement` always replaces whichever route currently
/// sits on top of the stack — not specifically the boot screen's own route.
/// So if a challenge deep link resolved and pushed its screen while the boot
/// screen was still showing, its later `pushReplacement` would silently
/// discard it. Deep-link handling awaits [done] before pushing, so it always
/// lands after the boot screen's own navigation instead of racing it.
class BootGate {
  static Completer<void> _completer = Completer<void>();

  static Future<void> get done => _completer.future;

  static void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Test-only: the app boots once per process, so production code never
  /// needs to reset this.
  static void resetForTest() => _completer = Completer<void>();
}
