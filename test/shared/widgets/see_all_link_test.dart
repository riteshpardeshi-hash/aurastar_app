import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/shared/widgets/see_all_link.dart';

// Client, 25 Nov 2026: the AI ad section's "See all" looked different from the others, and
// the sections are now called Ai Ad Contests and Brand Challenges.
void main() {
  testWidgets('reads "See All >", with the count when given, and is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [SeeAllLink(onTap: () => taps++), SeeAllLink(onTap: () {}, count: 9)]),
    ));
    await tester.tap(find.text('See All >'));
    expect(taps, 1);
    expect(find.text('See All 9 >'), findsOneWidget);
  });

  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('no screen writes its own See all / View all link', () {
    final own = RegExp(r'''['"](see|view) all''', caseSensitive: false);
    final offenders = [
      for (final f in sources)
        for (final line in f.readAsLinesSync())
          if (!f.path.endsWith('see_all_link.dart') && !line.trimLeft().startsWith('//') && own.hasMatch(line))
            '${f.path}: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });

  test('the old section names are gone from what users read', () {
    final old = RegExp(r'''AI ad campaign|Brand Videos''', caseSensitive: false);
    // The client spells it "Ai Ad Contests" (25 Nov), not "AI".
    final aiCaps = RegExp(r'''AI Ad Contest''');
    final offenders = [
      for (final f in sources)
        for (final line in f.readAsLinesSync())
          if (!line.trimLeft().startsWith('//') && (old.hasMatch(line) || aiCaps.hasMatch(line))) '${f.path}: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });
}
