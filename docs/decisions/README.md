# Architecture Decision Records

This folder mirrors the backend's `docs/api/../decisions/` convention
(see the [backend engineering docs](http://144.91.79.237:5173/) — "ADRs" in
the nav). Each file documents one non-trivial decision made in the Flutter
client: the problem faced, the options considered, and why we picked what we
picked.

**When to write one.** Not every commit needs an ADR — a typo fix or a color
tweak doesn't. Write one when:
- The fix required understanding *why* something broke, not just patching
  the symptom (e.g. a race condition, a protocol mismatch, a lifecycle bug).
- You chose between two or more real approaches and future-you (or a
  teammate) would otherwise have to re-derive the reasoning from scratch.
- The decision affects more than one screen/service, or sets a pattern
  other code is expected to follow.

**Numbering**: sequential, three digits, never reused even if a decision is
later superseded (mark it `Superseded by NNN` in the status instead).

**Format**: copy `TEMPLATE.md`. Keep it short — a decision nobody will read
because it's three pages long isn't documented, it's buried.

## Index

| # | Title | Status |
|---|-------|--------|
| 001 | [Deduped concurrent token-refresh + global session-expiry redirect](001-auth-session-failure-handling.md) | Accepted |
| 002 | [Upgrade `camera` to the CameraX Android backend to fix sideways recordings](002-android-portrait-video-recorded-sideways.md) | Accepted |
| 003 | [Auto-stop a challenge recording 10s after the ghost clip ends](003-post-ghost-recording-auto-stop.md) | Accepted |
| 004 | [Auto-read the login OTP from SMS (Message Central), drop the response echo](004-otp-sms-autofill-message-central.md) | Accepted |
| 005 | [Streak lives only on My Account; foreground push shows in-app, taps go to the notification list](005-streak-surface-and-foreground-push.md) | Accepted |
| 006 | [Rewards screen: coupons/bonuses + leaderboard vouchers; level-unlocks deferred](006-rewards-and-leaderboard-vouchers.md) | Accepted |
| 007 | [Screen-level stale-while-revalidate cache for tab navigation](007-screen-level-stale-while-revalidate-cache.md) | Accepted |
| 008 | [Deleted-video Aura clawback via a persisted local offset](008-deleted-video-aura-clawback-local-offset.md) | Accepted |
| 009 | [Creator dashboard shows creator-scoped stats only, not the account's player figures](009-creator-dashboard-shows-creator-scoped-stats-only.md) | Accepted |
| 010 | [Tier badge falls back to the level when the backend `tier` string is missing](010-tier-badge-falls-back-to-level-when-backend-tier-is-missing.md) | Accepted |
| 011 | [Persistent tab shell (IndexedStack) so bottom-nav switches never load](011-persistent-tab-shell-indexed-stack.md) | Accepted |
| 012 | [Client-side reporting of challenge views, watch progress and shares](012-client-side-challenge-view-share-watch-reporting.md) | Accepted |
| 013 | [`correctedVideoAspectRatio` must not invert an already-portrait `size`](013-video-aspect-ratio-double-correction-on-rotated-portrait-size.md) | Accepted |
| 014 | [Cache thumbnails/videos on a stable (unsigned) URL key](014-stable-cache-key-for-presigned-asset-urls.md) | Accepted |
| 015 | [Creator profile grid shows the creator's authored challenges, not their attempt videos](015-creator-profile-shows-authored-challenges-not-attempt-videos.md) | Accepted |
| 016 | [Coupon integration: POOL vs CATALOG sourcing, one post-score sheet](016-catalog-vs-pool-coupon-sourcing.md) | Accepted |
| 017 | [Tab shell reveals the tapped tab immediately; drop the ready-gate](017-tab-shell-reveals-immediately-no-ready-gate.md) | Accepted (amends 011) |
| 018 | [Engagement reporting realigned to the backend's view/impression definitions](018-engagement-reporting-realigned-to-backend-adr-090.md) | Accepted (amends 012) |
| 019 | [Feed-card impressions via a shared `VisibilityDetector` wrapper](019-feed-impression-instrumentation-visibilitydetector.md) | Accepted (extends 012 / 018) |
| 020 | [Home is `dashboard.dart`: pull-to-refresh, Featured carousel, device on engagement pings](020-home-screen-is-dashboard-pull-to-refresh-featured-carousel-device-pings.md) | Accepted |

For how a feature works *today* (as opposed to why a decision was made), see
[`docs/features/`](../features/).
