# 005 — Streak lives only on My Account; foreground push shows in-app, taps go to the notification list

Status: Accepted

## Problem

Two related gaps around the streak feature and push notifications:

1. **The dashboard was carrying the streak in two forms** — a 7-day dot-tracker
   banner (`_buildStreakBanner`) plus a once-per-session "streak ends at
   midnight" snackbar — on a home screen that is already dense (header, pending
   upload, hero, brand videos, creator videos, banners, trending, admin,
   endless grid). The My Account screen also has a streak card, so the streak
   was rendered twice with different logic and different rules for when to hide.

2. **`PushNotificationService` only registered the FCM token.** There was no
   `FirebaseMessaging.onMessage` handler, so a push arriving while the app was
   foregrounded showed the user nothing (iOS suppresses the system banner in
   foreground unless told otherwise; Android never shows one). The backend nudge
   engine (streak reminders included) was effectively silent whenever the app
   was open.

## Investigation

- The dashboard's own doc comment already flagged the streak as "decorative"
  (`fetchStreak()` swallows its failures to null). The streak-state logic
  (on-track / at-risk / broken) had a history of being structurally unreachable
  — see commit `347a613` and `streak_date.dart` — because the last-activity
  date was assumed to be "today". That logic deserves exactly one home, not a
  copy per screen.
- `GET /profile/streak` (OpenAPI, `http://144.91.79.237:3786/docs/openapi.yaml`)
  returns `currentStreak`, `longestStreak`, `lastActivityDate`,
  `completedStreaks`, `streakStartDate`, `lastRewardedAt`. It is read-only —
  there is no client action that advances or repairs a streak, so the streak is
  a status display, not an interactive surface.
- The push payload has **no documented per-type deep-link contract**.
  `NudgeTemplate.deepLinkScreen` exists in the spec but is described as
  admin-editable copy, seeded lazily — not a stable key the client can branch
  on. `main.dart` already had a comment saying exactly this and routing every
  tap to the in-app notification list as a result.

## Options considered

1. **Move the streak to the Challenges tab** — contextually strongest (the
   streak advances by doing challenges). Rejected for now: it adds a new
   stateful surface and its own fetch to a second screen, for a feature the
   product owner considers secondary.
2. **Keep a slimmed banner on the dashboard.** Rejected — the ask was
   explicitly to reduce dashboard clutter, and a smaller banner is still a row.
3. **My Account only** (chosen) — delete the dashboard banner and snackbar; the
   existing My Account streak card is the single surface. An earlier revision
   added an at-risk / broken status line to that card, but the product owner
   asked to keep the card in its original format, so it stays counts-only with a
   `N/7` cycle-progress figure added.
4. **Deep-link push taps by type** (e.g. `streak_*` → the streak card).
   Rejected — would require guessing undocumented payload keys; a wrong guess
   sends users to the wrong screen. Deferred until the backend documents the
   payload (ADR 042 in the backend repo).
5. **Foreground push: `setForegroundNotificationPresentationOptions` so iOS
   shows its own banner.** Rejected — diverges by platform (Android still shows
   nothing) and can double up with an in-app banner. An in-app snackbar on both
   platforms is consistent.

## Decision

- **Dashboard**: removed `_buildStreakBanner`, the at-risk snackbar, the
  `fetchStreak()` call in `_fetchDashboardProfileOnce`, and the `streakDay` /
  `lastStreakDate` plumbing through `_buildScaffold`.
- **My Account**: `_buildStreakCard` keeps its original layout (fire icon,
  "DAILY STREAK", a headline, `Best` / `Completed` on the right). The only
  change is the headline: `"$current days in a row"` → `"$dayOfCycle/7 days"`,
  where `dayOfCycle` is `currentStreak` capped at 7 — so a lapsed streak reads
  `"0/7 days"`. No status line, no state-driven colour. The card still hides
  only when `currentStreak == 0 && longestStreak == 0`.
- **Foreground push**: `main.dart` now listens to `FirebaseMessaging.onMessage`
  and shows a floating snackbar with a "View" action. Text is built by a new
  pure helper `lib/core/utils/push_message_text.dart` (`foregroundPushText`).
- **Push routing unchanged**: the snackbar's "View", `onMessageOpenedApp`, and
  `getInitialMessage` all open the in-app notification list. No per-type
  deep-linking until the payload contract is documented.

## Consequences

- The streak is now single-sourced, and shown as a plain progress figure
  (`N/7`) plus best/completed counts. The at-risk / "streak ends at midnight"
  nudge that used to fire from the dashboard is gone with no in-app
  replacement; the only reminder path left is the backend `streak_reminder`
  push (now visible in-foreground). A user with push off gets no nudge —
  accepted, streak is a secondary feature.
- `deriveLastStreakDate` (`lib/core/utils/streak_date.dart`) now has no caller —
  the dashboard banner was its only user. Left in place (8 lines, tested) in
  case streak-state logic returns; a future cleanup could drop it and its test.
- `N/7` caps at 7. If the backend ever lets `currentStreak` run past 7 without
  resetting, the card would sit at `7/7` — acceptable for now, revisit if that
  behaviour is confirmed.
- Foreground pushes now surface, but tapping any notification still lands on the
  list, not the relevant screen. Closing that gap needs the backend payload
  contract (ADR 042).

## Verification

- `test/core/utils/push_message_text_test.dart` — title+body / title-only /
  body-only / empty (data-only) / whitespace.
- `flutter analyze` clean for all changed files (2 pre-existing
  `curly_braces_in_flow_control_structures` infos elsewhere in `dashboard.dart`
  are unrelated). `test/features/dashboard/dashboard_test.dart` and
  `test/features/account/screens/my_account_screen_level_test.dart` still pass.
- The streak card change is display-only (a string-format tweak, no new
  branching), so it carries no dedicated test.
- The `onMessage` handler itself is not widget-tested — `main.dart`'s FCM wiring
  has no test harness in this repo. Manual check: send a test push with the app
  foregrounded → snackbar appears with "View" → tap opens the notification list.
