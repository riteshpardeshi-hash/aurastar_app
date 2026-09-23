import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Wraps a feed item and reports a challenge **impression** the first time the
/// item becomes at least [threshold] visible in the viewport.
///
/// Re-arms once the item scrolls fully off-screen, so scrolling a card away
/// and back counts as a new impression — that matches the "every on-screen
/// sighting" definition (backend ADR 090 / mobile ADR 019). The report is
/// fire-and-forget; [onImpression] must never throw or block.
///
/// Usage — one per card in a feed's item builder:
/// ```dart
/// ImpressionTracker(
///   detectorKey: ValueKey('imp-$challengeId'),
///   onImpression: () => ChallengeAnalyticsService().recordImpression(challengeId),
///   child: ChallengeCard(...),
/// )
/// ```
///
/// [detectorKey] must be **stable and unique** per logical item. Prefer a key
/// derived from the item's id (`ValueKey('imp-$challengeId')`); do not use the
/// list index alone (it reshuffles as items load) and do not reuse one key for
/// two cards on screen at once — `VisibilityDetector` silently tracks only the
/// last widget mounted with a given key.
class ImpressionTracker extends StatefulWidget {
  const ImpressionTracker({
    super.key,
    required this.detectorKey,
    required this.onImpression,
    required this.child,
    this.threshold = 0.5,
    this.enabled = true,
  });

  /// Key for the underlying [VisibilityDetector]. Stable + unique per item.
  final Key detectorKey;

  /// Called once each time the item crosses from "< [threshold] visible" to
  /// "≥ [threshold] visible" (after having been fully off-screen, or on first
  /// appearance).
  final VoidCallback onImpression;

  final Widget child;

  /// Fraction of the item that must be visible to count as an impression.
  final double threshold;

  /// When false the child renders untouched and no `VisibilityDetector` is
  /// mounted — use in tests / previews that don't exercise impressions.
  final bool enabled;

  @override
  State<ImpressionTracker> createState() => _ImpressionTrackerState();
}

class _ImpressionTrackerState extends State<ImpressionTracker> {
  /// True once this on-screen pass has been counted; reset when the item goes
  /// fully off-screen so the next pass counts again.
  bool _countedThisPass = false;

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted || !widget.enabled) return;
    final fraction = info.visibleFraction;

    if (!_countedThisPass && fraction >= widget.threshold) {
      _countedThisPass = true;
      widget.onImpression();
    } else if (_countedThisPass && fraction == 0.0) {
      _countedThisPass = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return VisibilityDetector(
      key: widget.detectorKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
