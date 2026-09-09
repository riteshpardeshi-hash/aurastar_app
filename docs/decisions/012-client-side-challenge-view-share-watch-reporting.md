# 012 — Client-side reporting of challenge views, watch progress and shares

Status: Accepted

## Problem

Bug report: on the creator / brand analytics screens the **Views**, **Shares**
and **Total Attempts** figures show `0` for challenges that demonstrably have
real activity (live challenges with participants, submissions and scores).
The counters are supposed to reflect actual mobile / user activity.

Affected readouts:
- `creator_challenge_analytics_screen.dart` — Overview tab (`views`,
  `shares`, `totalAttempts`), Engagement tab (`totalViews`, `shares`),
  Shares & Followers tab (`totalShareClicks`).
- `creator_challenge_status_screen.dart` — `_statsCard` (`Views`,
  `Attempts`).
- `creator_insights_screen.dart` — creator-wide `views`.

## Investigation

Traced each metric to its source in the live OpenAPI spec
(`http://144.91.79.237:3786/docs/openapi.yaml`, fetched 2026-09-07):

- **Views** — `CreatorChallengeAnalyticsResponse.views` / the
  `CreatorDailyAnalytics` rollup / `CreatorChallengeStats.views` ("a single
  flat challenge-wide counter"). The spec documents two events the **mobile
  app is expected to fire** to populate this family of counters:
  - `POST /challenges/{id}/impression` — *"Fired by the mobile app when this
    Challenge becomes visible inside the feed."*
  - `POST /challenges/{id}/watch-progress` — *"Fired repeatedly by the mobile
    app while a challenge's video is being watched."* Upserts one
    `ChallengeWatchAnalytics` row per `(challenge, player)` session.

  `grep -rn "impression\|watch-progress" lib/` → **zero call sites.** The
  Flutter client never fired either event, so the backend had no view data
  to aggregate.

- **Shares** — `CreatorShareAnalytics.totalShareClicks`. The spec is
  explicit that there is **no ingestion path**: *"No per-platform share
  tracking exists anywhere in this codebase yet"*, and the city-breakdown
  `shareRate` is *"Always 0 — no data source exists to compute this
  honestly."* Every share in the app is a bare OS share sheet
  (`Share.share(...)`, 13 call sites) with no backend call.

- **Total Attempts** — `totalAttempts` is *"Summed from
  `ChallengeParticipantStats.attemptCount`"*. The client already submits
  correctly via `POST /challenges/{id}/submissions`
  (`challenges_service.dart`). If real scored submissions exist and attempts
  still read 0, the increment / linkage is missing **server-side** — the
  same shape as the known `GET /profile/videos` linkage gap
  (`docs/backend-issues/002`). Not fixable from the client.

## Options considered

1. **Add `visibility_detector` and instrument every feed grid** — most
   faithful to "becomes visible inside the feed", but a new dependency and a
   lot of surface area (5+ grid screens) for a first cut.
2. **Fire impressions only where the app already knows a challenge is the
   focused item** — the reels `PageView` (`onPageChanged` = "this challenge
   is now the active reel") and `ChallengeDetail.initState` (the user opened
   it). No new dependency. Grid-scroll impressions deferred.
3. **Do nothing client-side, file it all as backend** — wrong: two of the
   three gaps are squarely the client not holding up its end of a
   documented contract.

## Decision

New `core/services/challenge_analytics_service.dart` — a fire-and-forget
singleton wrapping the three reporting calls. Every method swallows all
errors and never blocks the caller; analytics reporting must not be able to
break a screen.

- `recordImpression(id)` → `POST /challenges/{id}/impression`, **deduped per
  app session** (the reels feed re-emits `onPageChanged` on every scroll-back;
  a feed impression is meant to count once per session). Wired at:
  reels `onPageChanged` + first-page load, and `ChallengeDetail.initState`.
- `recordWatchProgress(id, watched, total, {flush})` →
  `POST /challenges/{id}/watch-progress`. Safe to call on every player tick
  — throttles internally to ≤1 request per challenge per 5s and only after
  watched time grows ≥3s; `flush: true` forces the final position out on
  dispose / clip-end. One `sessionId` per view. Wired into the reels
  `_ReelPage` player and `ChallengeDetail`'s controller.
- `recordShare(id, {platform})` → `POST /challenges/{id}/share`. **This
  endpoint does not exist yet** — the call is a deliberate no-op (404,
  swallowed) until the backend adds it. Wired now at every challenge-scoped
  share site (`challenge_detail`, `creator_challenge_status`,
  `aura_submitted_popup` ×2, `post_score_action_screen`,
  `creator_entries_screen`) so the client is finished the moment the
  endpoint lands.

## Consequences

- Views/watch data now flows for the two highest-signal surfaces (the reels
  feed and the challenge detail page). A challenge that gets watched will
  stop reading 0.
- **Not solved by this change:**
  - Grid-feed scroll impressions (dashboard / trending / category / all
    challenges) — deferred; needs `visibility_detector` or an equivalent.
    Opening any of those still records a view via `ChallengeDetail`.
  - `shares` stays 0 until the backend ships `POST /challenges/{id}/share`
    (`docs/backend-issues/004`).
  - `totalAttempts` needs a **backend** fix to increment
    `ChallengeParticipantStats.attemptCount` on submission
    (`docs/backend-issues/004`).
  - Whether `POST /challenges/{id}/impression` alone feeds
    `CreatorChallengeStats.views`, or whether `watch-progress` is the real
    source, needs backend confirmation — the impression endpoint's own doc
    only mentions `Challenge.challengeImpressions` + the campaign engine. We
    fire both, so the client is covered either way.
- Trade-off: `recordShare` intentionally hits a non-existent endpoint and
  logs a 404 in debug builds. Accepted as the cost of not having to revisit
  6 files when the endpoint lands.

## Verification

`test/core/services/challenge_analytics_service_test.dart`: impression dedup
per session, watch-progress throttle + flush + stable/rotating `sessionId`,
share payload, and that a transport failure never propagates. Fails against
the pre-fix code (the service didn't exist / no events were sent); passes
after.

Manual: open the reels feed and a challenge detail page against the live
backend, confirm `POST …/impression` and `POST …/watch-progress` fire in the
`[API]` debug log, then reload the creator analytics screen and confirm
Views is no longer 0.
