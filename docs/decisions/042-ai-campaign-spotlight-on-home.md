# 042 — AI ad campaigns at the top of a creator's home

Status: Accepted

## Problem

Creators had no way to find AI ad campaigns from the home screen: the campaign list was only
reachable from a brand's profile. The client approved a design (option A, "campaign
spotlight", 23 Nov 2026) where open campaigns are the first thing a creator sees, with the
brand, a cover, time left, seats, the prize and a one-tap next step. Invite-only campaigns
must never appear.

## Investigation

`GET /creator/ai-campaigns` (backend `discoverCampaigns`) already returns exactly the
campaigns a creator may join — LIVE, OPEN, before the deadline — plus the ones they're in,
and hides blocked brands. It lacked the brand, a picture and a prize; backend ADR 141 adds
`brand`, `coverImage`, `prize`, `format`, `creatorCap` and `liveAt`. The endpoint is
creator-only (`requireRole("creator")`), so players and brands can't use it.

## Options considered

1. **A new home section below Featured** — keeps Featured on top, but the approved design puts
   campaigns first.
2. **Replace Featured for creators, fall back to it when there are no campaigns** — matches the
   design and never leaves the top of the home empty.

## Decision

Option 2. `AiCampaignSpotlight` (features/ai_ads/widgets) loads the list once per home load
(keyed on the dashboard's refresh tick, so pull-to-refresh reloads it) and is shown only when
the user's role is `creator`; with no campaigns, or on an error, it renders the usual Featured
carousel. Order: campaigns the creator is in first (their next step: Create video / Pending /
See invite), then open ones by deadline; full campaigns they aren't in are left out. Join
opens the existing campaign screen and application form (terms, links, demo video — backend
ADR 131), not a new flow. "See all" opens the campaign list, now with cover cards and Ending
soon / New / Highest prize / Joined filters. The prize follows the coupons switch (backend
ADR 119) like every other reward in the app.

## Consequences

- While coupons are off (as in production on 23 Nov 2026), cards show no prize.
- Brands without a product or reference image get a plain gradient card.
- Players and brands keep today's home.
