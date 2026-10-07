# 030 — AI Ads UI wired to the backend's campaign model (not a per-brand mock)

Status: Accepted

## Problem

The `ai-ads` branch shipped a creator UI for AI-generated brand ads
(brand profile → prompt → text-to-video or images-first → auto score) backed by
an in-memory mock `AiAdsService` (`AiVideoJob`, `fetchCredits(brandId)`, fixed
`costs`). The real backend feature (backend ADRs 111–115) is shaped
differently, so the mock could not simply be pointed at an API:

- Work happens inside a **campaign** the creator has joined (with the brand's
  approval and acceptance of the ownership terms), not "for a brand".
- Credits are the **brand's**, allocated per creator per campaign — not a
  global creator wallet.
- Prices are not constants: every AI action is **quoted** by the backend from
  an admin-tunable rate card, and the creator must see that exact price first.
- Scoring is an explicit, **paid** step with its own quote, run as a
  background job — not an automatic side effect of finishing a video.
- The creator explicitly **submits a final ad**; the brand picks winners and
  grants rewards.

## Investigation

Contract read from the backend routes (`src/routes/creator.routes.js`) and
`docs/api/openapi.yaml` ("Creator - AI Ad Campaigns"); response shapes from
the services (`paginatedResponse` → `responses`, evaluations/rewards as plain
arrays). Error semantics: 402 = credits don't cover it (nothing charged);
409 "The price changed — this now costs N credits" = the server refused to
charge more than `expectedCredits`. The existing `ApiClient` verbs return only
the decoded body, so the status code needed for those two branches was lost.

## Options considered

1. **Keep the mock's screen flow and translate behind the service** (pick the
   brand's only campaign implicitly, auto-run scoring). Hides real states
   (invite pending, out of credits, price change) and charges for scoring
   without the creator seeing the price — rejected.
2. **Rebuild the screens around the backend's states**, keeping the mock's
   visual language and its entry point on the brand profile — chosen.

## Decision

- `ApiClient.send()` returns `ApiResponse(statusCode, body)`, with the same
  401 refresh-and-retry as the other verbs and a readable failure for a
  non-JSON body. `AiAdsService` maps 402 → `OutOfAiCreditsException`,
  409 "price changed" → `AiPriceChangedException`, everything else →
  `AiAdsException` (message is user-presentable).
- Every paid button shows its live quote (`"Generate video · 25 credits"`);
  the tap *is* the confirmation and sends that price as `expectedCredits`.
  A price change re-quotes; out of credits offers "Ask for more" (credit
  request to the brand). Credits reserved for one evaluation are shown and
  explained.
- Screens: `AiCampaignsScreen` (optionally one brand's) → `AiCampaignScreen`
  (brief, assets, join/invite with the terms dialog) → `CreateAiVideosScreen`
  (scripts: AI / refine / own text / free edit; method, length, quality) →
  `AiVideoDetailScreen` (keyframe pick → video, progress + cancel, evaluation
  + score card, submit final, edit/extend/new-audio) and `MyAiVideosScreen`,
  `AiRewardsScreen`.
- The brand-profile button is shown to `role == 'creator'` only, because the
  routes are `requireRole("creator")` — a player would only reach a 403.

## Consequences

- The client holds no pricing logic; rate-card changes need no app release.
- Long-running work (videos, evaluations) is polled every 5 s while a screen
  is open; there is no push-to-refresh yet — the backend's notifications
  (AI_AD_*) arrive through the normal notification list.
- There is no global "AI ads" tab: creators reach campaigns from a brand's
  page (and from invite notifications). A dedicated entry point is a product
  call for later.

## Verification

- `test/core/services/ai_ads_service_test.dart` — paths, bodies
  (`expectedCredits`, `acceptTerms`), parsing, 402/409 mapping.
- `test/core/services/api_client_send_test.dart` — status codes, refresh retry,
  non-JSON body.
- `test/features/ai_ads/*_screen_test.dart` — join/terms, quoted buttons,
  disabled-when-unaffordable, price change, out of credits, keyframes → video,
  cancel, polling, evaluation + score card, retry after failure, submit final,
  extend, my-videos list, rewards.
- `test/features/explore/screens/brand_profile_ai_campaigns_button_test.dart`
  — creator-only entry point.
