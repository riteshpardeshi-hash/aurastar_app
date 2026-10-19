# 039 — Creators build the scoring criteria on the create page

Status: Accepted

## Problem

Published creator challenges could not be played: every player got "Challenge not ready —
This challenge hasn't been set up for scoring yet". The draft form's "Scoring Criteria"
chips looked like scoring rules but were stored as display text only. The two create entry
points also differed: Creator Activity → "Create challenge" opened the old record flow,
My Challenges → "New Challenge" the draft page.

## Investigation

The backend scorer needs `Challenge.rubric` (weighted categories with score bands). The
creator draft flow never built one (backend ADR 137). On 2026-10-19 the shared database had
LIVE creator challenges with `rubric: null`, including one whose chips said "face should be
clear".

## Options considered

1. **Generate silently on the backend only** — fixes the bug, but the creator never sees or
   shapes how contestants are scored.
2. **Separate scoring screen after saving** — works, but splits one job across screens.
3. **Everything on the create page** — chosen.

## Decision

- The create/edit page (`CreatorChallengeDraftScreen`) plays the reference video and holds a
  `ScoringCriteriaPanel`: **Generate scoring criteria** (saves the draft first, then
  `POST /creator/challenges/:id/rubric/generate`), **Ask AI for changes** (regenerate with
  notes), **Edit** (names, descriptions, points, 6–8 categories), **Write my own**.
- The editor checks the backend's rules before saving: 6–8 categories of 5–30 points, the
  creator's categories add up to 85, so the criteria score out of exactly 100 (10 fixed +
  85 + 5 bonus, `CreatorRubric.validateEdits`). Older criteria that don't total 100 are
  flagged and can't be submitted.
- The bottom button is **Submit for Approval** (Resubmit after changes are requested); "Save
  as draft" finishes later. Without criteria, Submit offers "Generate & review" or "Let AI
  create them".
- Both entry points go through `openCreateChallenge`, so a creator always gets this page.
  Brand/admin accounts keep the record flow (the `/creator/*` endpoints accept the creator
  role only).
- Generate, submit, resubmit and publish use a 3-minute timeout: they can run an AI call.

## Consequences

The admin reviews the criteria with the rest of the challenge and approves it as one. The
standalone `CreatorChallengeScoringScreen` stays for viewing criteria from the status page.

## Verification

`test/features/creator/screens/creator_challenge_draft_screen_test.dart`,
`creator_challenge_scoring_screen_test.dart`, `test/features/creator/open_create_challenge_test.dart`,
`test/core/models/creator_rubric_test.dart`, `test/core/services/creator_challenges_rubric_test.dart`.
