import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/boot_gate.dart';

// Regression coverage for the deep-link race: the boot screen's own
// pushReplacement (fired once its login-state/version checks finish) always
// replaces whichever route currently sits on top of the navigator — not
// specifically the boot screen's own route. If a challenge deep link
// resolved and pushed its screen first, the boot screen's later
// pushReplacement would silently discard it. The fix makes deep-link
// handling await BootGate.done before pushing, so it always lands after the
// boot screen's own navigation instead of racing it.
void main() {
  testWidgets(
      'a deep-linked push that awaits BootGate lands after, not before, '
      "the boot screen's own pushReplacement", (tester) async {
    // Reset here rather than in setUp(): flutter_test runs setUp() in a
    // different zone than the test body, so a Completer constructed there
    // never resolves through pump() — it just hangs until the test timeout.
    BootGate.resetForTest();

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('Boot')),
    ));

    // Simulate a deep link whose network fetch already resolved, so it's
    // now only waiting on the gate before it pushes — mirrors main.dart's
    // `await BootGate.done...; _navigatorKey.currentState?.push(...)`.
    final deepLinkPush = BootGate.done.then((_) {
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('ChallengeDetail')),
      ));
    });

    // Simulate the boot screen finishing its routing decision: it lands on
    // Dashboard via pushReplacement, then signals the gate — mirrors
    // main.dart's `_BootScreen._boot()`.
    navKey.currentState!.pushReplacement(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Dashboard')),
    ));
    BootGate.complete();

    await deepLinkPush;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('ChallengeDetail'), findsOneWidget,
        reason: 'the deep-linked screen must survive, not be wiped out by '
            "the boot screen's pushReplacement");

    final challengeContext = tester.element(find.text('ChallengeDetail'));
    expect(ModalRoute.of(challengeContext)!.isCurrent, isTrue,
        reason: 'ChallengeDetail must be the topmost route, not buried '
            "under the boot screen's pushReplacement destination");
  });
}
