# 028 — Add Firebase Analytics by moving the app's default Firebase project to `aura-arena-81e92`

Status: Accepted

## Problem

We want Google Analytics for product usage (logins, challenge views,
submissions, shares). A new Firebase project (`aura-arena-81e92`) was
created for it; the app was still initialised against the old
`aura-app-efae1` project, and Android had no `google-services.json` at all.

## Options considered

1. **Analytics on a secondary `FirebaseApp`.** Rejected: the native
   Analytics SDKs (and `firebase_analytics`) only report for the *default*
   app, so this would silently collect nothing.
2. **Keep the old project as default, no analytics.** Doesn't meet the goal.
3. **Make the new project the default app.** Analytics works; everything
   else on Firebase moves with it.

## Decision

Option 3. `lib/firebase_options.dart` (hand-written from the two downloaded
config files, no `flutterfire configure`), `android/app/google-services.json`
and `ios/Runner/GoogleService-Info.plist` all point at `aura-arena-81e92`;
the Google Services Gradle plugin is applied; `firebase_analytics` added.

`AnalyticsService` (`lib/core/services/analytics_service.dart`) wraps it:
fire-and-forget, never throws, no-ops when Firebase isn't initialised, only
opaque ids / coarse enums as parameters (no phone numbers or names). The
user id is set/cleared centrally in `ApiClient.saveSession`/`clearSession`
and on cold start. Events: `login`/`sign_up` (phone), `logout`,
`screen_view` (bottom-nav tabs + named routes), `challenge_view`, `share`,
`submission_uploaded`, plus the participation funnel from the analytics
tracking plan: `recording_started`, `recording_cancelled`, `upload_started`,
`upload_succeeded`, `upload_failed {stage, reason}`,
`submission_status_changed`, `points_awarded`, `level_up`. User properties
`user_level` and `account_type` are set from the Dashboard profile poll
(re-sent only when changed).

Second batch: `brand_page_view`, `profile_view` (own profile excluded),
`explore_brands_click`, `aura_creator_join_click`, `center_fab_click`,
`onboarding_step`, `search`, `app_open {organic|push|deeplink}`,
`deeplink_open`, `coupon_claimed`, `follow`/`unfollow`, Google/Apple
`login`/`sign_up`, and `share` on every share button. `challenge_view` now
carries `source` (a new `source` param on `ChallengeDetail`, set at each of
its ~20 call sites) and `owner_type`/`owner_id` (the challenge's `sourceType`
and `creatorId`), so it is logged once the challenge fetch settles. Brand and
creator profile screens take the same optional `source`. Gaps: warm resumes
don't log `app_open` (only cold start and warm link/push opens);
`share_external.channel` isn't available (share_plus doesn't report the
target app reliably on Android); `aura_levels_open` has no screen to hook.

Score/points/level events are derived
client-side from the synchronous `createSubmission` response rather than
server events, so a user who closes the app mid-scoring won't emit them.

`android/app/google-services.json` is no longer git-ignored: it contains
client identifiers, not secrets, and CI needs it.

## Consequences

- **Push (FCM) moves projects.** Existing device tokens belong to the old
  project. Until the backend swaps its FCM service-account key for the new
  project's, pushes fail; tokens re-register on next launch. iOS also needs
  the APNs `.p8` uploaded (dev + prod) in the new project.
- The `appConfig/version` Firestore check now reads the *new* project; it
  already fails safe to "ok", so force/soft-update prompts are off until that
  doc is created there.
- The plist's `BUNDLE_ID` is `com.onadsgroup.auraapp`. The Codemagic
  *prototype* iOS build rewrites the bundle id to `...auraapp.prototype`, for
  which no Firebase app is registered — Firebase/analytics/push are
  unreliable on that build until one is added.
- Most routes are unnamed `MaterialPageRoute`s, so only tabs and named
  routes emit `screen_view`; name more routes as needed.
- Privacy policy and the Play data-safety form must mention analytics.

## Verification

`test/core/services/analytics_service_test.dart`: never throws without
Firebase, typed helpers emit the expected names/params, the route observer
logs named routes only. Live check: enable DebugView
(`adb shell setprop debug.firebase.analytics.app com.onadsgroup.auraapp`)
and confirm events in Firebase console → Analytics → DebugView. Note the
downloaded plist has `IS_ANALYTICS_ENABLED=false`; if iOS shows nothing in
DebugView, set it to `true` by hand.
