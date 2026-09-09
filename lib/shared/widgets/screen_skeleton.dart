import 'package:flutter/material.dart';

/// Full-screen shimmer placeholder shown in place of a loading spinner while
/// a top-level tab screen fetches its first payload.
///
/// [MainShell] normally *holds* on the current tab until the next one is
/// ready, so this is only ever seen if that hold times out (a genuinely
/// stuck load). It still exists so the fallback is a calm layout rather than
/// a spinning ring.
class ScreenSkeleton extends StatefulWidget {
  /// Roughly how many list/card rows to lay out under the header block.
  final int rows;

  const ScreenSkeleton({super.key, this.rows = 4});

  @override
  State<ScreenSkeleton> createState() => _ScreenSkeletonState();
}

class _ScreenSkeletonState extends State<ScreenSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final base = Color.lerp(
          const Color(0xFF14121F),
          const Color(0xFF221C33),
          t,
        )!;
        return ColoredBox(
          color: const Color(0xFF080810),
          child: SafeArea(
            child: SingleChildScrollView(
              // Never scrolls — the clamp just stops a RenderFlex overflow
              // when this is dropped into a short slot (e.g. a grid sliver).
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(base, height: 26, widthFactor: 0.5),
                  const SizedBox(height: 20),
                  _bar(base, height: 120, widthFactor: 1),
                  const SizedBox(height: 24),
                  for (var i = 0; i < widget.rows; i++) ...[
                    _bar(base, height: 64, widthFactor: 1),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double height, required double widthFactor}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
