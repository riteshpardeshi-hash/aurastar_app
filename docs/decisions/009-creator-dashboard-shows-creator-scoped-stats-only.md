# 009 — Creator dashboard shows creator-scoped stats only, not the account's player figures

Status: Accepted

## Problem

A user who became a creator saw their **player** history on the creator
dashboard (`CreatorDashboardScreen`): "Total Aura 51597" (the Aura they earned
submitting to challenges as a regular user), "Submissions 10" / "Approved 0" /
"Approval Rate 0%" (their player challenge attempts), a personal Level/tier
progress bar ("Level 516 · Rookie · Next: Rising"), and a "Recent Submissions"
list of those attempts. None of these are creator concepts — a creator's
dashboard should describe the challenges they *publish* and the engagement those
draw, not their personal play record.

## Investigation

"Creating a creator account" is a misconception: `POST /creator/page` promotes
the caller's **existing** account to `role: creator` in place (per the backend
OpenAPI spec, `http://144.91.79.237:3786/docs/openapi.yaml` — "Creates an ACTIVE
creator page for the authenticated user and promotes their account role to
creator"). It is one `users` record. `auraPoints` is a single account-wide
balance (creator eligibility is even gated on `auraPoints >= 500`), and
`GET /profile` / `GET /profile/videos` keep returning that user's lifetime play
data regardless of role.

`CreatorDashboardScreen._load()` was calling `AuthApiService().getProfile()` and
`AuthApiService().fetchMyVideos()` and feeding them into `_buildAuraProgress`,
`_buildStats`, and `_buildRecentSubmissions`. Meanwhile the purpose-built
`GET /creator/dashboard/overview` already returns a `summary` object (reused from
`GET /creator/insights`) with `totalChallenges`, `liveChallenges`,
`totalParticipants`, `totalStars`, etc. — genuinely creator-scoped, and already
fetched by the screen for its `cards`/`pendingActions`.

## Options considered

1. **Delete the player sections, show nothing in their place** — removes the
   wrong data but leaves the screen sparse when the backend `cards` array is
   empty, and drops the "My Stats" heading entirely.
2. **Keep the sections but relabel** — doesn't help; the underlying numbers are
   still the player's, just with different captions.
3. **Replace "My Stats" with the overview `summary` totals, drop the Aura bar
   and Recent Submissions outright** — the stat grid stays, populated with
   Challenges / Live / Participants / Stars from an endpoint the screen already
   calls. `/profile` and `/profile/videos` are no longer hit by this screen.

## Decision

Option 3. `_buildStats()` now reads `overview['summary']`
(`totalChallenges`, `liveChallenges`, `totalParticipants`, `totalStars`).
`_buildAuraProgress`, `_buildRecentSubmissions`, `_buildSubmissionRow`,
`_timeAgo`, and `_normaliseVideo` are deleted, along with the `getProfile()` /
`fetchMyVideos()` calls and the `aura_tier` import. The personal Aura/level
belongs on My Account, which already shows it.

This sets the pattern: **creator surfaces present creator-scoped data even
though the promoted account still carries player-side figures.** The player
identity (Aura balance, level, submission history) lives on My Account; the
creator identity (challenges published, participants, stars) lives on the
creator dashboard.

## Consequences

- If `GET /creator/dashboard/overview` returns no `summary` (older backend, or
  an error), the four stat cards read `0` rather than showing stale player
  numbers — an honest empty state.
- The dashboard no longer makes two now-pointless requests per open.
- Not addressed: whether a creator should be able to *navigate* to their player
  profile from here. Out of scope; the bottom nav already exposes My Account.

## Verification

Regression test:
`test/features/creator/screens/creator_dashboard_screen_test.dart` — mocks
`GET /profile` with `auraPoints: 51597` / `level: 516` and `GET /profile/videos`
with 10 rows, and asserts none of those leak onto the screen while the
`/creator/dashboard/overview` summary totals (245 participants, 71 stars) do.
Fails against pre-fix `creator_dashboard_screen.dart` (`+0 -1`), passes after.
