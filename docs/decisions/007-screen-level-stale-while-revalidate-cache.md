# 007 — Screen-level stale-while-revalidate cache for tab navigation

Status: Accepted

## Problem

Switching between the bottom-nav tabs (Home / Search / Leaderboard /
Profile) showed a full-screen spinner every time before the tab's content
appeared — reported as "the splash/loading screen appears first, then the
module loads". ADR-adjacent change 006-era work made the transition itself a
quick cross-fade (`fadeThroughRoute`, `app_bottom_nav.dart`), but the tab
you land on still re-fetched from scratch on every visit.

## Investigation

The bottom nav pushes each tab as a fresh route
(`Navigator.pushAndRemoveUntil` in `AppBottomNav._goTo`). There is no
`IndexedStack` / keep-alive shell — every tab is its own `StatefulWidget`
that fetches in `initState` and renders `Center(CircularProgressIndicator())`
until the first response. So the second, third, … visit to a tab pays the
same cold-load cost as the first, even when the data is seconds old.

`ChallengesService.fetchCategoryNameMap` already keeps a `static
Future<...>?` for exactly this reason ("categories rarely change within a
session … cached here rather than repeated per-screen"), but it's a
one-off; nothing generalised it to screen payloads.

## Options considered

1. **Keep-alive tab shell (`IndexedStack`).** Build all four tabs once,
   switch by index, never dispose. Truly instant, but a large refactor
   against this codebase's grain: every top-level screen is a pushed route
   with its own `AppBottomNav`, navigation is imperative `Navigator.push`
   everywhere, and there are no nested navigators. Per-tab navigator stacks,
   the `activeTab`/`popUntil` logic, and every screen's constructor would
   have to change. High risk for a "make it feel faster" ask.

2. **Stale-while-revalidate data cache.** Keep the push-a-fresh-screen
   navigation. A tiny in-memory store holds each screen's assembled data;
   the screen reads it synchronously in `initState` and renders it
   immediately (no spinner), then refreshes in the background and swaps in
   the fresh copy. First visit still shows a spinner; every later visit is
   instant. Small, local, fits the existing architecture.

## Decision

Option 2. New `lib/core/services/screen_cache.dart` — `ScreenCache`, a
process-lifetime `Map<String, _Entry>` with `read<T>` / `write<T>` /
`age` / `invalidate` / `invalidatePrefix` / `clear`, plus a 64-entry
oldest-first eviction cap (keys like `creator.<id>` are unbounded over a
session).

**Not persisted.** A cold start loads fresh. This avoids per-payload JSON
serialization and the risk of presenting hours-old data as current;
`age()` is available if a screen ever wants a max-age gate.

**Cleared on logout** — `ApiClient.clearSession()` calls
`ScreenCache.clear()`, so every teardown path (explicit logout, logout-all,
forced 401 sign-out) drops the previous user's cached profile / standings.

Per-screen pattern (applied to `AllGeneralChallengesScreen`,
`LeaderboardScreen`'s `_ApiBoard` Global/Friends boards,
`MyAccountScreen`, `CreatorProfileScreen`):

```dart
// initState
final cached = ScreenCache.read<T>(_key);
if (cached != null) { /* populate fields */ _loading = false; }
_load();               // still runs

// _load(): only show the full spinner when there's nothing cached;
// write ScreenCache on success; never overwrite good cached data with an
// empty/error result from a failed *background* refresh.
```

`FollowButton` gained an `onChanged` callback so `CreatorProfileScreen` can
`ScreenCache.invalidate('creator.<id>')` the moment follow state changes,
rather than waiting for the next background refresh to correct the follower
count.

## Consequences

- Second-and-later visits to Search / Leaderboard / Profile / a creator
  page render instantly; the network refresh lands underneath within ~1s.
- **First visit per session is unchanged** — still a spinner.
- **Cold start is unchanged** — nothing persisted.
- Screens show data that can be one refresh-cycle stale for a moment
  (e.g. aura points just earned, a follower count just changed). Mitigated
  by always firing the background refresh, and by explicit `invalidate` on
  known mutations (follow toggle). Not mitigated for every possible mutation
  — acceptable because the stale window is a fraction of a second and the
  fetch always runs.
- The cache is global mutable static state. Tests that mount these screens
  must `ScreenCache.clear()` in `setUp`/`tearDown` (done for the touched
  test files).
- **Follow-up (mechanical, same pattern):** `AllVideosScreen`,
  `TrendingScreen`, the category-challenges screens, and the brand page all
  still cold-load. `_ChallengeBoard` (the Leaderboard "Challenge" tab) and
  `ChallengeDetail` were left alone — the latter already renders instantly
  from constructor params.

## Verification

- `test/core/services/screen_cache_test.dart` — read/write/type-miss/age/
  invalidate/invalidatePrefix/clear/eviction.
- `test/features/challenges/screens/all_general_challenges_screen_test.dart`
  — "a revisit paints the cached grid immediately with no spinner, then
  still refreshes in the background": holds the `/challenges` response open
  with a `Completer` on the second mount so only the cache can paint the
  grid; the background call still fires (`challengeCalls == 2`). Verified it
  fails against the pre-cache screen (0 thumbnails, spinner showing).
