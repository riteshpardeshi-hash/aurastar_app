# 018 — Bottom nav row can't overflow; full-slot hit targets; clamped text scale

Status: Accepted

## Problem

Field reports: on "some mobiles" the bottom-nav tabs — Leaderboard and
Profile in particular — didn't respond to taps, or needed 2–3 tries. Never
reproduced on the primary test devices.

## Investigation

`AppBottomNav` (`lib/shared/widgets/app_bottom_nav.dart`) is the single
bottom nav for every top-level screen. Its nav bar was a `Row` with
`MainAxisAlignment.spaceAround` and five children (Home, Search, a 58px
spacer for the centre FAB, Leaderboard, Profile). Each label was a `Text`
at `fontSize: 9` with **no `maxLines` / `TextOverflow`**, and nothing in
the app clamps `MediaQuery.textScaler`, so the OS font-size setting flowed
straight through.

On a narrower device (≤360dp logical width, 320dp phones, split-screen)
and/or with the OS font size raised — extremely common on Android — the
row's intrinsic width exceeds the pill. Flutter clips the overflow (the
debug-only yellow/black stripe; silent in release) and **does not deliver
pointer events to the clipped-out region** (`RenderBox.hitTest` gates on
`size.contains(position)` regardless of `Clip.none`). The children pushed
past the right edge are the last ones — Leaderboard, Profile — so exactly
those go dead. Reverting the fix and pumping the widget at 320dp / 1.5×
font reproduces it as a `RenderFlex overflowed by 197 pixels` and taps that
miss.

Two contributing hazards found in the same widget:

- **Sub-minimum tap targets.** Each item was `Icon(22)` + 3 + a ~11px label
  ≈ 36px tall — below the 48px (`kMinInteractiveDimension`) minimum — so
  near-misses on imprecise touch panels failed even without overflow.
- **Opaque square FAB hit box.** The centre action button used
  `HitTestBehavior.opaque` on a 56×56 *square* `Container`, centred over a
  58px gap (~1px clearance). As the last `Stack` child it's hit-tested
  first; on tight layouts the inner edge of Search / Leaderboard slid under
  the square and those taps opened the reels feed or landed dead.

## Options considered

1. **Shorten the labels / drop labels below a width threshold** — "Ranks"
   instead of "Leaderboard", etc. Buys headroom but doesn't remove the
   failure mode: a large enough font still overflows, and it's a
   copy/behaviour change driven by a layout bug.
2. **Wrap each item in `Flexible` and keep `spaceAround`** — stops the hard
   overflow but `spaceAround` still distributes negative free space oddly
   and the items don't get equal, predictable widths.
3. **Equal-width `Expanded` slots + ellipsised labels + clamped text scale**
   — the row can't overflow by construction (four equal slots + one fixed
   spacer), labels degrade to `…` instead of pushing width, and the bar
   caps text scaling at 1.2× so a huge system font can't blow out the
   9px-label layout.

## Decision

Option 3.

- Nav bar row is now `Expanded` slots (Home, Search, Leaderboard, Profile)
  with a fixed `SizedBox(width: 64)` spacer for the FAB. Equal slots, no
  overflow path.
- Every slot fills the full 62px pill height (`SizedBox(height: _pillHeight)`
  inside the opaque `GestureDetector`), so the tap target is the whole
  slot, not the glyph+label stack.
- Labels are `maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis`.
- `build` is wrapped in `MediaQuery.withClampedTextScaling(maxScaleFactor:
  1.2)` — scoped to the bar only.
- The FAB is now a full-width centred `Positioned` whose opaque hit box
  stays a fixed 56px square inside the 64px spacer, so it can't overlap the
  slots either side.

## Consequences

- The bar is tappable across width × font-scale combinations; taps hit a
  full-height slot.
- On very narrow layouts at large fonts "Leaderboard" ellipsises
  ("Leaderboa…"). Accepted — a clipped label that still switches tabs beats
  a full label that doesn't.
- The bar ignores OS font scale above 1.2×. This is the one surface where
  that's deliberate; if app-wide text-scale support is added later, this
  clamp should stay.
- Pattern for future nav/toolbar rows with fixed-size labels: equal
  `Expanded` slots + ellipsis + a scoped text-scale clamp, never
  `spaceAround` with bare `Text`.

## Verification

Regression tests in `test/shared/widgets/app_bottom_nav_test.dart`:

- *"Leaderboard and Profile stay tappable on a 320dp screen at 1.5x font"*
- *"Leaderboard and Profile stay tappable at 2x OS font scale"*

Both pump `AppBottomNav` at a constrained view size + `TextScaler`, assert
no `RenderFlex` overflow exception, and tap `Leaderboard` then `Profile`
expecting the matching `MainShellController` selections. Verified to fail
against the pre-fix widget (`RenderFlex overflowed by 197 / 283 pixels`)
and pass after. A third test pins that the centre FAB doesn't swallow an
inner-edge tap on the Search slot. Full suite green; `flutter analyze`
clean.
