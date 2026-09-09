# Backend bug: `GET /profile/videos` keeps returning soft-deleted videos

**Reported:** 2026-08-27 (recurrence of a 2026-08-05 issue)
**Severity:** Medium — deleted videos never leave the user's "My Videos" grid
**Affected endpoint:** `GET /api/v1/profile/videos`
**Related:** `DELETE /api/v1/videos/{id}`

## Symptom (client-visible)

Delete a video from "My Videos" → it stays in the grid (thumbnail goes
black, since the media URL is now dead). Pull-to-refresh doesn't remove it.
Tapping Delete on it again returns **"Video not found."** (`404`) — proving
it *is* gone server-side, the list endpoint just keeps listing it.

## Expected

`DELETE /videos/{id}` is documented as a soft delete. The API's own
soft-delete convention (openapi.yaml, on another resource: *"Stamps
`deletedAt` — the entry stops appearing in list/detail responses but is not
physically removed."*) is the right behavior here too: a soft-deleted video
should not appear in `GET /profile/videos`.

## History

- **2026-08-05:** same symptom. Worked around client-side by filtering out
  list items whose top-level `status` was `"inactive"` (the marker the
  backend set on delete at that time).
- **2026-08-27:** symptom returned. A still-listed deleted video no longer
  carries that marker (or carries a different one) — the `status: "inactive"`
  filter no longer catches it.

## Client status

Worked around again on `prototype`, this time marker-independently:
`VideosService` now records deleted ids for the session and filters them out
of both "My Videos" grids (`my_account_screen.dart`, `all_videos_screen.dart`)
regardless of what the list endpoint returns; a `404` on delete is treated as
an already-satisfied delete instead of surfacing "Video not found." to the
user. `VideosService.isDeletedVideo` also checks `status in {inactive,
deleted}`, `isDeleted == true`, and a non-null `deletedAt` as a best-effort
server-side signal.

This is a workaround. The real fix is for `GET /profile/videos` (and
`GET /videos/{id}`) to exclude soft-deleted videos at the source — then the
client can drop the id-tracking entirely.

## To reproduce

1. As a user with ≥1 uploaded/scored video, `DELETE /videos/{id}` → `200`.
2. `GET /profile/videos` → the deleted video is still in `responses`.
3. `DELETE /videos/{id}` again → `404 {"message":"Video not found."}`.
