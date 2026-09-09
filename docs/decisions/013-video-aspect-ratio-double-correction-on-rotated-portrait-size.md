# 013 — `correctedVideoAspectRatio` must not invert an already-portrait `size`

Status: Accepted

## Problem

A creator's challenge **reference video**, recorded in-app, played back
**squeezed into a short, wide, letterboxed strip** on the challenge detail
screen (`ChallengeDetail` fullscreen player) — the person upright but the
frame stretched horizontally and crushed vertically. The exact same
processed video played back **correctly as portrait** in the web admin
panel.

This is the same *symptom family* as ADR 002 (sideways/squeezed recordings)
but a different root cause: ADR 002 fixed the native **capture** pipeline;
this is a **client-side aspect-ratio math bug** that survives a perfectly
recorded file.

## Investigation

Added a temporary `[REFVIDEO]` diagnostic in `challenge_detail.dart`
`_buildController` / `_initAndPlayVideo` logging `size`, raw `aspectRatio`,
`rotationCorrection`, and the computed `correctedVideoAspectRatio`. On a real
Android device, opening the reference video produced:

```
[REFVIDEO] url=https://womaty-dev-raw-clips.s3…/raw-videos/challenge/2026/09/07/…7fefeff5-….mp4
source=file  size=480x640  rawAspect=0.750  rotationCorrection=270  correctedAspect=1.333
```

What this establishes:

- **It's the raw `.mp4`, from the on-disk cache** (`source=file`,
  `raw-videos/challenge/…`) — not the MediaConvert HLS output. So this is
  not an HLS-encode problem, and the app and the admin panel are playing the
  *same* file. (`Challenge.videoUrl` served the presigned raw URL because
  this clip's processing hadn't finished.)
- **`video_player` reported `size: 480x640`** — already the rotated,
  portrait display dimensions, `rawAspect` 0.75 (correct) — **plus**
  `rotationCorrection: 270`.
- `correctedVideoAspectRatio` inverted on the 90/270 flag:
  `1 / 0.75 = 1.333`. That landscape ratio sized `ChallengeDetail`'s
  fullscreen `AspectRatio` box (`challenge_detail.dart`), and the portrait
  `VideoPlayer` was stretched to fill it → the squeezed strip.

The helper's assumption — *"`VideoPlayerValue.aspectRatio` does not swap
width/height when `rotationCorrection` is 90/270, so always invert"* — is
only true when `size` is the **pre-rotation** buffer. Here `size` is
**already rotated**, so inverting **double-counts** the rotation. This is
precisely the *"the reverse, double-correcting an already portrait-shaped
`size`"* failure mode that `portraitPreviewAspectRatio`'s own doc comment
already warned about — and `brand_preview_screen` / `preview_screen` /
`VideoPlayerWidget` (own-submission mode) already use
`portraitPreviewAspectRatio` for exactly this reason, which is why the
creator's *local* post-recording preview looked fine while `ChallengeDetail`
(which uses `correctedVideoAspectRatio`) did not.

The web admin panel's browser `<video>` element reads the container rotation
matrix and renders 480×640 portrait directly — no second correction — hence
"correct in admin, wrong in app".

## Options considered

1. **Point `ChallengeDetail` / the reels player at `portraitPreviewAspectRatio`.**
   Rejected: that helper *forces* `min/max` (always ≤ 1, i.e. portrait), and
   a challenge reference video can legitimately be landscape (screen
   recording, an imported clip). It's only safe for this app's own
   portrait-locked camera output.
2. **Fix `correctedVideoAspectRatio` to only invert a landscape-shaped
   `size`.** When `size` is already portrait (`raw < 1`) and a 90/270 flag
   is present, the display orientation is portrait and `raw` already gives
   it; only when `size` is still landscape (`raw > 1`) does the flag mean
   "the real display is the inverse". One line, provably correct for both
   observed cases, and keeps the ADR-002-era landscape-buffer case working.

## Decision

Option 2. `core/utils/video_aspect_ratio.dart`:

```dart
final rotated = value.rotationCorrection == 90 || value.rotationCorrection == 270;
return (rotated && raw > 1) ? 1 / raw : raw;
```

Plus a `size.width/height <= 0` guard returning the raw `aspectRatio` (no
divide-by-zero before the first frame).

## Consequences

- Fixes the squeezed reference video on `ChallengeDetail` and every other
  surface using `correctedVideoAspectRatio` (reels feed,
  `creator_entries_screen`, `VideoPlayerWidget` non-own-submission mode).
- The ADR-002 case it was originally written for — `size` reported as the
  pre-rotation landscape buffer (e.g. 1920×1080) with a 90/270 flag — is
  unchanged: `raw > 1`, still inverted.
- Residual assumption: a 90/270 flag on an already-portrait `size` is taken
  to mean "display portrait". A pathological file (portrait-shaped `size`
  that genuinely needs a quarter-turn to *landscape*) would still be sized
  portrait. No such file has been seen; `portraitPreviewAspectRatio` makes
  the same bet for the capture path.
- Does not touch `portraitPreviewAspectRatio` — its `rotationCorrection: 0`
  + landscape-buffer case is still un-catchable by any `size`-shape
  heuristic, so own-recorded previews keep force-portrait sizing.

## Verification

`test/core/utils/video_aspect_ratio_test.dart` — new case: `size 480x640`,
`rotationCorrection 270` ⇒ `correctedVideoAspectRatio` returns `0.75`
(portrait), not `1.333`. Reverting the fix to `rotated ? 1/raw : raw` fails
that case (confirmed: `+5 -1`) while the three pre-existing rotation tests
still pass. Plus a `Size.zero` guard case.

Manual: the `[REFVIDEO]` diagnostic (since removed) confirmed the input
values above on-device; with the fix, `correctedAspect` for that clip is
`0.750`.
