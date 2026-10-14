# Backend gap: no endpoint to block a user or report a user

**Reported:** 2026-10-08
**Status:** OPEN — blocking the iOS App Store resubmission
**Severity:** High — App Review rejected build 1.0 (62) under guideline 1.2 (user-generated content)
**Affected endpoints:** none exist. Closest is `POST /challenges/{id}/report`, which reports a *challenge*, not a person.

## Why this is needed

Apple rejected the app on 2026-10-07 under **guideline 1.2 — Safety — User-Generated Content**. For apps with user-generated content they require all of:

1. Terms (EULA) the user agrees to, stating zero tolerance for objectionable content and abusive users — client work, tracked separately.
2. A way to **flag** objectionable content — partly exists (challenge report).
3. A way to **block** abusive users. Blocking must **notify the developer** and **remove the blocked user's content from the blocking user's feed instantly**.
4. The developer must **act on reports within 24 hours** by removing the content and ejecting the offending user.

Apple also asks for a screen recording on a physical device showing the EULA, the flag mechanism and the block mechanism.

## Investigation

Searched the full live spec (`http://144.91.79.237:3786/docs/openapi.yaml`, fetched 2026-10-08) for `block`, `mute`, `hide`, `report`:

- No user-block, unblock or blocked-list endpoint. Every `BLOCKED` hit is either the admin brand status enum (`PATCH /admin/brands/{brandId}/status`) or admin device-risk tooling (`/admin/risk/block-device`) — neither is player-facing.
- The only player-facing report endpoint is `POST /challenges/{id}/report` (reason enum `inappropriate|spam|dangerous|misleading|copyright|other`). There is no way to report a user, a submission or a comment.
- `/admin/moderation/queue` and `/admin/moderation/cases/*` exist, so the moderation workflow itself is in place; it just has no user-originated block or user-report input.

A device-only block in the app was considered and rejected for now: it can hide content but cannot notify the developer, does not follow the user to another device, and leaves nothing for moderators to act on.

## Requested

All authenticated (`BearerAuth`).

| Endpoint | Purpose |
|---|---|
| `POST /users/{id}/block` | Block a user. Idempotent. Must create a moderation-queue item so the team is notified. Reject blocking self. |
| `DELETE /users/{id}/block` | Unblock. |
| `GET /profile/blocked` | List the caller's blocked users (`_id`, `displayName`, `avatar`) so the app can show a "Blocked users" screen and filter locally. |
| `POST /users/{id}/report` | Report a user. Body `{ reason, remarks? }`, same reason enum as challenge reports. Feeds the existing moderation queue. |

Server-side behaviour we also need, so blocking is instant and consistent:

- Content authored by a blocked user is excluded from the blocker's responses wherever other users' content appears: leaderboards (global and per-challenge), search results, creator and brand lists, the challenge feed and comments (if enabled). Doing it server-side means every client benefits without per-screen filtering.
- Idempotent per (blocker, blocked) pair.

Nice to have: an optional `submissionId` / `videoId` on the report so moderators see the specific content.

## 24-hour response

Apple expects a documented process: reports reviewed within 24 hours, offending content removed, offending account ejected. Please confirm who owns the moderation queue and the SLA, and that an admin can deactivate a user from a case (`POST /admin/moderation/cases/{caseId}/decide`).

## Client plan once shipped

- "Block user" and "Report user" actions on creator and brand profiles and on leaderboard rows (rows currently only show a "player profiles are private" notice).
- Settings → Blocked users, with unblock.
- Move the report flow off the dead Firestore path for submissions (`_SubmissionReportSheet` in `challenge_detail.dart`) onto the new API.
- Explicit EULA accept step at signup.
- Record the physical-device demo video for App Review.
