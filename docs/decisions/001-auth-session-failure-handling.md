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
- ~~`ApiClient` exposes a broadcast `onSessionExpired` stream, fired only
  when a refresh token is confirmed dead — never on a network/timeout
  failure~~ — this claim was **wrong** in the original implementation; see
  the 2026-08-18 update below, which fixes it.

## Update (2026-08-18): refresh-vs-network conflation, and a misleading error screen

Users reported the app cold-starting into "Failed to load profile." with a
wifi-off icon even while connected to the internet. Investigation found two
distinct bugs, both stemming from the original implementation of this ADR:

**1. `ApiClient._doRefresh()` didn't actually distinguish "confirmed dead"
from "couldn't tell."** The original code wrapped the `/auth/refresh` POST
in a single `try { ... } catch (_) {}`, then unconditionally fell through to
`clearSession()` + `_sessionExpired.add(null)` whenever the `if (res.statusCode
== 200)` branch wasn't taken — which happened both when the backend actually
returned a non-200 (a real verdict) *and* when the request itself threw
(timeout/`SocketException`, i.e. no verdict at all). A plain connectivity
blip landing at the exact moment the 15-minute access token expired would
force a real logout, contradicting the "never on a network/timeout failure"
claim this ADR made. Fixed by separating "the request failed to complete"
(return `false`, leave the session untouched — the next authed call just
retries) from "the backend responded and rejected the token" (the original
clear-session-and-signal path, now reached only from an actual non-200
response).

**2. Dashboard's error screen collapsed every failure into "no internet."**
`Dashboard._fetchDashboardProfile` threw a bare `Exception('Failed to load
profile')` whenever `AuthApiService.getProfile()` returned `null` — and
`getProfile()` swallowed *all* failures (network exceptions, timeouts, a
500, a malformed response, an auth failure) into that same `null`, discarding
the actual cause. The error screen then always showed a `wifi_off_rounded`
icon and the literal text "Failed to load profile.", regardless of why the
load actually failed. Fixed by adding `AuthApiService.getProfileOrThrow()`
(additive — the existing `getProfile()` keeps its null-swallowing contract
for the ~8 other call sites that rely on it) which lets the real error
propagate, and having Dashboard classify it via a new `isNetworkError()`
helper extracted from `error_message.dart`'s existing `humanizeError()`:
only genuinely connectivity-flavored exceptions (`SocketException`,
`TimeoutException`, `ClientException`, etc.) get the wifi-off icon and the
generic "couldn't reach servers" copy; anything else shows a plain error
icon and the real message.

Together: a cold-start network blip still shows the (now-2s-auto-retrying)
"couldn't reach servers" screen as before, a network blip specifically
*during token refresh* no longer force-logs-out the user, and a genuine
backend error is no longer misreported as a connectivity problem.

## Verification

`test/core/services/api_client_test.dart`:
- 3 concurrent authed calls racing an expired token trigger exactly one
  `/auth/refresh` request and all 3 succeed with the rotated token.
- 3 concurrent authed calls against a genuinely dead refresh token still
  attempt refresh only once and fire `onSessionExpired` exactly once.
- A network/timeout failure while calling `/auth/refresh` leaves the stored
  access/refresh tokens untouched and never fires `onSessionExpired` (added
  2026-08-18; reverting the `_doRefresh()` fix reproduces the failure with
  `Expected: 'expired-access-token' Actual: <null>`).

`test/core/utils/error_message_test.dart` (added 2026-08-18): pins down
`isNetworkError()`'s classification (`SocketException`, `TimeoutException`,
`http.ClientException` → true; a plain backend-message `Exception` → false)
and that `humanizeError()` only substitutes the generic connectivity copy
for the network-flavored cases.

Confirmed the original dedup test isn't tautological by temporarily
reverting the dedup (`_tryRefresh` calling `_doRefresh()` directly) — both
tests failed with `Expected: <1> Actual: <3>` — then restored the fix and
re-verified green. Confirmed the 2026-08-18 regression test the same way by
reverting just the `_doRefresh()` split and re-running.
