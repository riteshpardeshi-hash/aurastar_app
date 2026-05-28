# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app (iOS simulator or connected device)
flutter run

# Build for iOS
flutter build ios

# Run static analysis
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get

# Clean build artifacts
flutter clean
```

## Architecture

The entire app lives in a single file: `lib/main.dart` (~4100 lines). There are no separate files, modules, or feature folders — all screens, widgets, and logic are co-located.

### Role system

User roles are stored as boolean flags on the Firestore `users` document:
- `isAdmin: false`, `isCreator: false` → regular user
- `isCreator: true` → brand (can create challenges, see brand screens)
- `isAdmin: true` → platform admin (can do everything; sees all panels)

`Dashboard` reads these flags via a real-time `StreamBuilder` and conditionally renders sections. The `isBrand` variable maps to `isCreator` in Firestore.

### Firestore collections

| Collection | Purpose |
|---|---|
| `users` | Profile, role flags (`isAdmin`, `isCreator`), `totalRewards` points |
| `challenges` | Approved challenges shown in the feed; `creatorId: 'system'` = platform challenges, otherwise brand UID |
| `submissions` | User video submissions; `status: pending/approved`; approval increments `totalRewards` on the user doc |
| `creator_requests` | Brand-submitted challenge proposals awaiting admin approval; on approve, a new doc is added to `challenges` |

### Auth flow

`main()` → `MyApp` checks `FirebaseAuth.instance.currentUser`:
- Not logged in → `AuthChoiceScreen` (email or phone)
- Logged in, no Firestore profile → `ProfileSetupScreen`
- Logged in, profile exists → `Dashboard`

Phone auth uses Firebase OTP. Email auth supports both sign-in and sign-up from the same `LoginScreen` (toggled by `isLogin` flag).

### Navigation

All navigation uses `Navigator.push` / `Navigator.pushReplacement` / `Navigator.pushAndRemoveUntil` with `MaterialPageRoute`. There is no named routing or go_router. The app has no bottom nav bar; all flows start from `Dashboard`.

### Video flows

Two parallel camera/preview/upload flows exist with nearly identical logic:
- **User submission**: `CameraScreen` → `PreviewScreen` → uploads to `submissions/` in Firebase Storage, creates `submissions` Firestore doc
- **Brand challenge creation**: `BrandCameraScreen` → `BrandPreviewScreen` → uploads to `creator_videos/` in Firebase Storage, creates `creator_requests` Firestore doc

`VideoPlayerWidget` handles remote URLs (network); `PreviewScreen` and `BrandPreviewScreen` use `VideoPlayerController.file` for local playback.

The global `cameras` list is populated in `main()` via `availableCameras()` and used by both camera screens.

### Key screens

- `Dashboard` — role-based hub; rendered via `StreamBuilder` on the user doc
- `CreatorAdminScreen` — brand's admin panel for reviewing their challenge's participant submissions (approving/rejecting with aura points)
- `AdminScreen` — platform admin panel with two tabs: user submissions and brand requests
- `LeaderboardScreen` — reads `users` collection ordered by `totalRewards`
- `ExploreCreatorsScreen` — lists distinct `creatorId`s from `challenges` collection (excluding `'system'`)
- `CreatorProfileScreen` — public brand profile with their live challenges
- `MyAccountScreen` — personal profile + submission history

## Firebase setup

The app uses `firebase_core`, `firebase_auth`, `cloud_firestore`, and `firebase_storage`. Firebase is initialized in `main()` with `Firebase.initializeApp()`. The iOS configuration is in `ios/GoogleService-Info.plist`. There is no `google-services.json` in the Android tree — Android Firebase setup may be incomplete.

## Design conventions

- Primary accent: `Color(0xFF7B2CBF)` (purple)
- Background gradients use `Colors.black.withValues(alpha: ...)` (use `withValues` not the deprecated `withOpacity`)
- Auth screens share the same full-bleed background image (`assets/images/power-music-concept-portrait (2).jpg`) with a dark gradient overlay
- `InputDecoration` helpers named `input(String hint)` are defined locally in each stateful screen (duplicated pattern)
