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

/// The aspect ratio for a video that was just recorded by this app's own
/// camera screens (`CameraScreen`/`BrandCameraScreen`), which always
/// `lockCaptureOrientation(DeviceOrientation.portraitUp)` before recording.
///
/// [correctedVideoAspectRatio] trusts `rotationCorrection` to know whether
/// `size` is pre- or post-rotation, but that metadata has been observed to
/// be unreliable specifically for locally-recorded files on Android (e.g.
/// reporting `rotationCorrection: 0` while `size` is still the landscape,
/// pre-rotation sensor buffer — or the reverse, double-correcting an already
/// portrait-shaped `size`) — either way, `correctedVideoAspectRatio` ends up
/// sizing the box as landscape, squeezing the actually-portrait content into
/// a short, wide, heavily-letterboxed strip. Since capture is always
/// portrait-locked here, sidestep the unreliable metadata entirely and just
/// force the box to be taller than it is wide.
double portraitPreviewAspectRatio(VideoPlayerValue value) {
  final w = value.size.width;
  final h = value.size.height;
  if (w <= 0 || h <= 0) return 9 / 16;
  return (w < h ? w : h) / (w < h ? h : w);
}
