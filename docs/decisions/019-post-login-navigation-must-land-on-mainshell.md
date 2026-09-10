# 019 — Post-login navigation must land on MainShell, not a bare Dashboard

Status: Accepted

## Problem

Field reports: on "some mobiles" **all four** bottom-nav tabs (Home, Search,
Leaderboard, Profile) did nothing when tapped. The centre action button
still worked. Not reproducible on the primary dev devices. It "wasn't there
earlier" — a regression.

## Investigation

The bottom nav is one shared widget, `AppBottomNav`. Since the "Unify bottom
nav" rework (commit `bce3551`) a tab tap no longer does `Navigator.push` —
it calls `MainShellController.instance.select(index)`, a **broadcast
`StreamController<int>`**. The *only* subscriber is `MainShell`, in
`initState` (`lib/features/shell/main_shell.dart`). If no `MainShell` is
mounted, `select()` adds to a stream nobody is listening to and the tap is a
silent no-op. The centre FAB is unaffected because it still calls
`Navigator.push(ChallengeReelsScreen())` directly.

So the four tabs are dead exactly when the app is showing a **standalone
`Dashboard`** (its `embeddedInShell` defaulting to `false`, so it renders
its own `AppBottomNav`) with no `MainShell` above it.

Tracing every route that lands in the app:

| Entry path | Target | Result |
|---|---|---|
| Boot with a saved session (`main.dart:356`) | `pushReplacement(MainShell())` | nav works |
| Onboarding chain end (`setup_screen.dart:49`) | `pushAndRemoveUntil(MainShell())` | nav works |
| Post-score / preview / creator-submitted | `pushAndRemoveUntil(MainShell())` | nav works |
| **OTP verify — returning user** (`phone_auth_screen.dart:135`) | `Dashboard()` | **tabs dead** |
| **OTP verify — new user, profile already complete** (`phone_auth_screen.dart:141`) | `Dashboard()` | **tabs dead** |
| **Google / Apple sign-in, profile complete** (`auth_choice_screen.dart:69`) | `Dashboard()` | **tabs dead** |

"Some mobiles" was a red herring — it's *some sessions*: anyone who
authenticated via OTP or social login in-session landed on the bare
`Dashboard`. A device with a persisted session boots through `main.dart`
straight into `MainShell`, which is why it worked for the dev.

The rework converted the nav mechanism to the `MainShellController` bus but
left these three post-auth navigation targets pointing at the pre-rework
`Dashboard()` screen, where the old push-based nav had worked from any
route.

## Options considered

1. **Make `MainShellController` replay the last value / let `AppBottomNav`
   fall back to `Navigator.push` when there's no shell** — papers over the
   real issue (an app screen with a nav bar that isn't under the shell that
   owns navigation) and keeps two navigation mechanisms alive.
2. **Point the three post-auth targets at `MainShell()`** — the same thing
   every other correct entry path already does. `Dashboard` is only ever
   meant to be a tab *inside* the shell now.

## Decision

Option 2. Replaced `const Dashboard()` with `const MainShell()` at:

- `lib/features/auth/screens/phone_auth_screen.dart` — returning user, and
  new-user-with-complete-profile.
- `lib/features/auth/screens/auth_choice_screen.dart` — `_navigateAfterAuth`.

`Dashboard` is no longer constructed anywhere outside `MainShell`'s
`IndexedStack`. The onboarding chain (ProfileSetup → CityInterests →
Interests → Rules → TrustSetup → Setup) already terminates correctly at
`pushAndRemoveUntil(MainShell())` and was left as-is.

## Consequences

- Every way into the app now goes through `MainShell`, so the bottom nav
  always has its controller listener. One navigation mechanism.
- `MainShell` builds all four tab screens up front (IndexedStack keep-alive).
  Post-login now pays that build cost immediately instead of when the user
  first leaves Home. Acceptable — each tab renders its own skeleton and the
  boot path already does exactly this.
- Guard for the future: constructing `Dashboard()` (or any tab screen)
  outside the shell reintroduces the dead-nav bug. If a standalone use ever
  comes back, that screen must host its own real navigation, not an
  `AppBottomNav`.

## Verification

Regression tests in `test/features/auth/screens/phone_auth_screen_test.dart`:

- *"a returning user lands on MainShell (bottom-nav tabs work)"*
- *"a new user whose profile is already complete also lands on MainShell"*

Both drive the OTP request + verify flow (verify → `status: success`,
`isNewUser` false / true) and assert `find.byType(MainShell)` after the
navigation. Verified to fail against the pre-fix code
(`Found 0 widgets with type "MainShell"` — landed on a bare `Dashboard`)
and pass after. Full suite green; `flutter analyze` clean.

## Related

ADR 018 hardened `AppBottomNav`'s own layout (equal-width slots, clamped
text scale) against a separate, additive failure mode where the *last two*
tabs were untappable on narrow / large-font devices due to row overflow
clipping the hit region. This ADR is the cause of the *all four dead*
report.
