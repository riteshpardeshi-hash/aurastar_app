import 'package:video_player/video_player.dart';

/// The aspect ratio to size a video's layout box (e.g. an `AspectRatio`
/// wrapper) at, accounting for `rotationCorrection`.
///
/// `VideoPlayerValue.aspectRatio` is just `size.width / size.height`.
/// `VideoPlayer` rotates its platform view with a `RotatedBox` when
/// `rotationCorrection` is 90 or 270, so a box sized off the raw ratio can
/// end up shaped for the wrong (pre- vs post-rotation) orientation and
/// squeeze the content into a letterboxed strip.
///
/// The catch: whether `size` is the pre-rotation buffer or the already-
/// rotated display size depends on the platform decoder and the source
/// file. Two real cases seen in this app:
///  - `size` is the *pre-rotation* landscape buffer (e.g. 1920x1080) with a
///    90/270 flag — the displayed video is portrait, so the ratio must be
///    inverted.
///  - `size` is *already* the rotated portrait dimensions (e.g. 480x640,
///    CameraX-recorded challenge reference clips) *and still* carries a
///    90/270 flag — inverting again double-counts the rotation and produces
///    a landscape box for a portrait clip (the "squeezed reference video"
///    bug; see ADR 013).
///
/// So only invert when `size` is still landscape-shaped (`raw > 1`); when it
/// is already portrait, trust it as the display ratio. A 90/270 flag on an
/// already-portrait `size` reliably means "display portrait", which `raw`
/// already gives.
double correctedVideoAspectRatio(VideoPlayerValue value) {
  final w = value.size.width;
  final h = value.size.height;
  if (w <= 0 || h <= 0) return value.aspectRatio;
  final raw = w / h;
  final rotated =
      value.rotationCorrection == 90 || value.rotationCorrection == 270;
  return (rotated && raw > 1) ? 1 / raw : raw;
}

/// The aspect ratio for a video that was just recorded by this app's own
/// camera screens (`CameraScreen`/`BrandCameraScreen`), which always
/// `lockCaptureOrientation(DeviceOrientation.portraitUp)` before recording.
///
/// [correctedVideoAspectRatio] infers from `size` and `rotationCorrection`
/// whether `size` is the pre- or post-rotation shape, but that metadata has
/// been observed to be unreliable for locally-recorded files on Android —
/// most notably `rotationCorrection: 0` reported alongside a `size` that is
/// still the landscape, pre-rotation sensor buffer, which no `size`-shape
/// heuristic can catch. That sizes the box as landscape and squeezes the
/// actually-portrait content into a short, wide, letterboxed strip. Since
/// capture is always portrait-locked here, sidestep the metadata entirely
/// and just force the box to be taller than it is wide.
double portraitPreviewAspectRatio(VideoPlayerValue value) {
  final w = value.size.width;
  final h = value.size.height;
  if (w <= 0 || h <= 0) return 9 / 16;
  return (w < h ? w : h) / (w < h ? h : w);
}
