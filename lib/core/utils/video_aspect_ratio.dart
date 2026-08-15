import 'package:video_player/video_player.dart';

/// The aspect ratio to size a video's layout box (e.g. an `AspectRatio`
/// wrapper) at, accounting for `rotationCorrection`.
///
/// `VideoPlayerValue.aspectRatio` is just `size.width / size.height` — it
/// does not swap width/height when `rotationCorrection` is 90 or 270.
/// `VideoPlayer` itself rotates its platform view with a `RotatedBox` in
/// that case, but the box the caller sizes around it is not rotated, so
/// using the raw aspect ratio there sizes it for the *pre-rotation* shape
/// (e.g. landscape) while the content rendered inside is actually the
/// swapped, *post-rotation* shape (e.g. portrait) — the mismatch is what
/// makes a genuinely-portrait video appear squeezed/sideways on screen even
/// though the platform view correctly rotated the pixels.
double correctedVideoAspectRatio(VideoPlayerValue value) {
  final raw = value.aspectRatio;
  return (value.rotationCorrection == 90 || value.rotationCorrection == 270)
      ? 1 / raw
      : raw;
}
