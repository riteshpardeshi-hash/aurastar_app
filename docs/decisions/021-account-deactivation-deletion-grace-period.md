# 021 — Account deactivation, delayed-deletion grace period, and data export

Status: Accepted

## Problem

The only self-service account-removal path (`AuthApiService.deleteAccount()`
→ `DELETE /profile`) was an instant, irreversible erasure: one tap of "Delete
Forever" and the account was gone, no way back. There was also no way to
temporarily step away from the app (deactivate) without permanently deleting
it, and no way to download a copy of your own data.

The product requirement: deletion should give a configurable grace period
(admin-tunable, default 15 days) during which the account is deactivated but
recoverable — simply logging back in cancels the pending deletion and
reactivates the account — and only becomes permanent once that window
elapses. Separately, users should be able to deactivate (no deletion implied)
and export their data as an Excel workbook.

## Investigation

The backend implemented this first (see the backend repo's ADR 098, which
supersedes its ADR 095): `DELETE /profile` no longer erases immediately — it
now schedules deletion and returns `deletionScheduledFor`; new endpoints
`POST /profile/deactivate`, `POST /profile/deletion/cancel`, and
`GET /profile/export` were added; every login response (`POST
/auth/otp/verify`, `POST /auth/google`, `POST /auth/apple`) now carries a
`deletionCancelled: boolean` flag, true when that login just auto-cancelled a
pending deactivation/deletion. Confirmed by reading the backend's
`docs/api/openapi.yaml` and the actual committed route/controller diff
(`src/routes/profile.routes.js`, `src/controllers/profile.controller.js`,
`src/services/auth.service.js`) on its `feat/account-deactivation-deletion-export`
branch, rather than assuming shapes — per this repo's "ground claims in the
spec" rule. That branch is not yet merged/deployed as of this ADR, so the
live OpenAPI spec at `/docs` should be re-checked before relying on these
shapes in further work.

## Options considered

1. **Keep `deleteAccount()`'s existing "fire and forget, instant" contract,
   add the new endpoints as unrelated extras.** Rejected — the whole point
   of the grace period is that `DELETE /profile` is no longer instant; a
   client that keeps treating it as instant would show the wrong copy
   ("permanently removes your profile" with no grace period mentioned) and
   never surface the returned `deletionScheduledFor` date at all.
2. **Show the exact grace-period length (e.g. "15 days") in the initial
   confirm dialog, hardcoded client-side.** Rejected — the backend setting is
   admin-tunable at runtime; hardcoding a number here would drift the moment
   an admin changes it. The confirm dialog instead uses generic language
   ("a grace period set by Aura Arena") and the *actual* date is shown from
   the real `deletionScheduledFor` the API returns, in a follow-up dialog
   right after the request succeeds.
3. **Poll or query the grace-period setting from the client before showing
   the confirm dialog, to show the exact day count up front.** Rejected as
   unnecessary complexity for this pass — no endpoint currently exposes the
   raw setting value to non-admin callers, and the returned
   `deletionScheduledFor` from the actual request already gives the user the
   one date that matters (when it will happen), immediately after confirming.

## Decision

- `AuthApiService.deleteAccount()` now returns `Future<DateTime?>` (the
  server's `deletionScheduledFor`) instead of `Future<void>`, and its doc
  comment/behavior no longer claims instant erasure.
- Added `deactivateAccount()`, `cancelPendingDeletion()`, `exportMyData()` to
  `AuthApiService`.
- Added `ApiClient.getBytes()` — every other `ApiClient` method assumes a
  JSON body; the `.xlsx` export needed a raw-bytes path with the same
  401-retry-once/timeout shape as `get()`.
- `AuthResult` (the shared login-result record type) gained a
  `deletionCancelled` field, threaded through from every login call site
  (`verifyOtp`, `signInWithGoogle`, `signInWithApple`).
- New shared widget `shared/widgets/deletion_cancelled_dialog.dart` —
  `showDeletionCancelledDialog()` — shown once by every login entry point
  (`PhoneAuthScreen._verifyOtp`, `AuthChoiceScreen._navigateAfterAuth`, which
  both Google and Apple sign-in funnel through) when `deletionCancelled` is
  true, before navigating on. Centralized rather than duplicated so the
  copy/styling can't drift between entry points.
- `SettingsScreen`: added "Deactivate Account" (Danger Zone, simple
  confirm — same weight as Logout, since it's reversible any time) and
  "Export My Data" (Account section, not destructive) actions.
  `_DeleteAccountDialog`'s copy was rewritten to describe the grace-period
  behavior generically; the exact scheduled date is shown in a new
  post-confirmation dialog using the real value the API returned, then the
  screen navigates to `PhoneAuthScreen`.

## Consequences

- Any other place in the client that assumed `deleteAccount()` immediately
  and permanently erases the account (none found beyond `SettingsScreen` at
  the time of this change) needs the same update if it's ever called
  elsewhere.
- The post-confirmation "scheduled for" dialog is shown and awaited *before*
  `Navigator.pushAndRemoveUntil` runs, specifically because that call removes
  `SettingsScreen` from the tree — a `ScaffoldMessenger`/dialog call against
  its `context` afterward would be invalid (looking up a deactivated
  widget's ancestor). Any future edit to this flow must preserve that
  ordering.
- This client build depends on the backend's `feat/account-deactivation-deletion-export`
  branch being deployed with matching shapes; until then, hitting these
  endpoints against production will 404/behave like the old immediate-delete
  contract.

## Verification

Widget tests in `test/features/account/screens/` cover: the Deactivate
Account confirm dialog's cancel/confirm wiring, and that `_DeleteAccountDialog`'s
typed-DELETE gating still works unchanged. The network calls themselves
(`AuthApiService` methods) aren't exercised in these tests — same pre-existing
boundary as Logout/Logout-All/the original Delete Account test, since this
test bundle has no Firebase app initialized and no HTTP mocking harness for
`ApiClient` today. Manual verification against a locally running backend
(same branch) is the practical path until that harness exists.
