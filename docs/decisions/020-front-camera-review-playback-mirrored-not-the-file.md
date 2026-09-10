# 020 — Mirror the front-camera *review playback*, not the recording or the file

Status: Accepted

## Problem

A user records a selfie-facing challenge take on Android. The live camera
preview is mirrored (selfie-style, as every phone camera is). The review
screen (`PreviewScreen`, the "Looks good? / Submit for Aura Score" step)
then plays the saved file, which on Android is **un-mirrored** — a
horizontal flip of what they just framed. It reads as "the recording came
out mirrored / backwards." Same in the creator flow (`BrandCameraScreen` →
`BrandPreviewScreen`).

## Investigation

No flip is applied anywhere in our own code. The behaviour is the `camera`
plugin's platform default (`camera: ^0.12.0`):

- **Live preview** is mirrored for the front lens on **both** platforms
  (CameraX `PreviewView` / iOS `AVCaptureVideoPreviewLayer`).
- **Recorded file**: `camera_avfoundation` sets `connection.isVideoMirrored
  = true` for `.front` (`DefaultCamera.swift`), so **iOS records the front
  camera mirrored** — it matches its preview. `camera_android_camerax` does
  **not** mirror the recording, so **Android records un-mirrored**.

So the mismatch is Android-only: iOS users never saw it. Confirmed by the
reporter's two screenshots being exact horizontal flips of each other.

A first attempt un-mirrored the *live preview* to match the file. On device
that made framing feel backwards (raise right hand → moves left on screen)
and would have broken iOS (un-mirror its preview while its file stays
mirrored). Reverted.

## Options considered

1. **Un-mirror the live preview** — rejected above: breaks the natural
   selfie framing and breaks iOS.
2. **Mirror the Android recorded file** — via a `camera_android_camerax`
   fork setting `MIRROR_MODE_ON_FRONT_ONLY`, or an ffmpeg `hflip` pass after
   recording. Makes every surface consistent, but means owning a native
   plugin patch, or a large dependency + a re-encode per take.
3. **Mirror only the review playback.** Keep the live preview and the
   uploaded file exactly as they are; horizontally flip the `VideoPlayer`
   on `PreviewScreen` / `BrandPreviewScreen` for front-camera takes on
   Android, so the review matches what the user saw while recording.

## Decision

Option 3 — the requested behaviour: "it should look proper while recording
as before; in the preview it should not flip."

- `CameraScreen` captures the lens direction when recording **stops**
  (`_lastRecordingWasFront`) — the user can flip the camera afterward, so
  reading the controller at preview time would be wrong — and passes
  `mirrored: Platform.isAndroid && _lastRecordingWasFront` to `PreviewScreen`.
- `PreviewScreen` / `BrandPreviewScreen` gained a `mirrored` flag (default
  `false`); when set, the player is wrapped in `Transform.scale(scaleX: -1)`.
  `BrandCameraScreen` feeds it the same way.
- `UploadQueueService` persists the flag so a failed-upload retried from the
  dashboard banner re-opens `PreviewScreen` with the same orientation.
- Gallery-picked videos and every other caller default to `false`.

`Platform.isAndroid` guard: iOS already records the front camera mirrored,
so its review already matches — flipping there would re-introduce the bug.

## Consequences

- Recording feels the same as before (mirrored selfie preview); the review
  screen now matches it on Android.
- The **uploaded file is unchanged** — un-mirrored on Android. In the
  community feed, reels, and to the AI scorer, an Android user's video still
  appears as other people's cameras see them (text readable). This matches
  the common convention (Instagram/Snap show your posted video un-mirrored)
  and keeps the AI comparing like-for-like against reference clips recorded
  the same way. If product later wants the *posted* video mirrored too, that
  is option 2 and a bigger change.
- The flag rides on the local navigation/queue only. It is derived fresh
  each recording from the lens + platform, not stored on the submission, so
  there is nothing to migrate.
- iOS is deliberately untouched.

## Verification

Manual: record a front-camera take on Android → the review screen is
oriented the same as the recording preview (raised hand on the same side);
switch to the back camera → review is not flipped; on iOS both stay
correct. `flutter analyze` clean; existing `preview_screen` /
`upload_queue` suites green with the added optional flag.
