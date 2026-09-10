# 018 — Engagement reporting realigned to the backend's view/impression definitions

Status: Accepted (amends [012](012-client-side-challenge-view-share-watch-reporting.md))

## Problem

[ADR 012](012-client-side-challenge-view-share-watch-reporting.md) stood up
`ChallengeAnalyticsService` against an *unconfirmed* backend contract — its own
Investigation section ends with "whether `POST /impression` or `watch-progress`
is the real view source needs backend confirmation … we fire both." The client
made two guesses to cover that uncertainty:

1. **`recordImpression` deduped per app session.** A challenge got at most one
   impression no matter how many times the user scrolled it back into view.
2. **`recordWatchProgress`'s first ping waited for the 3s-growth / 5s-gap
   throttle** (or the dispose-time `flush`). A genuine short view — scroll to a
   reel, watch 2s, scroll on — only reached the backend if `flush` happened to
   fire.

The backend has since defined these precisely
([backend ADR 090](http://144.91.79.237:5173/decisions/090-engagement-metrics-and-redis-buffered-counters),
`docs/features/engagement-metrics.md` in that repo), and both client guesses
are now wrong:

> **Impression** — the challenge video appeared on the user's screen, any
> feed. Counted **every time**, no de-dup, even a sub-second scroll-past.
>
> **View** — a play session with **≥ 1 second** watched. One view **per play
> session** (`sessionId`), so the same user replaying counts again. A view
> always implies an impression.

The counters are absorbed into Redis backend-side and flushed to Mongo ~every
60s, so over-reporting is cheap and the client should send the true signal, not
a pre-filtered one.

## Investigation

- Backend `impression.service.js` now calls `recordImpression()` (its Redis
  buffer) **unconditionally** for every `POST /challenges/:id/impression` —
  organic and campaign — and the old "an impression is also a view" 1:1 bump
  was removed. So the client de-dup was silently discarding real impressions
  the backend wants.
- Backend `watchAnalytics.service.js` now records a view when
  `watchedDuration >= 1`, keyed one-per-`sessionId` via `SET NX`
  (`eng:seen:{sessionId}`, 6h TTL). The client already mints one `sessionId`
  per `_WatchState` (i.e. per play, reset by `endWatchSession`) — that part
  was already right. What was missing: the first ping needs to leave at the
  1s mark, not the 3s mark, or short views are lost unless `flush` fires.
- `grep -rn "recordImpression" lib/` — call sites are the reels feed
  (`challenge_reels_screen.dart`) and `challenge_detail.dart`. Grid feeds
  (dashboard, trending, category, all-challenges) fire nothing; a challenge
  seen only in a grid produced **no** impression. Fixing that is
  [ADR 019](019-feed-impression-instrumentation-visibilitydetector.md).

## Options considered

1. **Keep the per-session impression de-dup, add a "force" flag for
   grid-feed re-appearances.** Keeps a client-side notion of "how often is
   too often" that the backend no longer has. Two sources of truth for one
   rule.
2. **Drop the de-dup entirely; let every on-screen sighting be an
   impression; send the first watch ping at ≥1s.** Matches the backend
   definition exactly. Costs more requests, which the Redis buffer is
   explicitly built to absorb.
3. **Move the ≥1s / per-session view decision fully client-side** (only fire
   `watch-progress` once, when 1s is crossed). Fragile — a dropped request
   loses the whole view, and the backend still needs the later pings for
   watch-depth (`completionPercentage`, buckets). Better to keep sending
   progress and let the backend's `SET NX` be the single de-dup point.

## Decision

Option 2. Changes to `lib/core/services/challenge_analytics_service.dart`:

- **`recordImpression(id)` no longer de-dupes.** The `_impressed` set and its
  `resetForTest()` clear are gone. Every call POSTs. The caller decides what
  "on screen" means — the reels feed on page-change, `ChallengeDetail` on
  open, and (ADR 019) an `ImpressionTracker` once per ≥50%-visible pass in
  the grid feeds.
- **`recordWatchProgress` sends the first ping of a session as soon as
  `watched >= _firstPingThreshold` (1s)**, bypassing the
  `_minGrowth` (3s) / `_minResendGap` (5s) throttle. `firstPing` is "this
  session has never sent" (`st.lastSentAt == null`). Every subsequent ping
  keeps the existing throttle; `flush: true` still overrides everything
  (except zero/negative `watched`).
- `sessionId` handling is unchanged — one per `_WatchState`, minted lazily,
  dropped by `endWatchSession()` so the next play is a new view. Doc comments
  updated to say *why* (`SET NX eng:seen:{sessionId}` backend-side).
- `recordShare` is unchanged. Doc comment corrected: shares are a synchronous
  backend write (not Redis-buffered) because a share is a deliberate action,
  not scroll telemetry.

The canonical client-side description now lives in
[`docs/features/engagement-reporting.md`](../features/engagement-reporting.md).

## Consequences

- **"Views" and "impressions" will read higher** than before for any
  challenge users revisit or replay — that is the corrected behaviour, not
  inflation. Numbers are not comparable across the backend ADR 090 boundary;
  no backfill.
- **More `/impression` and `/watch-progress` requests per session.** All
  fire-and-forget, `unawaited`, error-swallowed; the backend soaks them in
  Redis. A dropped request loses one count, never a screen.
- Grid-feed impressions still don't fire until [ADR 019] lands the
  `VisibilityDetector` wiring. Opening a challenge from a grid still records
  an impression + (if watched) a view via `ChallengeDetail`.
- The `watch-progress` throttle's steady-state 5s-gap half is still not
  unit-testable without fake time — accepted; `flush` is the path that
  matters and it is tested.
- If the backend ever changes the view threshold off 1s, `_firstPingThreshold`
  is the one constant to change.

## Verification

`test/core/services/challenge_analytics_service_test.dart` (rewritten):

- `recordImpression` fires on **every** call for the same challenge (3 calls
  → 3 POSTs). Reverting the de-dup removal makes this expect 1.
- First `recordWatchProgress` ping leaves at `watched: 1.2s` with **no
  flush**; `watched: 0.8s` with no flush sends nothing; after the first ping,
  sub-threshold ticks are throttled; `flush` gets through even below 1s;
  `sessionId` is stable within a play and changes after `endWatchSession`;
  zero/negative `watched` sends nothing even with `flush`.
- A thrown transport error and a 500 both fail to propagate to any caller.

`flutter test` → 17 passing in that file. `flutter analyze` clean on the
service.
