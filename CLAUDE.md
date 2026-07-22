# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Flutter app (`lib/`)

```bash
flutter run               # Run on iOS simulator or connected device
flutter build ios         # Build for iOS
flutter analyze           # Static analysis (lint rules in analysis_options.yaml)
flutter test              # Run all tests
flutter test test/widget_test.dart   # Run a single test file
flutter pub get           # Get dependencies
flutter clean             # Clean build artifacts
```

### Cloud Functions (`functions/`)

```bash
cd functions
npm run serve             # firebase emulators:start --only functions
npm run deploy            # firebase deploy --only functions
npm run logs              # firebase functions:log

# One-time backfill: generate AI scoring checklists for existing challenges
GEMINI_API_KEY=<key> SERVICE_ACCOUNT=../serviceAccount.json node backfill_rubrics.js [--force]
```

The functions need the `GEMINI_API_KEY` param set (via `firebase functions:config` / `.env` for params). Runtime is Node 20.

## Architecture

Two halves: a **Flutter client** (`lib/`) and a **Firebase backend** (Firestore + Storage + Cloud Functions in `functions/`). The client never scores submissions — it uploads videos and writes Firestore docs; Cloud Functions do all AI scoring asynchronously.

### Client structure (`lib/`)

Feature-first layout (this was previously one ~4100-line `main.dart`; it has been split):

- `main.dart` — bootstrap only: `Firebase.initializeApp`, `availableCameras()`, deep-link handling, shows `SplashScreen`.
- `core/globals.dart` — global `cameras` list, populated in `main()`, used by both camera screens.
- `core/models/aura_tier.dart` — 6 reward tiers keyed by level; `auraTierForLevel()` / `nextAuraTier()` helpers.
- `features/<name>/screens|widgets/` — each feature (auth, splash, dashboard, home, challenges, creator, admin, explore, search, account, leaderboard, notifications, video).
- `shared/widgets/` — cross-feature widgets (wallet, level-up sheet, level rewards, follow button, aura action sheet, video thumbnail).
- `core/utils/cdn_url.dart`, `core/services/video_cache_service.dart` — video-delivery scaffolding. CDN base is currently empty and 480p/thumbnail variants are commented out, so `toCdnUrl`/`toOptimizedVideoUrl` are pass-throughs today; `VideoCacheService` just tracks recently-viewed URLs in `SharedPreferences`.

### Auth & navigation flow

`SplashScreen` runs an animated intro, then `pushReplacement` to either `Dashboard` (if `FirebaseAuth.currentUser != null`) or `AuthChoiceScreen`. Profile setup happens via `ProfileSetupScreen` for logged-in users without a Firestore profile. Phone auth uses Firebase OTP; email auth handles both sign-in and sign-up from `LoginScreen` (toggled by `isLogin`).

All navigation is imperative `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` with `MaterialPageRoute` — no named routing or go_router. `Dashboard` is the hub and has a custom bottom nav (Home / Challenges / Leaderboard / Profile + center FAB to the community feed).

### Deep linking (`main.dart`)

Uses `app_links`. Inbound URLs of the form `/challenge/{challengeId}` (cold-start and warm) are looked up in Firestore and open `ChallengeDetail` via a top-level `navigatorKey`. `firebase.json` configures Firebase Hosting to rewrite `/challenge/**` and serve `apple-app-site-association` for iOS universal links.

### Role system

Roles are boolean flags on the Firestore `users` doc:
- `isAdmin: false, isCreator: false` → regular user
- `isCreator: true` → brand (sees Brand Tools, can create challenges)
- `isAdmin: true` → platform admin (sees everything)

`Dashboard` reads these via a real-time `StreamBuilder` on the user doc and conditionally renders sections. The local `isBrand` variable maps to `isCreator` in Firestore.

### Leveling & Aura

Points live in `totalRewards` on the user doc. Level = `totalRewards ~/ 1300 + 1` (`_xpPerLevel` in `dashboard.dart`). Crossing a tier boundary triggers `LevelUpSheet`. Tiers/unlocks defined in `core/models/aura_tier.dart`.

## Backend: AI scoring pipeline (`functions/index.js`)

Two Firestore `onDocumentCreated` triggers, both using **Gemini 2.5 Flash** with the video Files API:

1. **`generateScoringRubric`** (on `challenges/{id}` create): downloads the challenge's reference `videoUrl`, has Gemini watch it, and writes back `aiScoringChecklist` (strict YES/NO questions) and `aiScoringPrompt` to the challenge doc.

2. **`scoreSubmission`** (on `submissions/{id}` create): scores the user's video against the challenge. Three paths, in priority order:
   - **Manual prompt** — if `challenge.aiScoringPrompt` exists, send it as-is with reference + user video; flexibly extract `score`/`total_score` and `short_feedback`.
   - **Checklist** — if `challenge.aiScoringChecklist` exists, Gemini answers YES/NO per question; **score is computed in code** (`yesCount / total * 100`) so the AI cannot inflate it.
   - **Fallback** — direct reference-vs-submission comparison.

   Score is clamped 0–100; `approved = score >= 10`; `auraPoints = score` when approved. Results (`status`, `aiScore`, `aiReason`, `auraPoints`, etc.) are written back to the submission doc.

3. **Daily valid score limit** (`applyDailyScoreLimit`): only the top N approved scores per day count toward Auras (N = `user.dailyValidScoreLimit`, default 3). A better score replaces the day's lowest counted score (with a negative `auraTransactions` entry); `totalRewards` is incremented by the net. Requires a composite index on `submissions`: `userId ASC, isCountedForDailyAuras ASC, createdAt ASC`.

`auraTransactions` is an append-only ledger of every Aura change (`challenge_score`, `daily_score_replacement`).

### Firestore collections

| Collection | Purpose |
|---|---|
| `users` | Profile, role flags (`isAdmin`, `isCreator`), `totalRewards` points, `dailyValidScoreLimit` |
| `challenges` | Approved challenges in the feed; `creatorId: 'system'` = platform, else brand UID. Holds AI rubric fields (`aiScoringChecklist`, `aiScoringPrompt`) |
| `submissions` | User videos; AI-scored (`status: approved/rejected/ai_error`, `aiScore`, `auraPoints`, `isCountedForDailyAuras`) |
| `creator_requests` | Brand challenge proposals awaiting admin approval; on approve a `challenges` doc is created (which triggers `generateScoringRubric`) |
| `auraTransactions` | Append-only Aura ledger |
| `achievement_cards` | Achievement card definitions |

### Video flows (two near-identical pipelines)

- **User submission**: `CameraScreen` → `PreviewScreen` → uploads to Storage `submissions/`, creates a `submissions` doc (which fires `scoreSubmission`).
- **Brand challenge creation**: `BrandCameraScreen` → `BrandPreviewScreen` → uploads to Storage `creator_videos/`, creates a `creator_requests` doc.

`VideoPlayerWidget` plays remote URLs (network); the preview screens use `VideoPlayerController.file` for local playback.

## Firebase setup

Uses `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`. Client config is generated in `lib/firebase_options.dart`; iOS config in `ios/GoogleService-Info.plist`. There is no `google-services.json` in the Android tree — Android Firebase setup may be incomplete. Hosting/functions config is in `firebase.json`.

## Design conventions

- Primary accent: `Color(0xFF7B2CBF)` (purple); dark background `Color(0xFF080810)`.
- Use `Colors.x.withValues(alpha: ...)` — **not** the deprecated `withOpacity`.
- Auth screens share a full-bleed background image with a dark gradient overlay.
- `InputDecoration` helpers named `input(String hint)` are defined locally per stateful screen (a duplicated pattern).

## Engineering standards

These apply to every change, not just ones Claude Code makes:

- **Root cause over symptom patch.** A retry/try-catch that silences a
  failure is not a fix until you can state *why* the failure happens. If you
  can't explain it in one sentence, keep digging before shipping.
- **Every bug fix ships with a regression test.** The test should fail
  against the pre-fix code and pass against the post-fix code — verify this
  by temporarily reverting the fix and confirming the test actually catches
  it, not just that it's green.
- **Non-trivial decisions get an ADR** in `docs/decisions/` — see that
  folder's `README.md` for when one is warranted and the template to use.
  This mirrors the backend team's own ADR convention.
- **Ground claims in the spec, not assumption.** When behavior depends on
  the backend (status codes, token lifetimes, response shapes), check the
  live OpenAPI spec (`http://144.91.79.237:3786/docs/openapi.yaml`, or the
  Scalar UI at `/docs`) rather than guessing from client-side symptoms
  alone. It lives in the separate backend repo (`docs/api/openapi.yaml`
  there), not this one.
- **PRs explain "why," not "what."** The diff already shows what changed —
  see `.github/pull_request_template.md`.
