# 033 — AI ad join requests are an application: pitch, links, demo video

Status: Accepted (2026-10-15) · Backend: ADR 131

## Problem

"Ask to join" on an AI ad campaign sent only `acceptTerms: true`. Brands had nothing to judge a
creator by, so they couldn't decide whom to accept.

## Investigation

The backend (ADR 131) now accepts `links` (instagram, youtube, x, facebook, linkedin, website —
URLs or @handles), an optional `demoVideoKey` from a presigned upload, and a pitch of up to 1,000
characters, and returns `suggestedLinks` on the campaign to prefill the form.

## Options considered

1. Keep the terms dialog, then open a second sheet for the application — two modals in a row
   for one action.
2. **One application sheet with the terms as a checkbox** — chosen.
3. Edit links on the creator profile screen and reuse them silently — the brand would see stale
   links and the creator couldn't tailor the pitch per campaign.

## Decision

- `showJoinRequestSheet` (`lib/features/ai_ads/widgets/ai_join_request_sheet.dart`) replaces the
  terms dialog for "Ask to join": pitch (1,000 chars), six link fields prefilled from
  `suggestedLinks`, an optional demo video (gallery, ≤ 90 s, ≤ 100 MB checked before upload) and
  the ownership-terms checkbox. At least one link and the checkbox are required before sending.
- The video goes presign → PUT (`ApiClient.uploadToS3`, with progress) → `demoVideoKey`.
- Accepting an invite still uses the terms dialog — invited creators were already chosen by the
  brand.
- The picker is injectable (`pickVideo`) so tests don't need the platform channel.

## Consequences

- Brands get a real application to review (backend ADR 131 / admin creator-profile modal).
- The form is longer; links are prefilled so repeat applications are quick.
- A failed upload keeps the form open with the error; nothing is sent until the video is in S3.
