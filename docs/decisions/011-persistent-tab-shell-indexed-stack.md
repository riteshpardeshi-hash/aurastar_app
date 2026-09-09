# 011 — Persistent tab shell (IndexedStack) so bottom-nav switches never load

Status: Accepted — the "First-load race" hold below was removed in
[ADR 017](017-tab-shell-reveals-immediately-no-ready-gate.md); the tab now
reveals immediately and `onReady` no longer exists.

## Problem

Switching between the four bottom-nav tabs (Home / Search / Leaderboard /
Profile) showed a full-screen loading spinner. `AppBottomNav` pushed a fresh
route per tab (`pushAndRemoveUntil(fadeThroughRoute(...), isFirst)`), so the
destination rebuilt from scratch every time, re-ran `initState`, and
re-fetched. ADR 007's `ScreenCache` only hid that spinner from the *second*
visit onward in a session.

User requirement: tab switches must have **no loading at all — only a smooth
transition** — every time, including the first switch after launch, with
scroll position preserved.

## Investigation

The push-per-tab model is the root cause: a destroyed-and-recreated screen
*must* reload. `ScreenCache` (ADR 007) papers over it but can't cover a
first visit, and it doesn't preserve scroll or in-flight controllers.

The standard fix for a tab UI is a persistent shell: build all tabs once,
keep them all mounted, and switch which one is visible. Flutter's
`IndexedStack` does exactly this.

## Options considered

1. **Persist `ScreenCache` to disk.** Every tab renders last-known content
   instantly on a cold start. Smaller change, but scroll position still
   resets, `initState`/fetch still re-run each visit, and a genuine
   first-ever visit (fresh install) still has nothing to show.
2. **Persistent `IndexedStack` shell.** All four tab screens mounted once,
   switching is an index change: no rebuild, no re-fetch, no spinner, scroll
   kept. Chosen. Bigger change — `AppBottomNav` stops pushing routes,
   `main.dart` lands on the shell, the four screens drop their own bottom
   nav and back buttons when embedded.

## Decision

**Option 2.**

- `lib/features/shell/main_shell.dart` — `MainShell` holds
  `IndexedStack(index: _visibleTab, children: [Dashboard, Search,
  Leaderboard, MyAccount])` and one shared `AppBottomNav`. The switch is a
  plain `setState` on the index (no `AnimatedSwitcher` — wrapping the
  IndexedStack in one would mount two of them over the same page elements
  mid-transition and lose their state; the point here is that state is never
  lost).
- `lib/features/shell/main_shell_controller.dart` — a broadcast-stream
  singleton. `AppBottomNav._switchTab` does
  `Navigator.popUntil(isFirst)` (a no-op on a shell tab; pops back to the
  shell from a drill-down screen stacked above it) then
  `MainShellController.instance.select(index)`. The shell listens and
  switches.
- Each of the four screens gains `embeddedInShell` (default `false`) and
  `onReady`. When embedded they drop their own `AppBottomNav` and back
  affordance, and call `onReady` once first content is displayable.
  Standalone use (e.g. Search/Leaderboard pushed from a creator screen) is
  unchanged.
- **First-load race** (a tab tapped in the ~1 s before its background
  preload finished): the shell *holds* on the current tab —
  `_selectedTab` (nav highlight) moves immediately, `_visibleTab` only
  follows once that tab reports `onReady`, or after a 5 s safety timeout.
  No skeleton or spinner in the common case. The remaining full-screen
  loading states in the four screens were swapped from
  `CircularProgressIndicator` to a `ScreenSkeleton` shimmer for the rare
  timeout path.
- `main.dart` and the four "reset to home" push sites
  (`setup_screen`, `post_score_action_screen`,
  `creator_challenge_submitted_screen`, `preview_screen`) now target
  `MainShell` instead of `Dashboard`.

Relationship to ADR 007: `ScreenCache` stays — it still serves screens
pushed standalone and warms the shell's first build within a process. It is
no longer the mechanism for tab-switch smoothness.

## Consequences

- Tab switches are a single frame: no rebuild, no network, no spinner,
  scroll position and TabController state preserved.
- All four screens' `initState` timers/controllers now live for the whole
  session instead of being recreated per visit — Dashboard's 20 s profile
  poll and `PushNotificationService().initialize()` run once, which is an
  improvement, but the four screens are permanently in memory.
- Deep links, session-expiry, notification taps, and the centre-FAB reels
  feed are untouched — they still push/replace on the root navigator above
  the shell.
- Drill-down screens keep their own push-based navigation and their own
  `AppBottomNav`; from one, a tab tap pops to the shell then switches.
- `fadeThroughRoute` (`core/utils/page_transitions.dart`) is now unused by
  app code; the file and its test are kept for now.

## Verification

- `test/features/shell/main_shell_test.dart` — all four pages built on
  mount; switching to a ready tab shows it with **no
  `CircularProgressIndicator`**; switching away and back does not re-fetch
  (request count stays 1 — proves keep-alive); the shell holds on the
  current tab while a gated load is pending, then switches when it resolves.
- `test/shared/widgets/app_bottom_nav_test.dart` rewritten for the new
  contract: a non-active tab tap calls `Navigator.popUntil(isFirst)` and
  `MainShellController.instance.select(index)`; the active tab is a no-op.
- Full suite: 295 passing, no regressions (two unrelated pre-existing
  failures on the branch are untouched).
- Manual: from Home, tap Profile/Search/Leaderboard repeatedly → instant,
  no spinner, scroll retained; cold relaunch then immediately tap Profile →
  Home holds until Profile's data lands, then switches; deep link and
  forced 401 still behave.
