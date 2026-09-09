# 006 — Rewards screen: coupons/bonuses + leaderboard vouchers; level-unlocks deferred

Status: Accepted

## Problem

Two coupon mechanics were requested for players:

1. **Level-gated** — reaching a level (e.g. 5) unlocks a coupon.
2. **Leaderboard-gated** — finishing in a challenge leaderboard's top N wins a coupon.

The client already integrates `GET /profile/rewards` + `POST /profile/rewards/{id}/claim`
as an inline "MY REWARDS" list on the My Account screen. Nothing else about
coupons/vouchers is wired.

## Investigation

Re-fetched the live OpenAPI spec (`http://144.91.79.237:3786/docs/openapi.yaml`).
The backend has **two separate reward systems**, and only one of the two requested
mechanics maps to anything that exists:

**A. UserReward ledger** — `GET /profile/rewards`, `POST /profile/rewards/{id}/claim`.
`rewardType` is `aura_points` or `coupon_code`; a coupon hides its `couponCode`
until claimed. `reason` ∈ `{streak_completion, leaderboard_top, admin_manual,
brand_challenge, challenge_participant_target}`. `RewardTemplate` (admin-only) is
just `name/description/type/auraAmount/couponValue` — **no trigger or criteria
field**. Admin assigns via `POST /admin/rewards/assign` (manual) or the backend
auto-assigns for those five reasons.

**B. Leaderboard Offers / vouchers** (backend ADR 082) — a brand creates a
`LeaderboardOffer` scoped to a challenge/campaign with a `rankLimit` and a code
pool. The scoring pipeline grants a voucher the instant a submission moves the
player into the top-`rankLimit` band (also returned as `data.grantedVouchers[]`
on `POST /challenges/{id}/submissions`, and a 10-min cron backstop). Player
endpoints: `GET /profile/offer-vouchers` (paginated: `code`, `reason`,
`rankAtGrant`, `status` ∈ `{GRANTED, REDEEMED, EXPIRED}`, `grantedAt`,
`claimExpiresAt`, `redeemUrl`; also mirrored into `GET /profile/rewards`) and
`POST /challenges/{id}/offers/claim` (a separate "legacy claim pool": pull one
still-`AVAILABLE` code, once per player, challenge must be LIVE).

**Mechanic 2 = Leaderboard Offers.** Fully built backend-side, zero client
integration.

**Mechanic 1 (level-gated) has no representation in the spec.** No level-based
`reason`, no criteria field on templates, no "locked/upcoming rewards" or
unlock-threshold endpoint. The only "level" construct is a `level_up`
*notification* type. The client cannot build this against a contract that
doesn't exist.

## Options considered

1. **Build both now** — impossible; mechanic 1 has no endpoint to call.
2. **Hold everything until the backend confirms both** — rejected by the product
   owner; mechanic 2 is specced and shippable today.
3. **Build mechanic 2 now; flag mechanic 1 back to the backend team** (chosen).
4. **UI: keep expanding the inline My Account section** vs **a dedicated Rewards
   screen**. Chose the dedicated screen (consistent with ADR 005's "keep My
   Account uncluttered"); My Account keeps a one-line teaser that taps through.

## Decision

- **New `lib/core/services/rewards_service.dart`** owns all player reward calls:
  `fetchRewards` / `claimReward` (moved out of `AuthApiService`), plus
  `fetchOfferVouchers` (`GET /profile/offer-vouchers`) and `claimChallengeOffer`
  (`POST /challenges/{id}/offers/claim`). `_extractList` unwraps the documented
  `PaginatedList` envelope for `/profile/rewards` and falls back across key names
  (`responses`/`vouchers`/`grants`/…) for `/profile/offer-vouchers`, which the
  spec types only as a generic success envelope.
- **New `lib/features/account/screens/rewards_screen.dart`** — two sections:
  *Coupons & Bonuses* (the moved `_RewardCard` UI, claim reveals the code) and
  *Leaderboard Vouchers* (new `_VoucherCard`: offer name, value, rank, status
  pill, tap-to-copy code, "Redeem" → opens `redeemUrl` externally via
  `url_launcher`, expiry countdown). Per-section empty states.
- **My Account** — the inline `_RewardsSection`/`_RewardCard` are removed; a
  `_buildRewardsRow` teaser ("Rewards & Vouchers", badge = coupon rewards still
  `active`) pushes `RewardsScreen` and reloads the badge on return.
- **`claimChallengeOffer` is added but wired to no UI.** No player-facing field
  signals which challenges have a claimable pool; the method is there so the
  entry point is a one-liner once the backend surfaces that.
- **`data.grantedVouchers` post-score sheet.** `ChallengesService.createSubmission`
  now returns a record `({submission, grantedVouchers})`. `preview_screen.dart`
  shows `showGrantedVouchersSheet` (a modal bottom sheet — trophy header, per
  voucher: name/value/rank, tap-to-copy code, "Redeem now" → `redeemUrl`,
  expiry) after `AuraSubmittedPopup` closes and before routing on, whenever
  `grantedVouchers` is non-empty. The same vouchers remain on RewardsScreen; the
  sheet is only the moment-of-delight.

## Consequences

- Level-gated coupons are **not delivered**. Blocked on the backend exposing an
  endpoint that lists level-gated rewards with their thresholds and per-user
  lock state. Flagged to the backend team; revisit when that contract exists.
- Vouchers have no in-app "mark redeemed" action — status transitions happen on
  the brand's redemption site. The app shows the code and opens `redeemUrl`;
  `status` just reflects backend state on next load.
- `/profile/offer-vouchers` has no documented item schema, so `_VoucherCard`
  reads fields defensively (`rankAtGrant`/`rank`, `offerName`/`voucherLabel`).
- Reward calls moved off `AuthApiService`; the three reward tests moved from
  `auth_api_service_test.dart` to `rewards_service_test.dart`.

## Verification

- `test/core/services/rewards_service_test.dart` (9) — endpoint paths/bodies for
  all four methods, the status filter, the `responses`/`vouchers` key fallback,
  and no-throw on 409/500.
- `test/features/account/screens/rewards_screen_test.dart` (2) — both sections
  render with a claimable coupon and a redeemable voucher; per-section empty
  states when the backend returns nothing.
- `test/core/services/challenges_service_test.dart` (+3) — `createSubmission`
  surfaces `grantedVouchers`, defaults it to `[]`, still throws the backend
  message on failure.
- `test/features/challenges/widgets/granted_vouchers_sheet_test.dart` (4) — name/
  code/Redeem render, header pluralises, no Redeem without a `redeemUrl`, Done
  dismisses.
- `flutter analyze` clean for all changed files. Full `test/core/services` and
  `test/features/account` suites pass except the pre-existing
  `archived_videos_screen_test.dart` timer failure (fails on a clean tree too).
