import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
