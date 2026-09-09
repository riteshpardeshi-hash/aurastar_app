# Backend gap: challenge Views / Shares / Attempts analytics counters never populate

**Reported:** 2026-09-07
**Status:** RESOLVED (2026-09-09) — backend shipped all three writers; see [Resolution](#resolution-2026-09-09).
**Severity:** Medium — creator & brand analytics are unusable; every challenge reads 0 views / 0 shares / 0 attempts regardless of real activity
**Affected endpoints:**
- `GET /creator/challenges/{id}/analytics` (`views`, `shares`, `totalAttempts`)
- `GET /creator/challenges/{id}/analytics/engagement` (`totalViews`, `shares`)
- `GET /creator/challenges/{id}/analytics/shares` (`totalShareClicks`)
- `GET /creator/challenges/{id}/stats` (`views`, `attempts`)
- `GET /creator/dashboard/...` creator-wide `views`
**Related:** `POST /challenges/{id}/impression`, `POST /challenges/{id}/watch-progress`, `POST /challenges/{id}/submissions`, `CreatorChallengeStats`, `CreatorDailyAnalytics`, `ChallengeParticipantStats`

## Symptom (product requirement not met)

Product wants the creator/brand analytics Views, Shares and Attempts figures
to reflect actual mobile activity. Today they are permanently `0` for every
challenge, including live challenges with participants, submissions and
scores.

## Investigation

Spec fetched from `http://144.91.79.237:3786/docs/openapi.yaml` on
2026-09-07.

### 1. Views — client wasn't firing the events (fixed client-side), source-of-truth unconfirmed

The spec documents two events the **mobile app** is expected to fire:

- `POST /challenges/{id}/impression` — *"Fired by the mobile app when this
  Challenge becomes visible inside the feed … bumps
  `Challenge.challengeImpressions`"*
- `POST /challenges/{id}/watch-progress` — *"Fired repeatedly by the mobile
  app while a challenge's video is being watched … Upserts one
  `ChallengeWatchAnalytics` row"*

The Flutter client fired **neither** (zero call sites). Fixed on `prototype`
— see ADR 012 / `ChallengeAnalyticsService`. The client now fires both from
the reels feed and the challenge detail page.

**Open question for the backend team:** which event actually increments the
`views` / `CreatorChallengeStats.views` / `CreatorDailyAnalytics` value the
creator-analytics endpoints return? The `impression` endpoint's doc only
mentions `Challenge.challengeImpressions` and the Campaign engine, not the
creator-analytics `views` field. If `views` is fed from something else
entirely (or nothing yet), please wire it to `impression` and/or
`watch-progress`.

### 2. Shares — no ingestion endpoint exists at all

- `GET /creator/challenges/{id}/analytics/shares`: *"No per-platform share
  tracking exists anywhere in this codebase yet."*
- `GET /admin/analytics/challenges/{id}/cities` `shareRate`: *"Always 0 — no
  data source exists to compute this honestly."*

There is nowhere for the client to report a share. Every share in the app is
a native OS share sheet.

### 3. Attempts — client submits correctly; the counter isn't derived from it

`totalAttempts` is documented as *"Summed from
`ChallengeParticipantStats.attemptCount`"*. The client already creates every
attempt via `POST /challenges/{id}/submissions`. If attempts still read 0
with real submissions present, `attemptCount` (or the challenge↔participant-
stats linkage) is not being written in the submission pipeline — same shape
as issue 002 (`GET /profile/videos` linkage).

## Requested backend changes

1. **Confirm / wire the `views` source.** State which event increments the
   creator-analytics `views` counter, and wire `POST /challenges/{id}/impression`
   and/or `POST /challenges/{id}/watch-progress` into
   `CreatorChallengeStats.views` + the `CreatorDailyAnalytics` daily rollup.

2. **Add a share-event endpoint.** Proposed, matching the existing
   `/impression` + `/watch-progress` sibling shape:

   ```
   POST /challenges/{id}/share
   Authorization: Bearer <token>
   { "platform": "instagram_story" }   // optional, free-form
   → 200 { status: "success" }
   ```

   Increment `CreatorChallengeStats` share count (and, ideally, a daily
   `CreatorDailyAnalytics.shares` bucket so the trends endpoint can drop
   `sharesTrend` from its `unavailable` list). `platform`, when present,
   should feed `CreatorShareAnalytics.platformDistribution`. The client
   already calls this path from every challenge-scoped share site (ADR 012);
   it's a harmless 404 until the endpoint ships.

3. **Increment `ChallengeParticipantStats.attemptCount`** (and set
   `firstAttemptAt` / `lastAttemptAt`) inside `POST /challenges/{id}/submissions`,
   including for `flagged` submissions, so `totalAttempts` and the
   participant analytics reflect reality.

## Client status (on `prototype`)

- `impression` + `watch-progress`: **firing now** from the reels feed
  (`onPageChanged` + first page) and `ChallengeDetail` (open + player
  progress, throttled, flushed on dispose). Grid-feed scroll impressions are
  not yet wired (needs a visibility detector); opening a challenge still
  counts.
- `share`: **firing now** to `POST /challenges/{id}/share` from all 6
  challenge-scoped share actions — no-op until the endpoint exists.
- `attempts`: nothing to do client-side; submissions are already posted
  correctly.

## To reproduce

1. As a creator, publish a challenge; have ≥1 other account watch its reel,
   share it, and submit a scored entry.
2. Open the creator analytics screen for that challenge.
3. Views / Shares / Total Attempts all read `0` (expected: non-zero).

## Resolution (2026-09-09)

All three requested backend changes landed. Confirmed against the backend
repo (`aura-arena/backend`) + the live OpenAPI spec.

1. **`views` source — wired.** Backend ADR 086 added
   `utilities/challengeStats.js#bumpChallengeStat`. The **first**
   `watch-progress` ping per `(challenge, player)` bumps
   `CreatorChallengeStats.views` (`watchAnalytics.service.js`). Backend
   ADR 089 then added the matching `CreatorDailyAnalytics.views` +1 at the
   same point, so the daily/trend series moves too. `POST /impression` also
   bumps both, but **only for a challenge in an ACTIVE paid Campaign** — for
   an organic challenge it's a no-op, so `watch-progress` is the organic
   source. `ChallengeAnalyticsService` fires both; no client change needed.

2. **Share endpoint — shipped**, exactly the proposed shape. `POST
   /challenges/{id}/share` → `challenges.service.js#recordShare` bumps
   `CreatorChallengeStats.shares` (ADR 086) and `CreatorDailyAnalytics.shares`
   (ADR 089). The `platform` body field is accepted but **not yet stored** —
   `CreatorShareAnalytics.platformDistribution` remains a backend follow-up.
   `ChallengeAnalyticsService.recordShare` already sends it; nothing to change
   client-side.

3. **`attemptCount` — already incremented.** `creatorParticipants.service.js`
   (`inc = { attemptCount: 1, totalAuraEarned }`) and the admin participant
   aggregations read it. `totalAttempts` reflects real submissions.

**Still open (backend follow-ups, not blocking this issue):**
- Per-platform share attribution (`platformDistribution`).
- Grid-feed scroll impressions on the client (needs a visibility detector);
  opening a challenge still records a view via `ChallengeDetail`.
