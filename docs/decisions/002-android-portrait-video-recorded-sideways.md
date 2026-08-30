# 002 — Upgrade `camera` to the CameraX Android backend to fix sideways recordings

Status: Accepted

## Problem

Videos recorded on Android through `CameraScreen`/`BrandCameraScreen` were
playing back rotated 90° — a portrait selfie recording ended up as a sideways
landscape clip. This reproduced on a fresh recording, on Android, before any
upload or backend processing: `PreviewScreen`'s local playback (right after
tapping stop, before Submit) already showed the content sideways.

Both camera screens already call
`CameraController.lockCaptureOrientation(DeviceOrientation.portraitUp)` (a
prior fix, see the comment at `camera_screen.dart` `_initCamera`), which
rules out "the device physically rotated mid-recording" as the cause — this
is a different bug.

## Investigation

- Confirmed the live `CameraPreview` widget renders the user upright and
  correctly framed at the moment of recording (screenshot evidence) — so the
  live preview pipeline is fine.
- `PreviewScreen`'s local playback of the just-recorded file (same
  screenshot set, same take) already shows the content rotated 90°, before
  any network/backend involvement. Since `portraitPreviewAspectRatio`
  (`core/utils/video_aspect_ratio.dart`) already sidesteps trusting
  `video_player`'s `rotationCorrection` metadata for local files (that
  metadata was already known to be unreliable there — see that file's
  doc comment), and the content is still visibly sideways, the problem
  isn't a Flutter-side box-sizing issue — the **recorded file's pixel data
  itself** is landscape.
- Backend-supplied evidence (a `_ai_proxy.mp4` derivative + the backend
  team's own diagnostic log, `target=90° before=1280x720 after=1280x720`)
  confirms the same file physically decodes as 1280×720 landscape with an
  identity (no-op) rotation matrix — i.e. no rotation tag at all, not a
  wrong one. The backend's own orientation-correction step detects a 90°
  correction is needed but its rotate call is a no-op (dimensions unchanged
  before/after) — a separate, backend-side bug, flagged to that team, but
  not sufficient to explain the client-local preview already being sideways
  before the file ever reaches the backend.
- The app's `camera` plugin was pinned to `^0.10.5+9` (resolved
  `camera_android: 0.10.10+17`), Flutter's **legacy, pre-CameraX** Android
  camera implementation. This implementation is a well-documented source of
  device-specific "preview correct, recorded file wrong orientation" bugs
  (the sensor/`MediaRecorder` orientation hint pipeline, separate from the
  live `SurfaceTexture` preview transform) — exactly the split observed
  here. Google's own fix for this bug class was rewriting the Android
  backend on CameraX, shipped as the endorsed `camera_android_camerax`
  implementation starting `camera` 0.11.0 (current stable at the time of
  this fix: 0.12.0+2).

## Options considered

1. **Add a client-side rotation workaround** (e.g. force-rotate the
   recorded `XFile` before upload based on a heuristic). Rejected: doesn't
   address the root cause, adds a transcode step on-device (cost, battery,
   time-to-submit), and would need to special-case every device/orientation
   combination the legacy plugin gets wrong.
2. **Push the fix entirely to the backend** (make their rotate step
   actually apply). Necessary regardless (flagged separately), but
   insufficient alone — the file is already wrong before it leaves the
   device, so this only patches the symptom for the AI-scoring path, not
   for the app's own local preview or any other consumer of the raw file.
3. **Upgrade `camera` to the CameraX-backed implementation.** Fixes the
   problem at the layer it actually originates in (capture/recording), with
   no new client-side workaround code to maintain, and is the
   plugin-maintainer-endorsed fix for this exact bug class.

## Decision

Upgraded `camera: ^0.10.5+9` → `^0.12.0` (also bumped the dev-only
`camera_platform_interface` constraint to `^2.11.0` to match). `flutter pub
get` resolved to `camera_android_camerax` and dropped `camera_android`
entirely — no manifest or Gradle changes were needed (the project's
`minSdkVersion` already resolves to Flutter's default of 24, which satisfies
`camera` 0.12.0's SDK 24+ requirement).

No application code changes were required — `CameraController`,
`lockCaptureOrientation`, `ResolutionPreset`, and `CameraDescription` are
all part of `camera_platform_interface`, which the new Android
implementation still satisfies. `flutter analyze` found no new issues.

## Consequences

- Fixes the recording pipeline at the root; no client-side rotation
  workaround to maintain.
- Does **not** fix already-uploaded sideways submissions, and does not fix
  the separate, confirmed-independent backend bug in the `ai_proxy`
  generation step (see Verification) — that's been flagged to the backend
  team and needs their own fix for AI scoring and any playback path that
  serves a video processed through that same step.

## Consequences (real-device verification, 2026-08-24)

Built and installed a debug APK, recorded a fresh portrait clip on a real
Android device:

- `PreviewScreen`'s local playback (immediately after recording, before
  upload) is now **upright** — the client-side fix works. Confirmed by
  screenshot.
- The AI score result and the in-app "My Videos" detail screen for that
  same submission are **still sideways** after upload. The AI feedback
  itself even says "the sideways orientation of the camera severely
  impacts the presentation."
- Pulled the submission's `_ai_proxy.mp4` (the artifact the backend
  generates to feed Gemini scoring) both from a pre-fix submission
  (2026-08-21) and a fresh post-fix submission (2026-08-24) and inspected
  each with the same MP4-box parser used earlier in this investigation.
  **Both are byte-distinct files with the identical broken signature**:
  1280×720, identity (no-op) rotation matrix, zero rotation tag — same
  before and after the client fix.

  This rules out the client as the cause of the remaining symptom and
  narrows the backend bug further than the original `target=90°
  before=1280x720 after=1280x720` log suggested: rather than "detects the
  needed rotation but the rotate call is a no-op," the `ai_proxy`
  generation step appears to produce a **fixed 1280×720 landscape output
  regardless of the source video's actual orientation** — consistent with
  a transcode step that doesn't read/preserve source orientation at all
  (e.g. a hardcoded scale filter), not one that detects-then-fails-to-apply
  a correction.
- Not yet checked: the raw pre-processing upload (`stages.rawVideo.url` via
  `GET /dev/videos/{videoId}`, staging-only) — would confirm CameraX is
  writing correct orientation at the source, closing the loop entirely.
  Not blocking: the local `PreviewScreen` screenshot already demonstrates
  the client-recorded file is correct, since that screen plays the exact
  same on-device file the raw upload sends.

## Verification

- `flutter analyze`: clean (only pre-existing, unrelated lints).
- `flutter test`: full suite green except 2 pre-existing failures in
  `category_challenges_screen_test.dart` (starsCount/difficulty badge
  rendering — unrelated to camera/video, confirmed already present in the
  working tree before this change).
- `test/features/challenges/screens/camera_screen_test.dart` needed two
  updates to match `camera` 0.12.0's `CameraController.initialize()`, which
  now also subscribes to `CameraPlatform.onCameraError()`:
  - `_FakeCameraPlatform.onCameraError()` had no override, so the new
    `onCameraError(id).first` call inside `initialize()` threw
    `UnimplementedError`, which the app's own try/catch silently absorbed
    (`_cameraError = true`), leaving the screen stuck showing "Camera
    unavailable" in every test.
  - Once that was overridden, a second issue surfaced: returning
    `Stream.empty()` still failed the same `.first` call with `StateError:
    Bad state: No element`, because an already-closed empty stream never
    emits. Replaced it with a `StreamController.broadcast()` that's simply
    never closed, matching a real error stream that hasn't fired.
  - This is test-double maintenance to match the new platform-interface
    surface, not new production behavior — no assertions changed, and the
    existing "locks capture orientation to portrait" regression test still
    covers the original sideways-recording fix this ADR builds on.
- **Real-device verification (2026-08-24)**: confirmed — see "Consequences
  (real-device verification)" above. Local recording/preview is fixed;
  post-upload playback remains sideways, but is now conclusively isolated
  to the independent `ai_proxy` backend bug, not this client change.
