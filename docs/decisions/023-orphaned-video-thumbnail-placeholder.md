# 023 — Skip frame extraction for a backend-orphaned video

Status: Accepted

## Problem

A user reported one of their own videos in My Videos rendering as a blank
purple box with no thumbnail. `VideoThumbnailWidget` had a client-side
fallback for a missing `thumbnailUrl` — extract a frame from the raw
`videoUrl` — but for this video that fallback was silently failing after its
full 30s timeout, every time the widget mounted.

## Investigation

Traced the specific video via the backend's production database directly:
its `processingStatus` was `"pending"`, meaning the async S3 →
MediaConvert → Lambda 2 pipeline had never completed for it, and had been
stuck that way for weeks (not a "still processing" transient). Curling its
presigned raw `videoUrl` returned a plain `404` — the raw S3 object was
already gone, despite `processingStatus` never reaching `"completed"` (which
is the only condition under which the backend's own pipeline deletes the raw
copy — see `video.model.js`'s docstring in the backend repo). Something
outside the pipeline (most likely a raw-bucket lifecycle expiry rule)
removed it first.

Querying wider, 27 of 819 production videos were stuck the same way, across
every submission verdict — not specific to rejected/low-scoring submissions,
which is what the original report looked like on the surface.

This wasn't a client rendering bug — the widget's fallback behavior was
reasonable for its stated assumption ("thumbnailUrl is null because
processing hasn't finished yet, so try extracting from the still-fetchable
raw file"). The assumption just didn't hold for a video the backend's own
pipeline had permanently abandoned, and nothing in the API response said so.

## Options considered

1. **Client-side timeout tuning only** — shorten the 30s extraction timeout.
   Doesn't fix anything; still spends time discovering a URL that will
   never resolve, and a shorter timeout risks false negatives for a real
   slow connection on a video that would have succeeded.
2. **Client-side dead-URL pre-check (HEAD request) before extracting** —
   adds a network round-trip to every single thumbnail load, for a case
   that's supposed to be rare. Also racy: a HEAD succeeding doesn't
   guarantee the subsequent extraction will.
3. **Backend marks orphaned videos `processingStatus: "failed"` (paired
   backend fix, ADR 099 in the backend repo), client trusts that field** —
   chosen. The backend already has the authoritative view (it can see
   `processingError`, elapsed time since `createdAt`, and is the one place
   that can safely make the "give up" call once, rather than every client
   re-discovering it independently on every load).

## Decision

`VideoThumbnailWidget` gained an optional `processingStatus` parameter. When
it's `"failed"`, the widget skips the extraction fallback entirely and shows
a distinct "unavailable" placeholder (`Icons.videocam_off_rounded`) instead
of the generic loading-style gradient, so it's visually distinguishable from
"still loading" rather than looking like a stuck spinner. `thumbnailUrl`
still takes priority if somehow both are set. Wired through the two screens
that actually show the user's own submissions with this field available —
`AllVideosScreen` and `MyAccountScreen`'s "My Videos" grid and achievement
cards row, both fed from `GET /profile/videos`. Every other call site (feed,
challenge, creator-profile thumbnails) is left as `processingStatus: null`
(the default) — their thumbnails are near-always for videos processing
already completed by the time they're publicly visible, and their API
responses don't carry this field today.

## Consequences

- A genuinely orphaned video now shows a clear, fast, distinct "unavailable"
  state instead of a 30s hang ending in a blank box that looks identical to
  a video still loading.
- This depends on the backend's `video_processing_timeout` sweep (ADR 099,
  backend repo) actually running and flipping stuck videos to `"failed"` —
  without that, a permanently-stuck-at-`"pending"` video still falls through
  to the old extraction-timeout behavior. That's an accepted gap, not a new
  one: this fix narrows the affected window, it doesn't eliminate a case the
  backend hasn't classified yet.
- If a future screen wants this same protection, it needs to thread
  `processingStatus` from its own API response through to the widget the
  same way — it isn't automatic just by using `VideoThumbnailWidget`.

## Verification

`test/shared/widgets/video_thumbnail_widget_test.dart`'s new
`processingStatus:"failed"` group: confirms extraction is never attempted
for a failed video, confirms a non-empty `thumbnailUrl` still wins
defensively, and confirms a merely-`"pending"` video is unaffected (still
attempts extraction as before). `app_bottom_nav_test.dart` and
`main_shell_test.dart` re-run clean per this repo's standing nav-regression
rule.
