import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/selfie_preview.dart';

// The camera plugin mirrors the front-camera preview but records the file
// un-mirrored. unmirroredIfFront() flips the front preview back so what the
// user frames matches the saved video / the feed / the AI scorer. Back and
// external lenses must be left exactly as-is. See ADR 020.
void main() {
  CameraController controllerFor(CameraLensDirection dir) => CameraController(
        CameraDescription(
          name: dir.name,
          lensDirection: dir,
          sensorOrientation: 270,
        ),
        ResolutionPreset.high,
      );

  const child = SizedBox(key: Key('preview'));

  testWidgets('front camera preview is horizontally flipped (scaleX = -1)',
      (tester) async {
    final front = controllerFor(CameraLensDirection.front);
    addTearDown(() {
      try {
        front.dispose();
      } catch (_) {}
    });

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: unmirroredIfFront(front, child),
    ));

    final transform = tester.widget<Transform>(
      find.ancestor(of: find.byKey(const Key('preview')),
          matching: find.byType(Transform)),
    );
    // Row 0 / col 0 is horizontal scale, row 1 / col 1 vertical.
    expect(transform.transform.storage[0], -1.0,
        reason: 'front preview must be mirrored horizontally to match the file');
    expect(transform.transform.storage[5], 1.0,
        reason: 'no vertical flip');
  });

  testWidgets('back camera preview is returned untouched (no Transform)',
      (tester) async {
    final back = controllerFor(CameraLensDirection.back);
    addTearDown(() {
      try {
        back.dispose();
      } catch (_) {}
    });

    final result = unmirroredIfFront(back, child);
    expect(identical(result, child), isTrue,
        reason: 'back lens preview must be passed through unchanged');

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: result,
    ));
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('external camera preview is also left untouched', (tester) async {
    final external = controllerFor(CameraLensDirection.external);
    addTearDown(() {
      try {
        external.dispose();
      } catch (_) {}
    });

    expect(identical(unmirroredIfFront(external, child), child), isTrue);
  });
}
