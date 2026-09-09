import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/challenges/widgets/aura_sense_loading_view.dart';

// Regression coverage: the "Aura Sense" analysing screen used a fixed 64pt
// percent readout and rigid spacing, so on smaller / shorter screens it
// looked oversized and pushed the column out of balance (and could overflow).
// The percent size is now derived from the device and capped, and the big
// number is wrapped in a FittedBox so it can never overflow its row.
//
// It also painted the tall diamond background with BoxFit.cover, which scaled
// the art up to fill height and cropped the diamond's bright points off both
// screen edges — the "oversized / disproportionate" look. It now uses
// BoxFit.contain (the art's border is pure black, so the letterbox is
// invisible) and the whole diamond stays framed.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AuraSenseLoadingView()));
    await tester.pump(); // build
    await tester.pump(const Duration(milliseconds: 100)); // enter/percent anim
  }

  List<String> drainExceptions(WidgetTester tester) {
    final out = <String>[];
    for (var e = tester.takeException(); e != null; e = tester.takeException()) {
      out.add(e.toString());
    }
    return out;
  }

  for (final size in const [
    Size(320, 568), // small / short phone
    Size(393, 852), // typical modern phone
    Size(412, 915), // tall phone (the reported screenshot's shape)
  ]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await pumpAt(tester, size);

      final errors = drainExceptions(tester);
      expect(
        errors.where((s) => s.toLowerCase().contains('overflow')),
        isEmpty,
        reason: 'no RenderFlex overflow expected at $size:\n${errors.join('\n')}',
      );
    });
  }

  testWidgets('the diamond background is contained, not cover-cropped',
      (tester) async {
    await pumpAt(tester, const Size(393, 852));
    drainExceptions(tester); // missing image assets in the test bundle

    final bg = tester.widgetList<Image>(find.byType(Image)).firstWhere(
          (i) => (i.image as AssetImage?)?.assetName.contains('Asset 132') ?? false,
          orElse: () => const Image(image: AssetImage('none')),
        );
    expect(bg.fit, BoxFit.contain,
        reason: 'cover crops the diamond points off the screen edges');
  });

  testWidgets('the percent readout scales down from the old fixed 64pt',
      (tester) async {
    await pumpAt(tester, const Size(360, 640));
    drainExceptions(tester); // missing image assets in the test bundle

    final percent = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (t) => RegExp(r'^\d+%$').hasMatch(t.data ?? ''),
          orElse: () => const Text(''),
        );
    expect(percent.data, isNotNull);
    expect(percent.style?.fontSize, isNotNull);
    expect(percent.style!.fontSize!, lessThanOrEqualTo(52.0),
        reason: 'percent font must be capped well below the old 64pt');
  });
}
