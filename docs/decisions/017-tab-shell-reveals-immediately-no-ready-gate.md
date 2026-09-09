# 017 — Tab shell reveals the tapped tab immediately; drop the ready-gate

Status: Accepted (amends [011](011-persistent-tab-shell-indexed-stack.md))

## Problem

Two user-reported bugs about the bottom nav:

> "While navigating between Dashboard/Home, Search, Leaderboard, and Profile,
> the navigation is very slow. Sometimes I need to click 2–3 times before the
> selected screen opens. Buttons are not working properly."

## Investigation

Two independent causes.

**1. The ready-gate freeze (ADR 011's "first-load race" mechanism).**
`MainShell._selectTab` moved the nav highlight immediately but only swapped
the visible `IndexedStack` child once the target tab called `onReady()` —
with a 5 s `_holdTimeout` fallback. Each tab reports ready only after its
first network fetch resolves (`Dashboard` after `_profileFuture`,
`AllGeneralChallengesScreen` / `LeaderboardScreen._ApiBoard` after their
first page, `MyAccountScreen` after its 7-call fan-out). API GETs carry a
15 s timeout (`api_client.dart`), so on a cold start or any slow/stalled
request the first visit to a tab sat on the *previous* screen for the full
5 s before flipping. During that window a second tap was swallowed by
`AppBottomNav._switchTab`'s `if (widget.activeTab == tab) return;` (the
highlight had already moved), so the user tapped repeatedly and waited.

**2. Tiny hit targets.** The tab items in `AppBottomNav` were bare
`GestureDetector`s with the default `HitTestBehavior.deferToChild`, wrapping
a `Column(mainAxisSize: min)` of a 22 px icon + a 9 px label. Only the
painted glyph/text pixels were tappable; the surrounding padding and the
gaps between items were dead. Near-misses did nothing — "buttons not
working," independent of cause 1.

## Options considered

1. **Make tabs report ready sooner / pre-warm fetches.** Shrinks the freeze
   window but never closes it, and adds complexity to five screens to prop
   up a mechanism whose value is marginal.
2. **Reveal the tapped tab immediately; delete the gate.** All four screens
   are always mounted in the `IndexedStack` and each already renders its own
   `ScreenSkeleton` / empty / error state while loading. Showing that for a
   beat is strictly better than freezing on the previous tab. Simpler:
   `_selectTab` becomes a one-line `setState`, and `onReady` /
   `_ApiBoard.onFirstLoad` plumbing comes out of the four screens.

## Decision

**Option 2, plus the hit-target fix.**

- `main_shell.dart` — `_selectTab(i)` is `setState(() => _tab = i)`.
  Removed `_visibleTab`/`_selectedTab` split, `_ready`, `_holdTimer`,
  `_holdTimeout`, `_markReady`, `_showTab`. `_pages` is now `const`.
- `dashboard.dart`, `all_general_challenges_screen.dart`,
  `leaderboard_screen.dart`, `my_account_screen.dart` — `onReady` param and
  `_reportReadyOnce` removed; `_ApiBoard` loses `onFirstLoad` /
  `_notifyFirstLoad`. `embeddedInShell` stays (still suppresses each
  screen's own bottom nav / back affordance).
- `app_bottom_nav.dart` — `behavior: HitTestBehavior.opaque` on the tab
  `GestureDetector`s (`_navItem`, `_profileNavItem`) and the centre FAB, so
  the whole padded area registers the tap.

Unchanged: the `IndexedStack` keep-alive, `MainShellController`, the
`popUntil(isFirst)`-then-`select` flow from drill-down screens, the
`ScreenSkeleton` full-screen loading states from ADR 011.

## Consequences

- Every tab switch takes effect on the next frame. The first visit to a tab
  whose data hasn't arrived shows that tab's skeleton instead of a stalled
  previous screen; subsequent visits are instant (keep-alive, as before).
- The `onReady` first-content signal no longer exists. Nothing else
  consumed it; if a future feature needs "tab has content," add it back
  deliberately rather than reviving the gate.
- ADR 011's "First-load race" bullet and the last bullet of its
  Verification section no longer describe the code.

## Verification

- `test/features/shell/main_shell_test.dart` — new test *"reveals a
  still-loading tab immediately instead of freezing on the current one"*:
  with the `/leaderboard` call gated, tapping Leaderboard shows
  `LeaderboardScreen` (with its `ScreenSkeleton`) on the next frame and
  `Dashboard` is gone. Fails against the pre-change shell (the hold keeps
  `Dashboard` on screen). Existing keep-alive / no-refetch tests still pass;
  the old "holds on the current tab…" test was replaced.
- `test/shared/widgets/app_bottom_nav_test.dart` — new test *"a tap on the
  tab item padding (not the icon/label) still switches"*: `tapAt` the
  top-left corner of the Leaderboard item's `GestureDetector` rect (inside
  the padding, clear of the glyph) still fires `select(2)`. Fails without
  `HitTestBehavior.opaque`.
- `flutter analyze` clean (pre-existing infos only).
