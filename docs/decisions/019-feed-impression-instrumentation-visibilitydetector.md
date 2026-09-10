# 019 — Feed-card impressions via a shared `VisibilityDetector` wrapper

Status: Accepted (extends [012](012-client-side-challenge-view-share-watch-reporting.md) / [018](018-engagement-reporting-realigned-to-backend-adr-090.md))

## Problem

Under the backend's definition
([backend ADR 090](http://144.91.79.237:5173/decisions/090-engagement-metrics-and-redis-buffered-counters))
an **impression** is "the challenge video appeared on the user's screen, any
feed." The client only fires `recordImpression` from two places — the reels
feed and `ChallengeDetail.initState` (see [ADR 012]). A challenge that a user
scrolls past in the dashboard, Trending, a category grid, "All Challenges" or
the brand-challenges grid produces **zero** impressions unless they tap into
it. Those grids are where most browsing happens, so impression counts (and the
`views / impressions` view-rate the analytics screens want to show) are
systematically low.

[ADR 012] listed "add `visibility_detector` and instrument every feed grid" as
option 1 and deferred it — "a new dependency and a lot of surface area for a
first cut." That first cut shipped; this is the deferred follow-up.

## Investigation

- The grids are ordinary `ListView` / `GridView` / `CustomScrollView` builders
  (`dashboard.dart` — the home screen — and its horizontal rails,
  `trending_screen.dart`, `all_general_challenges_screen.dart`,
  `category_challenges_screen.dart`, `brand_challenges_screen.dart`). None
  expose "which items are on screen right now" — a `ScrollController` offset
  would have to be mapped back to item extents per screen, differently for
  each layout.
- Flutter has no first-party viewport-visibility callback. `visibility_detector`
  (0.4.0+2, ~1 file, no native code, widely used) is the standard answer: it
  reports `visibleFraction` per keyed subtree on a debounce
  (`VisibilityDetectorController.updateInterval`, default 500ms — which also
  naturally rate-limits fast scrolls).
- Backend counts **raw sightings** (ADR 090 / [ADR 018] — the client no longer
  de-dupes), so "scroll a card away and back" must produce a second
  impression. A plain "fire once per widget lifetime" wrapper is not enough;
  it has to re-arm when the card leaves the viewport.

## Options considered

1. **Per-screen bespoke visibility math off each `ScrollController`.** No
   dependency, but six different implementations to get right and keep right,
   and horizontal rails / grids / slivers each need their own. Rejected —
   this is exactly the kind of thing that drifts.
2. **One shared `visibility_detector` wrapper widget, dropped into each
   grid's item builder.** One implementation of the "≥ threshold visible →
   fire once, re-arm when fully off-screen" rule; each screen only has to
   wrap its card and pass an id. One small dependency.
3. **Instrument at the data layer** (fire an impression when a challenge
   enters a feed *response*). Wrong signal — that is "was returned by the
   API", not "was seen", and would count a 40-item page as 40 impressions
   the moment it loads.

## Decision

Option 2. New `lib/shared/widgets/impression_tracker.dart`:

```dart
ImpressionTracker(
  detectorKey: ValueKey('imp-$challengeId'),
  onImpression: () => ChallengeAnalyticsService().recordImpression(challengeId),
  child: <the card>,
)
```

- Fires `onImpression` once when `visibleFraction` first reaches `threshold`
  (default **0.5**).
- **Re-arms** when the card goes fully off-screen (`visibleFraction == 0`), so
  a later sighting fires again — matching the backend's raw-sighting count.
- `enabled` flag (default true) so tests/previews can opt out — when false the
  child renders with no `VisibilityDetector` mounted at all.
- `detectorKey` must be stable + unique per logical item (`ValueKey` off the
  challenge id, **not** the list index). `VisibilityDetector` only tracks the
  last widget mounted with a given key.

Screens to wrap (`ChallengeAnalyticsService` already swallows failures so a
bad key can't break a feed):

| Screen | Feed | Status |
| --- | --- | --- |
| `trending_screen.dart` | trending grid | ✅ wired |
| `all_general_challenges_screen.dart` | "All Challenges" grid | ✅ wired |
| `category_challenges_screen.dart` | per-category grid | ✅ wired |
| `dashboard.dart` | home screen — Featured carousel + brand / creator / trending rails + endless grid | ✅ wired (rails via `VideoThumbnailWidget.impressionChallengeId`; Featured carousel added with ADR 020) |
| `brand_challenges_screen.dart` | brand challenges grid | ✅ wired |

`home_feed_screen.dart` was an unreferenced alternate home layout (the shell
renders `dashboard.dart`); it was deleted with ADR 020 and its pull-to-refresh
+ Featured carousel ported into `dashboard.dart`.

`test/flutter_test_config.dart` zeroes `VisibilityDetectorController.updateInterval`
globally so the detector's timer never outlives a widget test's pump cycle
(it otherwise throws inside `RenderVisibilityDetectorBase` against a torn-down
tree).

The reels feed and `ChallengeDetail` keep their existing direct
`recordImpression` calls (they already know when a challenge is *the* focused
item — no visibility math needed).

## Consequences

- Impression counts jump once each grid is wrapped — that is the gap closing,
  not inflation. Roll out screen-by-screen so the change in the analytics
  numbers is attributable.
- New dependency: `visibility_detector: ^0.4.0+2` (pure Dart, no native).
- `VisibilityDetector`'s global `updateInterval` stays at its 500ms default in
  the app (rate-limits scroll); tests set it to `Duration.zero` for
  synchronous assertions.
- A very fast fling can scroll a card through the viewport within one
  `updateInterval` and never report ≥ 50% — accepted; that is arguably not a
  real "sighting" anyway.
- `threshold` and the re-arm rule live in one file — if the product view of
  "seen" changes, it changes once.
- Not covered: horizontal rails where a card is always partially visible at
  the edge — the 0.5 threshold handles the common case; per-rail tuning is a
  follow-up if it proves noisy.

## Verification

`test/shared/widgets/impression_tracker_test.dart`:

- On-screen from the start → fires exactly once.
- Scrolled out of view (below an 800px spacer in a 600px viewport) → never
  fires.
- Scrolled **in → out → in** → fires twice (the re-arm).
- `enabled: false` → child renders, no `VisibilityDetector` in the tree, never
  fires.

`flutter test` → 4 passing. `flutter analyze` clean. Per-screen wiring will
add a light widget test per feed as it lands.
