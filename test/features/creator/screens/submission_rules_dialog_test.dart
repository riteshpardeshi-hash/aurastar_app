import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/features/creator/screens/creator_challenge_status_screen.dart';

void main() {
  // Regression: with many rules the dialog's non-scrolling Column overflowed,
  // pushing the checkbox and Cancel/Submit off screen.
  testWidgets('a long rules list scrolls instead of overflowing',
      (tester) async {
    final rules = List.generate(
        12, (i) => {'title': 'Rule $i', 'description': 'Detail ' * 25});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => SubmissionRulesDialog(rules: rules)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('I acknowledge these rules'), findsOneWidget);
  });

  // Regression: the acknowledge checkbox lived at the end of the scrolling
  // rules list, so it started off screen and Submit sat greyed out with no
  // visible reason. It must be on screen — and tappable — without scrolling.
  testWidgets('the acknowledge checkbox is visible without scrolling and enables Submit',
      (tester) async {
    final rules = List.generate(
        12, (i) => {'title': 'Rule $i', 'description': 'Detail ' * 25});
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<bool>(
              context: context,
              builder: (_) => SubmissionRulesDialog(rules: rules)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final ack = find.text('I acknowledge these rules');
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final box = tester.getRect(ack);
    expect(box.top >= 0 && box.bottom <= screen.height, isTrue,
        reason: 'checkbox must be on screen before any scrolling');

    // Submit does nothing until acknowledged…
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    // …and works straight after ticking it — no scrolling involved.
    await tester.tap(ack);
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
