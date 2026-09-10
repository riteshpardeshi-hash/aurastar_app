# 020 — Un-mirror the front-camera preview instead of mirroring the file

Status: Accepted

## Problem

A user records a selfie-facing challenge take. The live camera preview shows
them as a mirror would (their right hand on the screen's right). The review
screen (`PreviewScreen`) then plays the saved file, which is the **true
optical** image — horizontally flipped from what they just framed. It reads
as "the recording came out mirrored." Same in the creator flow
(`BrandCameraScreen` → `BrandPreviewScreen`). Reported on Android; the same
default applies on iOS.

## Investigation

No flip is applied anywhere in our code — `camera_screen.dart` renders
`CameraPreview(_cam!)` raw inside a `FittedBox`, and `preview_screen.dart`
plays the file with a bare `VideoPlayer`. The mismatch is the platform
default of the `camera` plugin (`camera: ^0.12.0`,
`camera_android_camerax: 0.7.4+6`):

- **Front-camera preview is mirrored** — CameraX `PreviewView` and iOS's
  `AVCaptureVideoPreviewLayer` both mirror the front lens by default, the
  same as every stock camera app.
- **The recorded file is not mirrored** — `startVideoRecording()` writes the
  true sensor image. Confirmed by the user's two screenshots being exact
  horizontal flips of each other (AC unit and door swap sides).

The plugin exposes no `MirrorMode` / `isVideoMirrored` control for video
capture, so the recording side can't be changed without forking it.

Everything downstream of capture — `PreviewScreen`, the feed
(`VideoPlayerWidget`), the reels player, creator review, and the Gemini
scoring pipeline — consumes the un-mirrored file.

## Options considered

1. **Mirror the saved file** (ffmpeg `hflip` for front-lens takes). Correct
   on every surface with no per-screen logic. Cost: a heavy new dependency
   (`ffmpeg_kit_flutter`, native binary, LGPL build flavour), a few seconds
   of re-encode after every recording, and a generation of quality loss.
2. **Flip only in `PreviewScreen` / `BrandPreviewScreen`.** Cheap, but the
   feed and every other viewer still see the optical version, so "what I
   submitted" ≠ "what shows in the feed."
3. **Persist a `frontCamera` flag on the submission and flip in every
   player.** No re-encode, correct in-app. Cost: touches every video
   surface, needs a backend field, and forces a call on whether the scoring
   pipeline flips too (it matters for left/right-sensitive challenges).
4. **Un-mirror the live preview.** One `Transform.scale(scaleX: -1)` on the
   front-camera `CameraPreview`, so what the user frames is exactly what
   gets recorded and shown everywhere afterwards. Cost: the framing view no
   longer behaves like a mirror, which is unusual for a selfie camera and
   may itself feel "backwards" to some users.

## Decision

Option 4. `lib/core/utils/selfie_preview.dart` exposes
`unmirroredIfFront(controller, preview)`: for a `CameraLensDirection.front`
controller it wraps the preview in `Transform.scale(scaleX: -1)`; back and
external lenses are returned untouched. Applied in `CameraScreen._buildCamera`
and `BrandCameraScreen`'s preview `SizedBox`.

Chosen because it makes the preview agree with the file, the feed, other
viewers, and the scorer in one place, with no dependency, no re-encode, and
no backend change. The recording is already the "source of truth" every
other surface uses; this aligns the one surface that disagreed.

## Consequences

- What the user frames is what gets recorded and scored — no surprise flip
  on the review screen.
- The framing preview no longer mirrors like a bathroom mirror. Raising a
  hand moves the on-screen hand to the opposite side. This is the deliberate
  trade and may draw its own feedback; revisit if so.
- Assumes the standard platform behaviour (front preview mirrored, front
  file not). If an OEM device is found that records the front file already
  mirrored, its preview would then be wrong — handle that as a
  device-specific exception, not by reverting this.
- The ghost/reference PiP overlay is unaffected (it plays someone else's
  already-correct recording).

## Verification

`test/core/utils/selfie_preview_test.dart`: front controller → wrapped in a
`Transform` with `storage[0] == -1` (horizontal) and `storage[5] == 1` (no
vertical flip); back and external controllers → the preview widget returned
identical, no `Transform`. Device confirmation (preview now matches the
saved file for a front-camera take) still needs a manual pass on a phone.
`flutter analyze` clean.
