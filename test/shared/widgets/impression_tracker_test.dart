import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:aura_app/shared/widgets/impression_tracker.dart';

// ImpressionTracker fires one challenge impression per ≥threshold-visible
// pass and re-arms after the card goes fully off-screen, so a scroll away and
// back counts again — the "every on-screen sighting" rule from mobile ADR 019
// / backend ADR 090.
void main() {
  setUp(() {
    // Make VisibilityDetector callbacks fire on the next frame instead of
    // after its default 500ms debounce.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Widget host({
    required Widget tracked,
    double viewportHeight = 600,
    double leadingSpacer = 800,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: viewportHeight,
            child: ListView(
              children: [
                SizedBox(height: leadingSpacer, key: const Key('spacer')),
                tracked,
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('fires once when the item is on screen from the start',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(host(
      leadingSpacer: 0,
      tracked: ImpressionTracker(
        detectorKey: const Key('imp-chal-1'),
        onImpression: () => count++,
        child: const SizedBox(height: 200, child: Text('card')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(count, 1);
  });

  testWidgets('does not fire while the item is scrolled out of view',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(host(
      tracked: ImpressionTracker(
        detectorKey: const Key('imp-chal-1'),
        onImpression: () => count++,
        child: const SizedBox(height: 200, child: Text('card')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(count, 0, reason: 'card sits below an 800px spacer in a 600px viewport');
  });

  testWidgets('scrolling the item into view, away, and back counts twice',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(host(
      tracked: ImpressionTracker(
        detectorKey: const Key('imp-chal-1'),
        onImpression: () => count++,
        child: const SizedBox(height: 200, child: Text('card')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(count, 0);

    // Scroll it into view.
    await tester.drag(find.byType(Scrollable), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(count, 1);

    // Scroll it fully back off-screen — this re-arms the tracker.
    await tester.drag(find.byType(Scrollable), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(count, 1);

    // Scroll it back into view — a fresh sighting, a fresh impression.
    await tester.drag(find.byType(Scrollable), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(count, 2);
  });

  testWidgets('enabled: false renders the child and never fires', (tester) async {
    var count = 0;
    await tester.pumpWidget(host(
      leadingSpacer: 0,
      tracked: ImpressionTracker(
        detectorKey: const Key('imp-chal-1'),
        enabled: false,
        onImpression: () => count++,
        child: const SizedBox(height: 200, child: Text('card')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('card'), findsOneWidget);
    expect(find.byType(VisibilityDetector), findsNothing);
    expect(count, 0);
  });
}
