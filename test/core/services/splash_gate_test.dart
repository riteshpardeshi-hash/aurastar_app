import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/services/splash_gate.dart';

// Regression coverage for the deep-link race: SplashScreen's own
// pushReplacement (fired when its onboarding carousel or fast-boot check
// finishes) always replaces whichever route currently sits on top of the
// navigator — not specifically Splash's own route. If a challenge deep link
// resolved and pushed its screen first, Splash's later pushReplacement would
// silently discard it. The fix makes deep-link handling await
// SplashGate.done before pushing, so it always lands after Splash's own
// navigation instead of racing it.
void main() {
  testWidgets(
      'a deep-linked push that awaits SplashGate lands after, not before, '
      "Splash's own pushReplacement", (tester) async {
    // Reset here rather than in setUp(): flutter_test runs setUp() in a
    // different zone than the test body, so a Completer constructed there
    // never resolves through pump() — it just hangs until the test timeout.
    SplashGate.resetForTest();

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('Splash')),
    ));

    // Simulate a deep link whose network fetch already resolved, so it's
    // now only waiting on the gate before it pushes — mirrors main.dart's
    // `await SplashGate.done...; _navigatorKey.currentState?.push(...)`.
    final deepLinkPush = SplashGate.done.then((_) {
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('ChallengeDetail')),
      ));
    });

    // Simulate Splash finishing its onboarding/fast-boot check: it lands on
    // Dashboard via pushReplacement, then signals the gate — mirrors
    // splash_screen.dart's _goToApp().
    navKey.currentState!.pushReplacement(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Dashboard')),
    ));
    SplashGate.complete();

    await deepLinkPush;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('ChallengeDetail'), findsOneWidget,
        reason: 'the deep-linked screen must survive, not be wiped out by '
            "Splash's pushReplacement");

    final challengeContext = tester.element(find.text('ChallengeDetail'));
    expect(ModalRoute.of(challengeContext)!.isCurrent, isTrue,
        reason: 'ChallengeDetail must be the topmost route, not buried '
            "under Splash's pushReplacement destination");
  });
}
