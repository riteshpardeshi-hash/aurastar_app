import 'package:flutter/material.dart';

/// Single-series time-series line/area chart for one insights metric.
/// One series never needs a legend box — the caller's section title already
/// names the metric. Drag or tap to scrub a crosshair + value tooltip.
class CreatorInsightsChart extends StatefulWidget {
  final List<MapEntry<String, num>> points;
  final Color color;

  const CreatorInsightsChart({
    super.key,
    required this.points,
    this.color = const Color(0xFF7B2CBF),
  });

  @override
  State<CreatorInsightsChart> createState() => _CreatorInsightsChartState();
}

class _CreatorInsightsChartState extends State<CreatorInsightsChart> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
            child: Text('No data for this period', style: TextStyle(color: Colors.white38, fontSize: 12))),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        onHorizontalDragUpdate: (d) => _updateHover(d.localPosition.dx, width),
        onHorizontalDragStart: (d) => _updateHover(d.localPosition.dx, width),
        onTapUp: (d) => _updateHover(d.localPosition.dx, width),
        onHorizontalDragEnd: (_) => setState(() => _hoverIndex = null),
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: CustomPaint(
            size: Size(width, 200),
            painter: _ChartPainter(points: widget.points, color: widget.color, hoverIndex: _hoverIndex),
          ),
        ),
      );
    });
  }

  void _updateHover(double dx, double width) {
    final n = widget.points.length;
    if (n == 0) return;
    const leftPad = 34.0, rightPad = 8.0;
    final plotWidth = (width - leftPad - rightPad).clamp(1.0, double.infinity);
    final step = n > 1 ? plotWidth / (n - 1) : plotWidth;
    var idx = ((dx - leftPad) / step).round();
    idx = idx.clamp(0, n - 1);
    setState(() => _hoverIndex = idx);
  }
}

class _ChartPainter extends CustomPainter {
  final List<MapEntry<String, num>> points;
  final Color color;
  final int? hoverIndex;

  static const _leftPad = 34.0;
  static const _rightPad = 8.0;
  static const _topPad = 10.0;
  static const _bottomPad = 20.0;

  _ChartPainter({required this.points, required this.color, this.hoverIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final maxVal = points.map((p) => p.value.toDouble()).fold<double>(0, (a, b) => b > a ? b : a);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;
    final plotWidth = (size.width - _leftPad - _rightPad).clamp(1.0, double.infinity);
    final plotHeight = (size.height - _topPad - _bottomPad).clamp(1.0, double.infinity);
    final stepX = n > 1 ? plotWidth / (n - 1) : plotWidth;

    Offset pointAt(int i) {
      final x = _leftPad + stepX * i;
      final y = _topPad + plotHeight - (points[i].value / safeMax * plotHeight);
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = _topPad + plotHeight - (plotHeight * i / 3);
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width - _rightPad, y), gridPaint);
    }

    void label(String text, Offset offset, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      tp.paint(canvas, offset);
    }

    label(_compact(safeMax), Offset(0, _topPad - 6));
    label('0', Offset(0, _topPad + plotHeight - 6));

    final path = Path();
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      final p = pointAt(i);
      if (i == 0) {
        fillPath.moveTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    fillPath.lineTo(pointAt(n - 1).dx, _topPad + plotHeight);
    fillPath.lineTo(pointAt(0).dx, _topPad + plotHeight);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.10));

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    const bg = Color(0xFF080810);
    final endPoint = pointAt(n - 1);
    canvas.drawCircle(endPoint, 6, Paint()..color = bg);
    canvas.drawCircle(endPoint, 4, Paint()..color = color);
    label('${points.last.value}', Offset((endPoint.dx - 12).clamp(0, size.width - 24), endPoint.dy - 18));

    label(points.first.key, Offset(_leftPad, size.height - 14));
    final lastLabelTp = TextPainter(
      text: TextSpan(text: points.last.key, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    lastLabelTp.paint(canvas, Offset(size.width - _rightPad - lastLabelTp.width, size.height - 14));

    if (hoverIndex != null) {
      final hp = pointAt(hoverIndex!);
      canvas.drawLine(Offset(hp.dx, _topPad), Offset(hp.dx, _topPad + plotHeight),
          Paint()..color = Colors.white.withValues(alpha: 0.18)..strokeWidth = 1);
      canvas.drawCircle(hp, 6, Paint()..color = bg);
      canvas.drawCircle(hp, 4, Paint()..color = color);

      final point = points[hoverIndex!];
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: '${point.value}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          TextSpan(text: '  ${point.key}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
        textDirection: TextDirection.ltr,
      )..layout();
      final boxLeft = (hp.dx - tp.width / 2 - 8).clamp(0.0, size.width - tp.width - 16);
      final rect = Rect.fromLTWH(boxLeft, 0, tp.width + 16, 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = const Color(0xFF1A0A2E),
      );
      tp.paint(canvas, Offset(rect.left + 8, rect.top + 4));
    }
  }

  String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.hoverIndex != hoverIndex;
}
