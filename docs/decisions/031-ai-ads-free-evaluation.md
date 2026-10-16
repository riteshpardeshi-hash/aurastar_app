# 031 — AI Ads: evaluation is free, no credits kept back

Status: Accepted (amends 030)

## Problem

ADR 030 shipped AI scoring as a paid, quoted action, with credits "kept back for getting your ad
judged" (`reservedForEvaluation`) shown in the workspace and on unaffordable buttons. The client
then decided (2026-10-07, backend ADR 116) that evaluation is **free** for creators — the
platform pays — capped at an admin-set number per creator per campaign, and that every paid
price is the AI provider's cost plus the platform's margin, synced automatically.

## Investigation

Backend ADR 116 changes the contract: `…/evaluate/quote` now returns `credits: 0, free: true,
freeEvaluations {limit, used, left}, canAfford, reason?`; `…/evaluate` takes no price; the
workspace drops `prices.reservedForEvaluation` and adds `freeEvaluations`. An exhausted limit or
an already-judged video is a 409 with a readable message.

## Options considered

1. **Keep showing "0 credits"** on the score button. Accurate but reads like a price, and hides
   the real limit — rejected.
2. **Show "Free · N left"** and the backend's `reason` when it can't run — chosen.

## Decision

- `AiFreeEvaluations` (workspace + evaluation quote), `AiQuote.free/reason/freeEvaluations`;
  `AiPrices.reservedForEvaluation` and `AiWorkspace.spendable` removed;
  `requestEvaluation(id, videoId)` sends no body.
- Detail screen: "Get AI score · Free · N left" / "Try again · Free · N left"; when it can't run,
  the backend's reason shows and the button is disabled.
- Workspace: "Getting your ad judged by AI is free — N of M left."; an unaffordable action says
  "This costs X credits and you have Y."

## Consequences

The app still never computes a price. An older backend without `freeEvaluations` reads as
limit 0 (the line is hidden).

## Verification

`test/features/ai_ads/ai_video_detail_screen_test.dart` (free label, no price sent, limit
reached → reason + disabled), `create_ai_videos_screen_test.dart` (free line, shortfall text),
`test/core/services/ai_ads_service_test.dart` (free quote parsing, no body, missing field).
