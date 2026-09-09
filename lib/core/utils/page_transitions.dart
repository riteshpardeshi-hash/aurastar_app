import 'package:flutter/material.dart';

/// A quick cross-fade (with a barely-there scale) page transition, used for
/// switching between the top-level tab screens — Home / Search / Leaderboard
/// / Profile. It replaces the default platform push animation on those
/// routes so a tab switch reads as a smooth swap instead of a hard cut, and
/// it runs in both directions: fades in on push, fades back out on pop.
///
/// Deliberately short (~200ms in, ~150ms out) so it never gets in the way —
/// the destination screen still loads its own data right after.
Route<T> fadeThroughRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
