# 020 — Home is `dashboard.dart`: pull-to-refresh, Featured carousel, and device on engagement pings

Status: Accepted

## Problem

Three home-screen items reported broken from testing:

1. **Pull-to-refresh on the home feed does nothing.**
2. The **admin-curated Featured carousel** (ADR 092 backend) never appears — the
   home screen still shows a single hardcoded-fallback hero card.
3. On the admin panel's Challenge 360° **Device Distribution**, a real Android
   tester shows up as **Unknown**.

## Investigation

- Items 1 and 2 were implemented — but in **`lib/features/home/screens/home_feed_screen.dart`**
  (`RefreshIndicator` + `_tick` key bump; `_FeaturedHeroCard` carousel). That
  file is **dead code**: `grep -rn HomeFeedScreen lib/` returns only its own
  definition. `main_shell.dart`'s Home tab renders **`Dashboard(embeddedInShell: true)`**
  (`lib/features/dashboard/dashboard.dart`), and has for a while — `home_feed_screen`
  was an earlier alternate layout that `main_shell` was switched away from.
  Neither feature was ever on screen.
  - `dashboard.dart`'s real feed is a `CustomScrollView` (in `_buildScaffold`)
    with **no `RefreshIndicator`**, and its `_buildHeroSection` shows
    `_challengesFuture.first` (a `system` challenge, fallback title
    `"Bollywood Walk"`) — not `HomeService().fetchFeatured()`.
- Item 3: the backend's Device Distribution (backend ADR 093) reads the
  platform each engaged user **watched on** (`ChallengeWatchAnalytics.device`),
  falling back to their push-token platform (`DeviceToken.platform`). This
  client **never sent `device`** on `watch-progress` (`recordWatchProgress`
  body was `watchedDuration` / `videoDuration` / `sessionId` only), and on the
  test rig push registration never completes (device can't reach Play
  Services; local backend has no SNS platform app). Both sources empty →
  Unknown.

## Options considered

1. **Wire `HomeFeedScreen` into `main_shell` as the Home tab.** One line, both
   features light up. But `HomeFeedScreen` is a leaner, different layout —
   missing the points/level header, streak banner, pending-upload banner,
   level-up sheet, admin button, and the 20s profile freshness poll that
   `Dashboard` has. Swapping is a large silent regression.
2. **Port the features into `dashboard.dart`** (the live screen) and delete the
   dead file. More diff, no regression, features land where they're seen.
3. Device: send an `X-Client-Platform` header from `ApiClient` on every
   request and persist it backend-side. Broader surface; the engagement pings
   already have a `device` field the backend already stores.

## Decision

**Option 2 + option 3-scoped-to-the-pings.**

- `dashboard.dart`:
  - `_challengesFuture` / `_trendingCreatorsFuture` are no longer `final`;
    `_refresh()` reassigns them (+ re-loads the profile header, + bumps
    `_refreshTick`) and awaits the primary futures so the spinner holds.
  - `_buildScaffold`'s `CustomScrollView` is wrapped in `RefreshIndicator`
    (`onRefresh: _refresh`) with `AlwaysScrollableScrollPhysics`. The first
    sliver is a plain box (no `SliverAppBar`), so the pull gesture reaches the
    indicator cleanly.
  - `_buildHeroSection` is replaced by `_FeaturedCarousel` (ported from
    `home_feed_screen.dart`'s `_FeaturedHeroCard`): `HomeService().fetchFeatured()`,
    auto-advances every 4s, each card `SlideTransition`s in from the left,
    dots indicator, prewarms the current video, renders `SizedBox.shrink()`
    when nothing is featured. Keyed on `_refreshTick`.
- `lib/features/home/screens/home_feed_screen.dart` **deleted**.
- `ChallengeAnalyticsService`: a `_clientPlatform` getter
  (`kIsWeb ? 'web' : switch (defaultTargetPlatform) android/iOS → 'android'/'ios'`,
  else `'unknown'`) is now sent as `device` on both the `watch-progress` and
  `impression` request bodies. The backend already persists
  `ChallengeWatchAnalytics.device` from that field.

## Consequences

- Pull-to-refresh and the admin Featured carousel are live on the actual home
  screen. The old always-present hero card is gone — when no challenge is
  featured, the carousel simply collapses (matches the ADR 092 intent: only
  admin-picked challenges show in the Featured widget). If a permanent
  fallback hero is wanted, that's a follow-up.
- Device Distribution attributes a viewer to android/ios the moment they watch
  one video, with no dependency on push registration.
- `home_feed_screen.dart` is gone; ADR 019's impression-instrumentation table
  is updated. Any future home-screen work goes in `dashboard.dart`.
- `defaultTargetPlatform` on desktop/other returns `'unknown'` — acceptable,
  the app targets Android/iOS.

## Verification

- `test/core/services/challenge_analytics_service_test.dart` — `recordVideoView`
  now also asserts the `device` field is present on the ping.
- `flutter analyze` clean (pre-existing style infos only); the engagement +
  impression-tracker suites pass.
- Manual: pull down on Home → spinner + shelves re-fetch; with an
  `isFeatured` challenge set via the admin panel, the Featured carousel shows
  and auto-advances; Challenge 360° Device Distribution shows Android after a
  watch.
