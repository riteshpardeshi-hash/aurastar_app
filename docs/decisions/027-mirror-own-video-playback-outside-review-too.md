# 027 — Extend the front-camera mirror flag past the review screen to every own-video playback surface

Status: Accepted (amends 026)

## Problem

ADR 026 fixed the review screen (`PreviewScreen`/`BrandPreviewScreen`) right
after recording, but a user reported the same-looking bug one screen later:
a front-camera take recorded on Android looks correct while recording and
in that review step, but appears mirrored when watched back under
Profile → My Videos (both the account-screen preview grid and the full
`AllVideosScreen` grid, and the video detail screen opened from either).

## Investigation

Confirmed this is the exact tradeoff ADR 026 already named in its
Consequences section: the uploaded file is deliberately left un-mirrored
(true orientation) so the feed, reels, and the AI scorer see it as other
cameras would. Every playback surface *other than* the review screen plays
that same true file, un-flipped — including the user's own My Videos.

The `mirrored` flag ADR 026 introduced is derived fresh each recording
(lens + platform) and only rides on `PreviewScreen`'s local
navigation/`UploadQueueService` — nothing persists it anywhere the
`/profile/videos` response could later echo back, so My Videos has no way
to know a given video needs the same flip.

## Options considered

1. **Backend field** — send a `mirrored` bool at submission creation, have
   the backend store and return it on `/profile/videos`. Correct across
   devices/reinstalls, but requires coordinating a schema change with the
   separate backend team (see CLAUDE.md — ground backend behaviour in the
   OpenAPI spec, don't guess) and is out of scope for a client-only fix.
2. **Actually mirror the uploaded file** (ADR 026's rejected Option 2) —
   makes every surface consistent by construction, but reverses the reason
   026 kept the file true: the feed/reels would show a front-camera
   Android user's video flipped to everyone else (unreadable text/logos),
   and the AI scorer would compare a flipped clip against reference videos
   recorded the normal way. Bigger, riskier change for a cosmetic own-view
   issue.
3. **Local flag, keyed by video id.** `PreviewScreen` already knows
   `mirrored` and the video's id (`videoId`, claimed at presign time — the
   same id `/profile/videos` returns). Record it locally, in the same
   `VideosService` that already tracks locally-deleted video ids
   (`isDeletedVideo`) for an analogous backend gap, and have every
   own-video screen consult it.

## Decision

Option 3. `VideosService` gained `markMirrored(videoId)` /
`isMirroredVideo(video)`, persisted to `SharedPreferences` the same way
`_locallyDeleted` is (merge-on-write, capped, restored via `hydrate()`).

- `PreviewScreen._doUpload` calls `markMirrored(videoId)` right after a
  mirrored upload succeeds (`UploadQueueService.clear()` — i.e. once, not
  on every retry).
- `VideoThumbnailWidget` and `VideoPlayerWidget` gained a `mirrored` flag
  (default `false`) that wraps the rendered frame/player in
  `Transform.scale(scaleX: -1)`, same mechanism as `PreviewScreen`.
- `AllVideosScreen`, `MyAccountScreen`'s My Videos section, and
  `UserVideoDetailScreen` all thread `VideosService.isMirroredVideo(...)`
  through to those widgets.

## Consequences

- Same-device only: a reinstall or a second device has no record of which
  videos were mirrored, and those clips will show their true orientation
  again there. Acceptable for a cosmetic own-view detail, same tradeoff
  already accepted for the deleted-video-id tracking this reuses the
  pattern from.
- The feed, reels, and AI scorer are untouched — they never call
  `isMirroredVideo`, so other viewers keep seeing the true, readable
  orientation `026` was written to preserve.
- If the backend later adds a `mirrored`/`orientation` field (Option 1),
  this whole local-tracking block becomes dead code to delete, same as
  `VideosService`'s other backend-gap workarounds are flagged for removal.

## Verification

`test/core/services/videos_service_test.dart` — new `mirrored front-camera
Android uploads (ADR 026)` group: marking sets the flag, an unmarked video
stays unflagged, an empty id is a no-op, and the flag survives a simulated
relaunch (`hydrate()`) including when marked before any grid ran hydrate
first — same relaunch/ordering coverage as the existing deleted-id tests
this mirrors. `flutter analyze` clean on all seven changed files;
`preview_screen_test.dart` and `upload_queue_service_test.dart` still green.
