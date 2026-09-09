# 008 — Deleted-video Aura clawback via a persisted local offset

Status: Accepted

## Problem

Product requirement: when a user deletes one of their own videos from the
profile section, they should first see a confirmation that names the points
at stake ("This video earned you 48 Aura points. Deleting it will
permanently remove those 48 points from your wallet…"), and on confirm the
displayed wallet balance should drop by that amount straight away.

The pre-existing delete dialog was a generic "This will permanently remove
your video" with a code comment asserting that "any Aura-point reversal … is
computed and applied server-side."

## Investigation

That comment was an unverified assumption, and the spec contradicts it.
`openapi.yaml` (fetched 2026-09-04):

- `DELETE /videos/{id}` — *"Soft-deletes the video. Requires ownership."*
  Bare `SuccessEnvelope`; no Aura / ledger side effects documented.
- `AuraTransaction.reason` enum has no `video_deleted` value.
- `auraPoints` only ever decreases via the admin-only wallet
  reverse/adjust endpoints.

So the backend does **not** debit Aura on delete, and there is no
self-service endpoint that would. Filed as
`docs/backend-issues/003-video-delete-does-not-reverse-aura-points.md`.

## Options considered

1. **Popup only, leave the balance alone.** Honest to server truth, but
   fails the "balance drops immediately" half of the requirement.
2. **Optimistic local subtraction, no persistence.** Balance drops, then
   snaps back on the next `getProfile()` / `/aura/balance` call (which fires
   immediately — `my_account_screen._loadAll()` runs right after delete).
   Visible flicker; rejected.
3. **Persisted local offset.** Track the summed points of videos this user
   deleted in `SharedPreferences`; subtract that offset from every displayed
   balance until the backend debits it itself. Mirrors the existing
   `VideosService._locallyDeleted` workaround for
   [002](../backend-issues/002-profile-videos-returns-soft-deleted-videos.md).
4. **Backend fix only, block the client.** Correct, but out of scope for this
   repo and leaves the prototype demo broken in the meantime.

## Decision

Option 3, with a self-healing reconcile step so it can't double-count.

`VideosService` gains:

- `_deletedVideoAura` (int) + `_serverBalanceBaseline` (int?), both persisted;
  loaded in the existing `hydrate()`.
- `deleteVideo(id, {auraPoints})` — records `auraPoints` into the offset once
  per video id (guarded by the `_locallyDeleted` membership check so a
  re-delete of a still-listed soft-deleted video can't stack it). Now
  `await hydrate()`s first so the guard is reliable even on a delete straight
  from the video-detail screen.
- `adjustBalanceForDeletedVideos(serverBalance)` — pure, sync, floored at 0;
  called from every balance display (`my_account_screen`, `dashboard`,
  `wallet_screen`).
- `reconcileServerBalance(serverBalance)` — called once per balance load. If
  the server balance dropped since the last call, the backend (or an admin)
  applied a deduction of its own, so the offset is shrunk by that much. Once
  the backend ships issue 003 the offset converges to 0.

The confirmation dialog in `user_video_detail_screen.dart` names the exact
amount, and only when the video is `approved` with `auraPoints > 0`;
otherwise it keeps the generic wording.

Level and tier are **not** touched — they stay on the server's authoritative
values (per `aura_tier.dart` / the existing "do not recompute locally"
comments). Only the displayed points number moves.

## Consequences

- The wallet number on Profile, Dashboard and the Aura Wallet screen all
  drop immediately and consistently on delete, and stay dropped across app
  relaunches.
- The offset is a client-only fiction. It will disagree with
  `GET /aura/history` (no matching debit row) and with the raw
  `/aura/balance` until issue 003 ships. The wallet screen's transaction
  list therefore won't sum to the shown balance in that window — accepted.
- Edge case: if the server balance only ever moves up after a delete, a
  later backend debit that nets out positive is invisible to
  `reconcileServerBalance` and the offset keeps subtracting. Rare; resolves
  on any future balance drop.
- When issue 003 ships, delete this offset block, the three call sites, the
  backend-issue doc, and mark this ADR `Superseded`.

## Verification

Regression tests in `test/core/services/videos_service_test.dart`:

- deleting an approved video adds its points to the offset;
  `adjustBalanceForDeletedVideos` subtracts them; a non-approved / 0-point
  video changes nothing.
- the offset survives an app relaunch (persisted).
- a re-delete (`404` already-gone path) does not stack the deduction.
- `reconcileServerBalance` shrinks the offset when the server balance drops,
  and zeroes it once the drop covers the full offset.

Widget test in `test/features/account/screens/user_video_detail_delete_test.dart`:
the confirmation dialog shows the exact point amount for an approved video
and the generic copy otherwise.

## Follow-up (2026-09-07): extend the offset to the Leaderboard

The offset covered the three balance displays but not the Global / Friends
leaderboard, which is ranked **server-side** on the un-debited Aura total —
so after a delete the user's own row still showed the pre-deletion score
*and* sat at the pre-deletion rank (e.g. still shown 3rd while the wallet
already read a 7th-place total).

Added `VideosService.applyDeletedVideoOffsetToLeaderboard(entries,
currentUserId)` — pure/sync, alongside `adjustBalanceForDeletedVideos`. It
re-scores only the current user's row by `_deletedVideoAura` (floored at 0)
and moves that one row down to the slot its adjusted score earns, leaving
every other row in the server's order. No-op with no offset, no user id, or
when the user isn't in the loaded page.

`leaderboard_screen.dart` (`_ApiBoard`, shared by Global + Friends):
`hydrate()`s the offset in `initState`, applies the transform as a pure view
step in `build()` over a pristine `_entries` (the raw server list is what
still gets cached), and also runs `adjustBalanceForDeletedVideos` on the
"your position" footer row (shown when the user is below the loaded window).
The per-challenge board is unaffected — it ranks on submission `aiScore`,
not wallet Aura.

Limitations: the re-rank is only within the currently loaded pages; if the
adjusted score would place the user beyond the loaded window their row lands
at the bottom of what's loaded and settles lower as more pages page in.
Converges to correct once issue 003 ships and the offset hits 0 — same
cleanup note as above (delete this method and call sites too).

Tests: `applyDeletedVideoOffsetToLeaderboard` group in
`test/core/services/videos_service_test.dart` — reposition + re-score,
floor-at-0 sinks to last, identity when no offset / no id / user absent.

## Follow-up (2026-09-09): dropped the `reconcileServerBalance` self-heal

**Symptom:** a user deleted an approved video, saw the wallet drop, then
found it back at the pre-deletion figure after re-logging in the next day —
while the video stayed correctly hidden from the profile grid.

**Cause:** `reconcileServerBalance` shrank the offset on *any* fall in the
server balance since its last call, attributing it to the backend debiting
the deleted video. But the balance falls for unrelated reasons too — the
daily-valid-score-limit replacement writes a negative `auraTransactions`
entry (CLAUDE.md), reward redemptions lower `auraPoints`, and the three call
sites fed one shared `_serverBalanceBaseline` from two different endpoints
(`GET /profile.auraPoints` and `GET /aura/balance`) whose values need not
agree. Every false positive permanently shrank `_deletedVideoAura` (it only
ever decreased), so within a session or two it hit 0 and the deleted
video's Aura reappeared. The original "Edge case" note above had the
failure backwards — the real hazard was *downward* noise, and it wasn't
rare.

**Change:** removed `reconcileServerBalance`, `_serverBalanceBaseline`, and
the baseline pref key (`hydrate` now deletes any lingering copy). The offset
is set only by `deleteVideo` — once per video id, already guarded — and
otherwise never moves, so it's stable across balance swings and relaunches.
The three call sites now just `hydrate()` then `adjustBalanceForDeletedVideos`.

**Trade-off:** when the backend ships issue 003 and starts debiting on
delete, a client that still has this block will double-count a delete made
against the fixed backend. That was always going to require the coordinated
client release this ADR already calls for ("delete this offset block … mark
this ADR Superseded") — the auto-reconcile only ever bought a partial,
unreliable head start on that, at the cost of this bug.

Tests: `videos_service_test.dart` — the two `reconcileServerBalance` tests
were removed (they pinned the buggy behavior); added "offset is stable
across balance swings and relaunches" and "hydrate clears the retired
reconcile-baseline pref key".
