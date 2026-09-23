import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over Firebase Crashlytics.
///
/// Like [AnalyticsService] it never throws: crash reporting must not be able
/// to break the app, and Firebase may legitimately be uninitialised (the boot
/// `Firebase.initializeApp` is bounded by a timeout and its failure is
/// swallowed; unit tests never initialise it). See ADR 029.
///
/// Reports are only collected in release/profile builds — debug builds are
/// noisy and would bury real crashes.
class CrashReporter {
  CrashReporter._();

  /// Enables collection and routes uncaught errors to Crashlytics. Call once,
  /// right after `Firebase.initializeApp` succeeds.
  static Future<void> init() async {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

      // Framework errors (build/layout/paint/gesture): keep the default
      // console output, then also report as fatal.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        crashlytics.recordFlutterFatalError(details);
      };

      // Errors thrown outside the framework (async gaps, timers, isolates
      // callbacks). Returning true marks them handled, matching how release
      // builds already treat uncaught async errors (logged, app keeps
      // running) — they are now also reported.
      PlatformDispatcher.instance.onError = (error, stack) {
        // Handled = true also silences the console, so print it ourselves.
        debugPrint('Uncaught error: $error\n$stack');
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('CrashReporter init failed: $e');
    }
  }

  /// Opaque backend user id only — no phone number or name. Null clears it.
  static Future<void> setUserId(String? id) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(id ?? '');
    } catch (_) {}
  }

  /// A breadcrumb attached to the next report (e.g. the current screen).
  static void log(String message) {
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
  }

  /// A handled error worth seeing in the console (does not crash the app).
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason);
    } catch (_) {}
  }

  /// Forces a native crash so the pipeline can be verified end to end.
  static void testCrash() {
    try {
      FirebaseCrashlytics.instance.crash();
    } catch (_) {}
  }
}
