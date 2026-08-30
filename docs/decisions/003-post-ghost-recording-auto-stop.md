# 003 — Auto-stop a challenge recording 10s after the ghost clip ends

Status: Accepted

## Problem

`CameraScreen` records a user's attempt at a challenge while playing the
challenge's reference clip as a muted "ghost" PiP overlay. Recording had no
upper bound — the user had to tap stop themselves. Nothing stopped a take
from running far longer than the reference it will be scored against, which
produces submissions that are mostly dead footage: the AI scoring pipeline
(and any human spot-checking it) then has to sit through a 90-second clip to
score a 12-second routine, and the trailing footage is pure noise against
the rubric.

We want: once the ghost clip has played through once, the take may run at
most 10 more seconds, then stops itself.

## Investigation

The ghost overlay is driven by a `VideoPlayerController` in `CameraScreen`.
Two facts shaped the approach:

- The ghost was created with `setLooping(true)` and only ever `play()`s from
  `_startRecording()` (right after `CameraController.startVideoRecording()`),
  seeking back to zero on stop / lifecycle resume. So "the ghost plays" and
  "we are recording" begin within the same async turn — a few ms apart.
- `video_player` 2.11.1 does expose `VideoPlayerValue.isCompleted`, so a
  playback-completion listener was a real option (see below).

The existing 1-second `Timer.periodic` in `_startRecording()` already tracks
`_elapsed` for the on-screen recording pill, so a wall-clock deadline needs
no new timer infrastructure.

## Options considered

1. **Playback-completion listener** — set `isLooping = false`, add a
   listener on the ghost controller, and when `value.isCompleted` flips,
   start a 10s `Timer` to `_stopRecording()`. Most accurate: the grace
   window is measured from the ghost's *actual* on-screen end, so it stays
   correct even if playback stalls buffering. Costs: a controller listener
   with its own teardown paths (stop, dispose, lifecycle-pause), and it's
   awkward to exercise in a widget test because the fake
   `VideoPlayerPlatform` never emits a `completed` event.

2. **Wall-clock deadline from the ghost's known length** — when recording
   starts with a ready ghost, read `_ghostCtrl.value.duration`, and in the
   existing per-second tick auto-stop once
   `_elapsed >= ceil(ghostLength) + 10`. The ghost is set
   `setLooping(false)` so it visibly freezes on its last frame as the
   "grace has started" cue. No new timer, no listener lifecycle, fully
   deterministic to test.

## Decision

Option 2. The requirement is a *maximum* ("at most 10 more seconds"), and a
wall-clock cap is exactly that. The ghost clip is almost always a locally
cached file by the time recording starts (`VideoCacheService.ensureCached`
in `_initGhost`, usually pre-warmed from `ChallengeDetail`), so playback
drift versus wall-clock is negligible in practice, and where it isn't, a
slightly shorter grace window is a benign failure for a guide overlay. The
simpler control flow — no listener, reusing the tick that's already there —
is worth more than the accuracy Option 1 buys back.

Mechanics: `_ghostLengthSec` is captured in `_startRecording()` only when a
ghost is actually playing this take (`null` otherwise → no auto-stop, manual
control as before). `_tickAutoStop()` runs each second: past the ghost's
length it populates `_graceRemaining` (shown as "Auto-stop in Ns" on the
recording pill); at zero it calls `_stopRecording()`, which is now
guarded with `if (!_recording) return;` against a manual tap racing the
auto-stop. The fields are cleared in `_stopRecording()` and the
lifecycle-pause handler alongside the other recording state.

## Consequences

- Recordings for challenges with a reference clip are now bounded at
  `ghostLength + 10s`; the user can still stop earlier.
- Challenges with no reference video (`referenceVideoUrl` empty) are
  unchanged — there is no clip to measure from, so recording stays fully
  manual. The brand challenge-creation camera has no ghost overlay and is
  unaffected.
- The ghost no longer loops during a take. If a future feature wants the
  reference to keep repeating for the full recording, that will need to be
  reconciled with the "ghost end" cue this relies on.
- Drift trade-off: if the ghost stalls on a slow network the grace window
  is effectively shorter than 10s of playback. Accepted as benign; revisit
  with Option 1 if it ever matters.

## Verification

Regression test in
`test/features/challenges/screens/camera_screen_test.dart`:

- *"recording auto-stops 10s after the ghost reference clip ends"* — fake
  ghost clip is 5s; asserts recording is still live at 14s elapsed with the
  "Auto-stop in" hint visible, and that `stopVideoRecording` fires once the
  15s mark is crossed. Fails against pre-fix code (recording never stops).
- *"recording never auto-stops when the challenge has no ghost reference"* —
  no `referenceVideoUrl`; pumps 40s and asserts no auto-stop and no hint.
