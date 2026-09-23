import 'dart:async';

import 'package:visibility_detector/visibility_detector.dart';

/// Auto-loaded by `flutter test` for every test under `test/`.
///
/// `VisibilityDetector` (used by `ImpressionTracker` on the feed screens)
/// schedules its visibility callbacks on a timer whose default 500ms interval
/// outlives a widget test's pump/settle cycle — the pending update then fires
/// against a torn-down tree and throws inside `RenderVisibilityDetectorBase`.
/// Zeroing the interval makes callbacks run synchronously on the next frame,
/// which is both what impression tests want and what keeps unrelated screen
/// tests from tripping over the detector.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  await testMain();
}
