import 'package:aura_app/core/utils/share_origin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPadOS needs a non-empty `sharePositionOrigin` for every share sheet (ADR 037).
void main() {
  testWidgets('returns the widget\'s own on-screen rect', (tester) async {
    late BuildContext buttonContext;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 40, top: 100),
          child: Builder(builder: (context) {
            buttonContext = context;
            return const SizedBox(width: 120, height: 48);
          }),
        ),
      ),
    ));

    expect(shareOrigin(buttonContext), const Rect.fromLTWH(40, 100, 120, 48));
  });

  testWidgets('falls back to a non-empty rect in the middle of the screen when the widget has no size',
      (tester) async {
    late BuildContext emptyContext;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: Builder(builder: (context) {
          emptyContext = context;
          return const SizedBox.shrink();
        }),
      ),
    ));

    final rect = shareOrigin(emptyContext);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.isEmpty, isFalse);
    expect(rect.center, screen.center(Offset.zero));
  });
}
