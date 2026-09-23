import 'package:aura_app/core/services/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never throws when Firebase is not initialised', () async {
    // Unit tests never call Firebase.initializeApp: every entry point must
    // swallow the resulting error instead of breaking the caller.
    await CrashReporter.init();
    await CrashReporter.setUserId('u1');
    await CrashReporter.setUserId(null);
    CrashReporter.log('breadcrumb');
    await CrashReporter.recordError(StateError('x'), StackTrace.current,
        reason: 'test');
    CrashReporter.testCrash();
  });

  test('init leaves FlutterError.onError set without throwing', () async {
    final before = FlutterError.onError;
    await CrashReporter.init();
    // Firebase isn't available here, so init bails out before replacing it.
    expect(FlutterError.onError, before);
  });
}
