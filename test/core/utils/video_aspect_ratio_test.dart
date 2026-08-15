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
}
