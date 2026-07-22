# 001 — Deduped concurrent token-refresh + global session-expiry redirect

Status: Accepted

## Problem

Users reported the app cold-starting into a permanent "Failed to load
profile." screen after being closed for a while, with no way to recover
short of force-quitting and relaunching.

## Investigation

`Dashboard._fetchDashboardProfile` fires three authenticated calls at once
via `Future.wait` (`getProfile`, `fetchStreak`, `fetchOwnPage`). If the
access token has expired (15 min TTL, per the backend's live OpenAPI spec —
`docs/api/openapi.yaml` in the backend repo, served at
`http://144.91.79.237:3786/docs/openapi.yaml`), all three get a 401
simultaneously, and each one independently called `ApiClient._tryRefresh()`.

The backend's `/auth/refresh` rotates the refresh token on every use — the
submitted token is revoked immediately, replay is rejected with 401 (see the
live spec: `http://144.91.79.237:3786/docs/openapi.yaml`, path
`/auth/refresh`, description: "the submitted refresh token is immediately
revoked (rotation)"). With three independent, un-deduped refresh attempts:
the first one to land rotates the token and saves a valid new pair; the
other two are still holding the *old* (now-revoked) refresh token, get 401
back from the backend, and each call `clearSession()` — wiping out the
valid pair the first call just wrote, moments after it landed.

Separately: when a refresh token is *genuinely* dead (not a self-inflicted
race, but truly expired/revoked), the client had no way to distinguish that
from a transient network failure — `getProfile()` swallows all failures into
a generic `null`, so the user was stuck retrying against a session that can
never succeed.

## Options considered

1. **Add a retry button / auto-retry on the "Failed to load profile."
   screen.** Fixes the symptom for genuine transient network blips, but does
   nothing for either the refresh race (retrying with the same racing logic
   just re-triggers it) or a truly dead session (retrying with no valid
   credentials just 401s again). Kept as a *secondary* fix for real network
   hiccups, since that failure mode is still legitimate.
2. **Dedupe concurrent refresh attempts + broadcast a distinct
   "session expired" signal.** Addresses the actual root causes: no more
   racing refresh attempts, and a genuinely dead session gets a clear signal
   the rest of the app can react to.

## Decision

Implemented option 2, on top of keeping the retry UI from option 1 for
non-auth failures:

- `ApiClient._tryRefresh()` now funnels through a single in-flight `Future`
  (`_refreshInFlight`), so concurrent callers await the same refresh attempt
  instead of each independently reading and POSTing the refresh token.
- `ApiClient` exposes a broadcast `onSessionExpired` stream, fired only when
  a refresh token is confirmed dead (401 after an actual attempt) — never on
  a network/timeout failure, so it can't misfire on connectivity issues.
- `main.dart`'s `_MyAppState` subscribes app-wide and, on that signal, resets
  the navigation stack to `PhoneAuthScreen` with a snackbar, instead of
  leaving any screen stranded on a dead error state.

## Consequences

- Any authenticated call anywhere in the app now benefits from the refresh
  dedup and the session-expiry redirect, not just Dashboard.
- This assumes the backend returns a plain 401 for an invalid/expired/
  revoked refresh token (confirmed against the live OpenAPI spec at the time
  of writing). If that ever changes to a different status code, this logic
  needs updating alongside it.
- Doesn't address `flutter_secure_storage`'s "before first unlock" iOS
  keychain access issue after a device reboot — a separate, unconfirmed
  failure mode not reproduced here.

## Verification

`test/core/services/api_client_test.dart` — two tests:
- 3 concurrent authed calls racing an expired token trigger exactly one
  `/auth/refresh` request and all 3 succeed with the rotated token.
- 3 concurrent authed calls against a genuinely dead refresh token still
  attempt refresh only once and fire `onSessionExpired` exactly once.

Confirmed these aren't tautological by temporarily reverting the dedup
(`_tryRefresh` calling `_doRefresh()` directly) — both tests failed with
`Expected: <1> Actual: <3>` — then restored the fix and re-verified green.
