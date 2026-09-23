# 029 — Report crashes with Firebase Crashlytics

Status: Accepted (builds on 028)

## Problem

Crashes were only learned about from testers. The "stuck on boot" report
could not be reproduced under adb (remote tester, no USB access), and there
was no way to see the actual error. The analytics tracking plan (AD-43) also
asks for crash-free-users and ANR rates.

## Decision

Add `firebase_crashlytics` on the same Firebase project as analytics (022).

- `CrashReporter` (`lib/core/services/crash_reporter.dart`) wraps it, never
  throws, and no-ops when Firebase isn't initialised (same contract as
  `AnalyticsService`). `main()` calls `CrashReporter.init()` right after
  `Firebase.initializeApp` succeeds. It routes `FlutterError.onError`
  (fatal, console output kept) and `PlatformDispatcher.onError` (fatal,
  printed to the debug console because returning `true` would otherwise
  silence it) to Crashlytics. Collection is off in debug builds.
- User id: the same opaque backend id as analytics, set from
  `AnalyticsService.setUserId` (login, cold start, logout clears it). No
  phone number or name.
- Breadcrumbs: `AnalyticsService.logScreen` also adds `screen: <name>`.
- Handled errors worth seeing: the boot destination failure (the "stuck on
  boot" class) and unexpected upload failures — anything that isn't a
  network error or a server-worded rejection.
- Android: `com.google.firebase.crashlytics` Gradle plugin (uploads the R8
  mapping on release builds).
- iOS: a Codemagic step uploads the dSYMs after the IPA build for the
  production workflow only. It is `ignore_failure`: a failed upload just
  leaves that release's iOS stack traces unsymbolicated. The Xcode project is
  not modified.
- A "Send test crash (Crashlytics)" tile in Settings → Debug is shown in
  debug builds, or in release builds compiled with
  `--dart-define=CRASH_TEST=true`, so it never reaches real users.

## Consequences

- The prototype iOS workflow has no Firebase app registered for
  `...auraapp.prototype` (see 028), so its crashes aren't reported and its
  dSYMs aren't uploaded.
- Reports arrive after the app is relaunched, roughly a minute later.
- The privacy policy and store data-safety forms must mention crash
  reporting alongside analytics.
- Uncaught async errors are now marked handled, matching how release builds
  already treated them (logged, app keeps running), and are also reported.

## Verification

`test/core/services/crash_reporter_test.dart`: every entry point swallows the
uninitialised-Firebase error and `init` leaves `FlutterError.onError`
untouched when Firebase isn't available. Live check: build a release with
`--dart-define=CRASH_TEST=true`, tap the test-crash tile, relaunch, and
confirm the crash appears in Firebase console → Crashlytics.
