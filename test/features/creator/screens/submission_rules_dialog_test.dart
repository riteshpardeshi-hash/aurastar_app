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
    await tester.scrollUntilVisible(find.text('I acknowledge these rules'), 200);
    expect(find.text('I acknowledge these rules'), findsOneWidget);
  });
}
