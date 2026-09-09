# 015 — Creator profile grid shows the creator's authored challenges, not their attempt videos

Status: Accepted

## Problem

Every creator's public profile (`CreatorProfileScreen`) showed an empty
"No videos yet" state in its content grid, and "0 Challenges" in the header
stat — even for creators who have authored live challenges and/or recorded
challenge attempts.

## Investigation

- The grid was populated from `GET /creators/{id}/videos`
  (`CreatorsService.fetchCreatorVideos`), documented as *"videos submitted by
  a creator"* — the creator's own attempt `Submission` records. That endpoint
  returns `{"totalCount":0,"responses":[]}` for every creator tried.
- This is the same class of backend gap already logged for
  `GET /profile/videos` (`docs/backend-issues/002`, "My Videos Backend Gap"):
  scored/approved submissions are never linked into the per-user video feeds.
  Confirmed still broken as of 2026-09-08. Filed as
  `docs/backend-issues/005`.
- The header "Challenges" stat was rendered as `_videos.length`
  (`creator_profile_screen.dart`) — the length of that same always-empty list
  — so it was structurally always "0", and mislabeled regardless.
- `CreatorProfile` in the OpenAPI spec carries no challenge/video counts, so
  the real number can't come from `GET /creators/{id}`.
- `GET /challenges?creatorId={id}&sourceType=Creator` **does** work — it's the
  same feed endpoint used by trending/dashboard/category screens, and it
  applies the normal public visibility rules (non-admin callers see
  `status: approved`, minus `submissionStatus` PAUSED/ENDED). A creator's
  approved challenges come back here even while their lifecycle is stuck at
  DRAFT (a separate backend bug).

## Options considered

1. **Add a `/videos/my?userId={id}` fallback for the attempt-video grid.**
   Speculative — `/videos/my` is documented as "list *my* videos" and the
   `userId` filter may be admin-only or silently ignored, in which case it
   would render the *viewer's* videos on someone else's profile. Doesn't fix
   the wrong "Challenges" count.
2. **Show the creator's authored challenges instead.** Uses a known-good
   endpoint, is the content a "creator profile" is expected to showcase, and
   makes the "Challenges" stat correct by construction.
3. **Two sections** — authored challenges + a separate attempt-videos section.
   More screen surface and layout work for a section that is empty today.

## Decision

Option 2. `CreatorsService.fetchCreatorChallenges(id)` calls
`GET /challenges?creatorId={id}&sourceType=Creator`; the profile grid renders
those (thumbnail + title, tap → `ChallengeDetail`) and the header stat is now
`_challenges.length`.

`GET /creators/{id}/videos` is still fetched and used as a **fallback** grid,
shown only when the creator has authored no challenges (e.g. a regular user
promoted to creator). If/when `docs/backend-issues/005` is fixed, those
profiles start showing attempt videos again with no further client change.

## Consequences

- Creator profiles now show real content and a real challenge count.
- A creator with challenges still `PENDING_REVIEW` (not yet approved) shows
  "0 Challenges" — correct: unapproved challenges shouldn't appear on a public
  profile.
- The `ScreenCache` payload for `creator.{id}` gained a `challenges` key;
  older cached entries without it degrade to an empty list until the next
  background refresh (one load cycle).
- `CreatorsService._extractList` now also recognises a `challenges` array key
  in the response envelope.

## Verification

`test/core/services/creators_service_test.dart`:
- `fetchCreatorChallenges hits GET /challenges filtered by creatorId +
  sourceType and unwraps data.challenges` — fails if the `challenges` key is
  dropped from `_extractList` (verified by reverting that line).
- `fetchCreatorChallenges returns [] when the request is not successful`.

`flutter analyze` clean on the changed files; full `flutter test` suite
(130 tests) green.
