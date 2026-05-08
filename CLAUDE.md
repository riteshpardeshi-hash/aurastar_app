# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                 # install deps
flutter run                     # run on default device
flutter run -d chrome           # run web build
flutter analyze                 # lint (uses analysis_options.yaml -> flutter_lints)
flutter test                    # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter test --name "<substr>"       # run a single test by name
flutter build apk | ios | web   # release builds
```

The pubspec name is `aura_app` (the repo dir is `aurastar_app`). Test imports use `package:aura_app/...`.

## Architecture

This is a single-file Flutter app: **all UI, state, and Firebase access live in `lib/main.dart`** (~3400 lines, ~30 widget classes). There is no routing layer, no service layer, no models, and no state management library — screens navigate via `Navigator.push(MaterialPageRoute(...))` and read/write Firestore directly inside `StatefulWidget`s and `StreamBuilder`s.

When adding features, follow the existing convention (more classes appended to `main.dart`) unless the user asks to refactor. Section banners (`////////` comment blocks) delimit screen groups in the file.

### Backend (Firebase)
- `Firebase.initializeApp()` is called in `main()` with no options object — relies on platform config files (`android/app/google-services.json`, iOS `GoogleService-Info.plist`). There is no generated `firebase_options.dart`.
- **Firestore collections in use:** `users`, `challenges`, `submissions`, `creator_requests`.
- Auth is `FirebaseAuth` email/password. The root widget branches on `FirebaseAuth.instance.currentUser` to choose `LoginScreen` vs `Dashboard`.
- Video uploads go through `firebase_storage`; playback uses `video_player`.

### User roles (encoded in Firestore, not in types)
The app has three implicit roles, gated by fields on the user doc and by separate screens:
- **Regular user** — `Dashboard`, `ExploreCreatorsScreen`, `ChallengeDetail`, `CameraScreen` → `PreviewScreen` (records & submits to `submissions`).
- **Creator** — applies via `creator_requests`, then uses `CreatorHomeScreen`, `CreateChallenge`, `CreatorVideoRecorderScreen`.
- **Admin** — `AdminScreen` reviews `submissions` and `creator_requests` via `SubmissionTab`, `CreatorRequestTab`, `CreatorReviewScreen`.

When changing role-gated behavior, search for the relevant collection name and `currentUser!.uid` lookups — there is no central role guard.

### Camera flow
`CameraScreen` uses the top-level `cameras` list populated in `main()` from `availableCameras()`. New camera screens should reuse this global rather than calling `availableCameras()` again.

## Tests

`test/widget_test.dart` is still the Flutter starter counter test and **does not match `MyApp`** (which now boots into Firebase + auth). Expect it to fail; rewrite it before relying on `flutter test` as a gate, or skip it explicitly.
