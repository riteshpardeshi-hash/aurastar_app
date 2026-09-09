import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/page_transitions.dart';

// Coverage for the tab-switch transition: switching between top-level tabs
// used to hard-cut (and flash the Dashboard in between). fadeThroughRoute is
// the shared quick cross-fade that AppBottomNav now uses instead.
void main() {
  test('is a quick transition in both directions', () {
    final route = fadeThroughRoute<void>((_) => const SizedBox());
    expect(route, isA<PageRoute<void>>());
    final transition = route as TransitionRoute<void>;
    expect(transition.transitionDuration.inMilliseconds, lessThanOrEqualTo(250));
    expect(transition.reverseTransitionDuration.inMilliseconds,
        lessThanOrEqualTo(transition.transitionDuration.inMilliseconds));
  });

  testWidgets('cross-fades the destination in on push', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              fadeThroughRoute<void>((_) => const Text('destination')),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump(); // start the transition
    await tester.pump(const Duration(milliseconds: 90)); // mid-flight

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('destination'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, greaterThan(0.0));
    expect(fade.opacity.value, lessThan(1.0),
        reason: 'destination should still be fading in mid-transition');

    await tester.pumpAndSettle();
    expect(find.text('destination'), findsOneWidget);
    expect(fade.opacity.value, 1.0);
  });

  testWidgets('returns a result when popped', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.push<String>(
                context,
                fadeThroughRoute<String>(
                  (_) => Builder(
                    builder: (c) => ElevatedButton(
                      onPressed: () => Navigator.pop(c, 'picked'),
                      child: const Text('close'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(result, 'picked');
  });
}
