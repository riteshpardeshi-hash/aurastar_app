# AI Ads (creator side)

Brands fund AI ad campaigns; creators join one and make an ad with AI tools
using the brand's credits. The backend owns everything (campaigns, pricing,
the credit ledger, generation, scoring) — backend ADRs 111–115 and
`docs/features/ai-ad-campaigns.md` there. Why the client looks the way it does:
[ADR 030](../decisions/030-ai-ads-ui-wired-to-backend-campaigns.md).

## Where it lives

| Piece | File |
| --- | --- |
| API client + models | `lib/core/services/ai_ads_service.dart` |
| Status-preserving request | `ApiClient.send` → `ApiResponse` (`lib/core/services/api_client.dart`) |
| Campaign list (all / one brand) | `lib/features/ai_ads/screens/ai_campaigns_screen.dart` |
| Campaign: brief, assets, join | `ai_campaign_screen.dart`, `ai_brand_assets_row.dart` |
| Workspace: scripts → create | `create_ai_videos_screen.dart` |
| One image set / video | `ai_video_detail_screen.dart` |
| My images + videos | `my_ai_videos_screen.dart` |
| Rewards | `ai_rewards_screen.dart` |
| Shared bits | `widgets/ai_ui.dart`, `ai_dialogs.dart` (terms, credit request, edit script), `ai_job_status_badge.dart`, `ai_video_player.dart` |

Entry point: the **AI Ad Campaigns** button on a brand's profile, shown only to
users whose profile `role` is `creator`.

## Flow

1. **Join** — open campaigns: *Ask to join*; invite-only: *Accept invite*.
   Both show the ownership-terms dialog first and send `acceptTerms: true`.
   A request waits for the brand's approval (`REQUESTED` → `ACTIVE`).
2. **Script** — *Write with AI* (paid), *Refine with AI* (paid), *Use my text*
   (free) or *Edit* an existing version (free; creates a new version).
3. **Create** — *Text to video* (length + quality) or *Images first* (4
   keyframes → pick → video). Videos run in the background; the detail screen
   polls every 5 s and offers *Cancel (refunded)*.
4. **Judge** — *Get AI score* (paid, background job). The score card shows the
   0–100 score, per-criterion scores, missing mandatory brand assets, forbidden
   claims / safety issues (these cap the score), timed feedback and
   suggestions. A failed evaluation is refunded and can be retried.
5. **Iterate** — *Edit*, *Make it longer* (+4/5/8/10 s) or *New audio* on any
   finished video (paid, quoted).
6. **Submit** — *Submit as my final ad* (free, changeable until the deadline).
   The brand picks winners; rewards show under *My rewards*, where the creator
   confirms *I got it*.

## Money rules the client must keep

- **Never show a price the server didn't quote.** Every paid button label is
  the latest `POST …/workspace/quote` (or `…/evaluate/quote`) result, and the
  button is disabled until it arrives or when `canAfford` is false.
- **Send the price the creator saw** as `expectedCredits`. The server refuses
  to charge more (409 "The price changed…") — re-quote and let them tap again.
- **402** means nothing ran and nothing was charged — offer *Ask for more*
  (credit request; the brand reviews all the creator's activity first).
- Some credits are **kept back for one evaluation** (`reservedForEvaluation`)
  so a creator can always get their ad judged; the workspace says so.
