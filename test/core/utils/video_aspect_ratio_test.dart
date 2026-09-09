import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:aura_app/core/utils/video_aspect_ratio.dart';

// Regression coverage: a submission recorded upright but captured with the
// device rotated (or otherwise needing rotation) reported a
// `rotationCorrection` of 90/270 from the native decoder — `VideoPlayer`
// itself rotates its platform view with a `RotatedBox` in that case, but
// every screen sizing an `AspectRatio` box around it used the raw, unswapped
// `VideoPlayerValue.aspectRatio` (just size.width / size.height). That sized
// the box for the *pre-rotation* (landscape) shape while the rotated content
// inside was actually portrait — the mismatch is what made an upright video
// appear squeezed/sideways on screen despite the platform view having
// rotated the pixels correctly.
void main() {
  VideoPlayerValue valueFor({
    required Size size,
    required int rotationCorrection,
  }) {
    return VideoPlayerValue(
      duration: const Duration(seconds: 10),
      size: size,
      isInitialized: true,
      rotationCorrection: rotationCorrection,
    );
  }

  test('no rotation correction: aspect ratio is used as-is', () {
    final value =
        valueFor(size: const Size(1080, 1920), rotationCorrection: 0);
    expect(correctedVideoAspectRatio(value), value.aspectRatio);
  });

  test('90-degree rotation correction: width/height are swapped', () {
    // A landscape-reported raw frame (1920x1080, aspectRatio ~1.78) that
    // actually needs a 90-degree rotation to display as the portrait video
    // it really is — the corrected ratio must be the inverse (~0.5625).
    final value =
        valueFor(size: const Size(1920, 1080), rotationCorrection: 90);
    expect(correctedVideoAspectRatio(value), closeTo(1080 / 1920, 0.0001));
  });

  test('270-degree rotation correction: width/height are swapped', () {
    final value =
        valueFor(size: const Size(1920, 1080), rotationCorrection: 270);
    expect(correctedVideoAspectRatio(value), closeTo(1080 / 1920, 0.0001));
  });

  test('180-degree rotation correction: aspect ratio is unaffected', () {
    // A 180-degree flip doesn't change which dimension is width vs height.
    final value =
        valueFor(size: const Size(1080, 1920), rotationCorrection: 180);
    expect(correctedVideoAspectRatio(value), value.aspectRatio);
  });

  // Regression: a CameraX-recorded challenge reference clip
  // (womaty-dev-raw-clips .mp4, played from the on-disk cache) reported
  // `size: 480x640` — ALREADY the rotated, portrait display dimensions —
  // *and still* carried `rotationCorrection: 270`. The old code inverted on
  // any 90/270 flag, turning the correct 0.75 portrait ratio into 1.333, so
  // `ChallengeDetail`'s fullscreen `AspectRatio` box became landscape and
  // squeezed the portrait video into a letterboxed strip (the admin panel's
  // browser <video>, which just reads the rotation matrix, showed it
  // correctly). Fix: only invert when `size` is still landscape-shaped.
  test('90/270 flag on an already-portrait size is NOT inverted (double-'
      'correction bug)', () {
    final r270 = valueFor(size: const Size(480, 640), rotationCorrection: 270);
    expect(correctedVideoAspectRatio(r270), closeTo(480 / 640, 0.0001));
    expect(correctedVideoAspectRatio(r270), lessThan(1),
        reason: 'a portrait clip must get a portrait (<1) box');

    final r90 = valueFor(size: const Size(1080, 1920), rotationCorrection: 90);
    expect(correctedVideoAspectRatio(r90), closeTo(1080 / 1920, 0.0001));
  });

  test('degenerate zero size falls back to the raw aspectRatio, no divide-'
      'by-zero', () {
    final value = valueFor(size: Size.zero, rotationCorrection: 90);
    expect(correctedVideoAspectRatio(value), value.aspectRatio);
  });
}
