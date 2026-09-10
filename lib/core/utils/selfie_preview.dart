import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// Wraps a [CameraPreview] so the **front** camera shows the same,
/// un-mirrored image that actually gets recorded.
///
/// The `camera` plugin mirrors the front-camera *preview* selfie-style (as
/// every phone camera app does), but the saved video file is recorded
/// **un-mirrored** — the true optical image. Users therefore framed a mirror
/// image and then saw the "flipped" real one on the review screen and in the
/// feed.
///
/// We flip the *preview* back rather than mirroring the file: the recording,
/// the feed, other viewers, and the AI scorer all already see the
/// un-mirrored video, so matching the preview to the file is the change that
/// touches the least and keeps every surface consistent. See ADR 020.
///
/// Back / external lenses are returned unchanged.
Widget unmirroredIfFront(CameraController controller, Widget preview) {
  if (controller.description.lensDirection != CameraLensDirection.front) {
    return preview;
  }
  return Transform.scale(
    scaleX: -1,
    child: preview,
  );
}
