# Backend gap: deleting a video does not reverse the Aura points it earned

**Reported:** 2026-09-04
**Severity:** Medium — wallet balance overstates what the user can spend after a delete
**Affected endpoint:** `DELETE /api/v1/videos/{id}`
**Related:** `GET /api/v1/aura/balance`, `GET /api/v1/profile`, the `AuraTransaction` ledger

## Symptom (product requirement not met)

Product wants: when a user deletes one of their own videos from the profile
section, the Aura points that video earned are removed from their wallet, and
the displayed balance drops immediately.

Today `DELETE /videos/{id}` soft-deletes the video document and nothing else.
The points awarded for its submission (`netAurasAwarded`, added to
`user.auraPoints` at scoring time) stay on the account. `GET /aura/balance`
and `GET /profile` keep returning the pre-delete figure.

## Investigation

- `openapi.yaml` (fetched from `http://144.91.79.237:3786/docs/openapi.yaml`
  on 2026-09-04): `DELETE /videos/{id}` is documented only as *"Soft-deletes
  the video. Requires ownership."* Responses are a bare `SuccessEnvelope` /
  `ErrorEnvelope`; no mention of Aura, `auraPoints`, `totalRewards`, or the
  ledger.
- The `AuraTransaction` `reason` enum is
  `[challenge_submission, referral, achievement, bonus, admin_adjustment, reward, streak, gate_reward]`
  — there is no `video_deleted` / `submission_deleted` reason.
- The only paths that *decrease* `auraPoints` are the admin-only
  `POST /admin/wallet/transactions/{transactionId}/reverse` and
  `POST /admin/wallet/adjustments`.

So there is no self-service mechanism for the deduction the product wants.

## Requested backend change

On `DELETE /videos/{id}` (for a video whose submission earned points), write
an offsetting negative `AuraTransaction` and decrement `user.auraPoints` by
the amount that submission contributed, so that:

- `GET /aura/balance` and `GET /profile` immediately reflect the lower total.
- `GET /aura/history` shows the debit (a `deleted_video_deduction` /
  `video_deleted` reason would let the client label it — the wallet UI
  already has an icon case for `deleted_video_deduction`).
- Re-deleting an already-deleted video (`404` path) does **not** debit again
  (idempotent on the video id).

Open question for the backend team: if the deleted submission was the user's
*best* score for that challenge, should the deduction be the full
`aiScore`, or only `aiScore − nextBestRemainingScore` (mirroring the
`netAurasAwarded = aiScore − previousBestScore` award rule)? The client
currently assumes the full per-video `auraPoints` figure it was shown.

## Client workaround (on `prototype`)

`VideosService` keeps a persisted local offset (`_deletedVideoAura`) of the
points from videos this user has deleted, and every balance display
(`my_account_screen`, `dashboard`, `wallet_screen`) subtracts it via
`VideosService.adjustBalanceForDeletedVideos`. The offset is set only on
delete and is otherwise fixed — there is **no** auto-reconcile against the
server balance (an earlier `reconcileServerBalance` was removed 2026-09-09:
it misread unrelated balance drops — daily-score-limit replacements,
redemptions — as this debit and silently erased the offset within a
session; see ADR 008 follow-up). So when this backend change ships, the
client must be released with the whole mechanism deleted rather than
relying on it to converge.

The Global / Friends **leaderboard** is ranked server-side on the un-debited
total, so it needed its own hook:
`VideosService.applyDeletedVideoOffsetToLeaderboard` re-scores and
re-positions just the current user's row in the loaded page
(`leaderboard_screen.dart`). This too disappears when the backend debits on
delete. (Same root cause; no separate backend ask.)

Known limitation of the workaround: the client offset will disagree with
`GET /aura/history` (no matching debit row) and with the raw `/aura/balance`
until this issue ships — the wallet's transaction list won't sum to the
shown balance in that window. Accepted; it's a client-only fiction by
design.

## To reproduce

1. As a user with an approved video worth N Aura, note `GET /aura/balance`.
2. `DELETE /videos/{id}` for that video → `200`.
3. `GET /aura/balance` again → still the pre-delete figure (expected: −N).
4. `GET /aura/history` → no debit entry for the delete.
