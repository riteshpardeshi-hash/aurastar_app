# 016 — Coupon integration: POOL vs CATALOG sourcing, one post-score sheet

Status: Accepted

## Problem

The backend shipped its full coupon/offer system (ADRs 082–084, backend PRs
#94, #96–#99) and handed us `MOBILE-COUPON-INTEGRATION.md`. The client only
had the older, narrower slice from ADR 006:

- `createSubmission` read a single `data.grantedVouchers` array — a name the
  backend has since **removed**.
- The post-score sheet (`granted_vouchers_sheet.dart`) only knew "leaderboard
  voucher with a code", one layout.
- Level-gated coupons ("reach level N → coupon") were explicitly deferred in
  ADR 006 as *not in the backend* — they now exist.
- Nothing understood `sourcing` (`POOL` vs `CATALOG`), so a partner-catalog
  deal (code-less, "shop at the merchant") would have rendered as a broken
  code-only card.

## Investigation

Read `MOBILE-COUPON-INTEGRATION.md` end to end. The relevant contract:

- `POST /challenges/:id/submissions` now returns coupons in **two** arrays —
  `data.levelUpOffers[]` (crossed a level boundary with a `LEVEL` offer) and
  `data.leaderboardOffers[]` (entered an offer's top-N rank band). Same entry
  shape; the doc says to **concatenate** them and treat uniformly.
- The only per-entry branch the app needs is `sourcing`:
  - `POOL` — a real single-use code. Show `code` big/copyable; `redeemUrl`
    (optional) is the brand's own page.
  - `CATALOG` — a partner-network deal. Primary CTA opens `redeemUrl`, which
    is **always our own `/api/v1/r/:grantId` redirect** (a plain GET, no auth;
    302s through the affiliate network with an attribution `subid`). `code`
    may be present or `null`.
- Also on the response: `data.auraBalance` (running total) and `data.levelUp`
  (`{leveledUp, oldLevel, newLevel}` or null).
- `GET /profile/offer-vouchers` gains `?type=level|leaderboard`. Its rows do
  **not** carry `sourcing`/`merchantName` — the doc says infer CATALOG from
  `redeemUrl` containing `/r/`.
- Every grant also lands in `GET /profile/rewards` (`rewardType:
  "coupon_code"`) and `GET /profile/offer-vouchers`, so a missed sheet is
  never a lost coupon.

## Options considered

1. **Keep two separate arrays through the client.** Rejected — the doc is
   explicit that the app should not disambiguate level-up vs leaderboard for
   the celebration; concatenation is simpler and matches "one card per
   entry".
2. **Add `webview_flutter` and host `/r/:grantId` in a real in-app WebView.**
   Rejected for now — a new native dependency for what the doc says is fine to
   do in "an in-app browser / WebView (or the system browser)".
   `LaunchMode.inAppBrowserView` (SFSafariViewController / Chrome Custom Tabs)
   already ships with `url_launcher` and gives the in-app feel with no new
   surface area.
3. **Also consume `data.auraBalance` / `data.levelUp` to drive the wallet
   header and level-up animation from the submission response.** Deferred —
   the dashboard already updates the wallet and fires `LevelUpSheet` off its
   own profile stream (comparing the server's `tierName` across fetches).
   Wiring a second path risks double-firing the modal. The two fields are
   parsed and returned by `createSubmission` for a future caller, but nothing
   consumes them yet.

## Decision

- `ChallengesService.createSubmission` now returns
  `({submission, coupons, auraBalance, levelUp})`. `coupons` is
  `levelUpOffers ++ leaderboardOffers`; `data.grantedVouchers` is still
  accepted as the pre-rename name for `leaderboardOffers`.
- `granted_vouchers_sheet.dart` → **`coupons_sheet.dart`**
  (`showCouponsSheet`). One `_CouponCard` per entry, branching on
  `couponIsCatalog(entry)` — `sourcing` when present, else `redeemUrl`
  contains `/r/`:
  - CATALOG: primary **"Shop now"** → `redeemUrl`; `code` shown copyable if
    non-null; `merchantName` caption.
  - POOL: big copyable `code`; secondary **"Open offer"** → `redeemUrl`.
  - Both link kinds open via `LaunchMode.inAppBrowserView` (an in-app browser
    tab — SFSafariViewController / Chrome Custom Tabs) so the user never
    leaves the app; `url_launcher` falls back to the external browser if a
    platform can't honour it.
  - Title `voucherLabel ?? offerName`, subtitle `reason` verbatim, footer
    relative `claimExpiresAt`.
- `RewardsService.fetchOfferVouchers({String? type})` passes `?type=` through.
- `RewardsScreen._VoucherCard` gained CATALOG rendering (infer from
  `redeemUrl`), a "Shop now" label + code-less CTA path, a `merchantName`
  caption, and a level-vs-rank origin label (`levelAtGrant` → "Level N
  reward", else `rankAtGrant` → "Rank #N").

## Consequences

- One code path for both coupon kinds; a new `scope`/`sourcing` value from the
  backend degrades to the POOL layout rather than crashing.
- `/profile/offer-vouchers` CATALOG detection is heuristic (URL substring)
  until the backend adds `sourcing` to those rows — noted in
  `MOBILE-COUPON-INTEGRATION.md §5` as a small backend change to request.
- The push-notification `reward_awarded` deep link (doc §6) is **not**
  wired — the app deliberately routes every notification tap to the list
  (see `main.dart`); revisit if per-type deep links land generally.
- Multi-level jumps: the instant response only carries the highest level's
  coupons; the rest arrive within ~10 min via a backend sweep + notification.
  The sheet doesn't claim to be exhaustive, and RewardsScreen re-fetches on
  open, so they surface there.
- `data.auraBalance` / `data.levelUp` are now available but unused — a
  follow-up if we ever want the post-score screen to be self-sufficient.

## Verification

- `test/core/services/challenges_service_test.dart` — `coupons` concatenates
  level-up then leaderboard; `grantedVouchers` still accepted; `auraBalance` /
  `levelUp` parsed; empty defaults.
- `test/features/challenges/widgets/coupons_sheet_test.dart` — POOL shows code
  + "Open offer"; CATALOG shows "Shop now" + code + merchant caption;
  code-less CATALOG still shows "Shop now"; `sourcing` inferred from a `/r/`
  URL; header pluralises; Done dismisses.
- `test/core/services/rewards_service_test.dart` — `?type=level` passed
  through.
- Reverting `challenges_service.dart` to read `grantedVouchers` only makes the
  concatenation + level-up test fail; reverting the sheet's CATALOG branch
  makes the "Shop now" tests fail.
