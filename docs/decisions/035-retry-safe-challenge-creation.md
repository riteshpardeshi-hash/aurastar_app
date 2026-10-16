# 035 — Retry-safe challenge creation (long timeout, reuse the uploaded video, "already claimed" = created)

Status: Accepted (2026-10-15)

## Problem

Creating a challenge showed "Couldn't create the challenge. Couldn't reach Aura's servers…" even on
a good connection. Seen in production on 2026-10-15, on both creation screens (My Challenges → New
Challenge, and Creator Tools → Create challenge → record).

## Investigation

- Both create endpoints (`POST /creator/challenges` and `POST /challenges`) run the AI check on the
  reference video **before** answering. In production that took 27–87 s per request (API logs).
- `ApiClient`'s default timeout is 15 s. So the app gave up and showed the "can't reach" error,
  **but the server went on and created the challenge**.
- The creator then tapped Save again. That uploaded the video again and created a second
  challenge: two identical "talk" drafts in production.

So there were two bugs: the timeout was too short for this request, and retrying was not safe.

## Options considered

1. Raise the timeout only. This fixes the common case, but any dropped connection (mobile data,
   the app sent to the background) still loses the answer, and a retry still duplicates.
2. Make the backend create asynchronously (answer at once, run the AI check in the background).
   This is the better long-term shape, but it's a backend and contract change.
3. **Longer timeout plus a client flow that is safe to retry.** Chosen. It needs no backend change.

## Decision

- `CreatorChallengesService.createTimeout = 3 min`, used by `createDraft` and
  `ChallengesService.createChallenge`.
- `ChallengeCreateFlow` (`lib/core/services/challenge_create_flow.dart`) owns
  presign → upload → create for both screens:
  - The uploaded `videoId` is kept across retries. A retry only re-sends the create request; it
    never uploads again. Picking a different video calls `reset()`.
  - The backend lets a video be claimed by exactly one challenge, so a retry whose earlier create
    reached the server gets **409 "This video has already been claimed."** On a retry, the flow
    reads that as `createdEarlier`, i.e. success. On a first attempt it is still an error.
  - It records the step in flight, so errors say what failed: "Couldn't upload the reference
    video…" vs "Couldn't create the challenge…".
- Both screens show progress ("Uploading video… N%", then "Checking your video… this can take a
  minute") and disable the button while saving.
- Both services now throw the server's message on an error response. `createChallenge` used to
  crash on a null `data`.
- My Challenges refreshes its status-chip counts as well as the list after creating or opening a
  challenge (`_refresh()`).

## Consequences

- No more false "can't reach" errors on slow AI checks, and no duplicate challenges from retries.
- A genuinely slow server can keep the creator waiting up to 3 minutes. The progress label says
  why.
- If the backend ever changes the 409 wording, `ChallengeCreateFlow.isAlreadyClaimed` must follow.
  `test/core/services/challenge_create_already_claimed_test.dart` pins the real envelope.
- Regression tests (each verified to fail on the old code):
  - `test/core/services/creator_challenges_create_slow_ai_check_test.dart`: 40 s response on both
    endpoints.
  - `test/core/services/challenge_create_flow_test.dart`: 8 retry and edge cases.
  - `test/core/services/challenge_create_already_claimed_test.dart`: lost answer → 409 → created,
    for both endpoints, plus server error messages.
  - `test/features/creator/screens/creator_challenges_screen_counts_refresh_test.dart`: chip
    counts after create.
- Device QA on 2026-10-15 used a fault-injection proxy in front of the production API: a 40 s
  delay, a dropped connection then a retry, 7 rapid taps, and the record flow's dropped connection
  then a retry. Each produced exactly one challenge in the database.
