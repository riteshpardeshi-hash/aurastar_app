# Backend gap: `GET /creators/{id}/videos` returns an empty list

**Reported:** 2026-09-08
**Severity:** Medium — a creator's public profile shows no content in the video grid
**Affected endpoint:** `GET /api/v1/creators/{id}/videos`
**Related:** `GET /api/v1/profile/videos` (same class of gap — see
`docs/backend-issues/002` and the "My Videos Backend Gap" note), `Submission`
model, `POST /api/v1/challenges/{id}/submissions`

## Symptom (client-visible)

Open any creator's public profile (`CreatorProfileScreen`, reached from every
creator thumbnail / the Explore → Creators list). The lower half of the screen
shows an empty state — icon + "No videos yet" — for every creator, including
ones who have recorded and submitted challenge attempts.

`GET /creators/{id}/videos?page=1&limit=30` returns:

```json
{ "status": "success", "data": { "responses": [], "totalCount": 0, ... } }
```

## Expected

Per the OpenAPI spec the endpoint is *"Paginated list of videos submitted by a
creator"* — i.e. the creator's own challenge-attempt `Submission` records. A
creator with ≥1 scored/approved submission should get those rows back, the same
way `GET /challenges/{id}/submissions` returns per-challenge submissions.

## Root cause (suspected)

Same shape as `docs/backend-issues/002`: scored/approved submissions are not
linked into whatever collection/query backs the per-user video feeds.
`GET /profile/videos` has been observed returning `{"totalCount":0,
"responses":[]}` for an account with a genuinely scored submission
(repro submission `6a6ca44d7d9a251f5a7ab586`); `GET /creators/{id}/videos`
appears to share that broken linkage.

## Client status (worked around on `prototype`)

The creator profile no longer depends on this endpoint for its primary
content. As of this change it fetches the creator's **authored challenges**
via `GET /challenges?creatorId={id}&sourceType=Creator`
(`CreatorsService.fetchCreatorChallenges`) and renders those in the grid; the
"Challenges" stat is now that count (it was previously the length of this
always-empty video list, so every profile read "0 Challenges").

`GET /creators/{id}/videos` is still called and used as a *fallback* grid for
accounts that have authored no challenges, so once the backend links
submissions in, those profiles start showing attempt videos again with no
further client change.

## To reproduce

1. As a creator account with ≥1 approved challenge submission, call
   `GET /creators/{creatorId}/videos`.
2. Response is `data.responses: []` / `data.totalCount: 0`.
3. Cross-check `GET /profile/videos` for the same account — also empty despite
   the scored submission.
