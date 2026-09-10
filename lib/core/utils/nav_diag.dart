import 'package:flutter/foundation.dart';

/// TEMPORARY diagnostic logging for the "bottom-nav tabs do nothing on some
/// phones" report. Traces the full tap -> switch chain:
///
///   AppBottomNav._switchTab  (tap landed, early-return?, popUntil, route depth)
///     -> MainShellController.select  (index valid?, has a listener?)
///       -> MainShell._selectTab  (event received, index, setState ran?)
///
/// Run a build with this on, reproduce on the failing device, then:
///   adb logcat -s flutter | grep navdiag        (Android)
///   idevicesyslog | grep navdiag                (iOS)
///
/// Remove this file and its call sites (grep `navDiag`) once the broken link
/// is identified. Flip [kNavDiag] to false to silence without unwiring.
const bool kNavDiag = true;

void navDiag(String msg) {
  if (!kNavDiag) return;
  // debugPrint (not print) so it survives release/profile builds and is
  // rate-limit friendly.
  debugPrint('[navdiag] ${DateTime.now().toIso8601String()} $msg');
}
