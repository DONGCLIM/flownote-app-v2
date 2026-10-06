import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// 시안 원본 차트 3종을 수식까지 1:1로 옮긴 구현.
/// 원본은 SVG. Flutter는 CustomPainter로 동일 좌표계를 재현한다.

class FnChartDatum {
  const FnChartDatum({required this.label, required this.value, this.color});
  final String label;
  final double value;
  final Color? color;
}

// ---------------------------------------------------------------------------
// BarChart
// ---------------------------------------------------------------------------
/// ```js
/// function BarChart({ data, width=320, height=120, barColor, onBar, activeIndex })
///   max = Math.max(...values);  bw = width / data.length
///   rect x: i*bw + bw*0.22,  y: height-h,  w: bw*0.56,  h: max(h,2),  rx:3
///        fill: active ? blue-50 : barColor,  opacity: active ? 1 : 0.55
///   text x: i*bw + bw/2,  y: height+13,  fontSize:9,  fill: label-assistive,  anchor:middle
///   svg height = height + 18
/// ```
class FnBarChart extends StatelessWidget {
  const FnBarChart({
    super.key,
    required this.data,
    this.width = 320,
    this.height = 120,
    this.barColor,
    this.activeIndex,
    this.onBar,
  });

  final List<FnChartDatum> data;
  final double width;
  final double height;
  final Color? barColor;
  final int? activeIndex;
  final ValueChanged<int>? onBar;

  @override
  Widget build(BuildContext context) {
    final size = Size(width, height + 18);
    Widget chart = CustomPaint(
      size: size,
      painter: _BarPainter(
        data: data,
        chartHeight: height,
        barColor: barColor ?? FnColors.primaryNormal,
        activeIndex: activeIndex,
      ),
    );
    if (onBar != null) {
      chart = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          if (data.isEmpty) return;
          final bw = width / data.length;
          final i = (d.localPosition.dx / bw).floor();
          if (i >= 0 && i < data.length) onBar!(i);
        },
        child: chart,
      );
    }
    return SizedBox(width: width, height: height + 18, child: chart);
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.data,
    required this.chartHeight,
    required this.barColor,
    this.activeIndex,
  });

  final List<FnChartDatum> data;
  final double chartHeight;
  final Color barColor;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxV = data.map((d) => d.value).reduce(math.max);
    final bw = size.width / data.length;

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final h = maxV == 0 ? 0.0 : (d.value / maxV) * chartHeight;
      final active = activeIndex == i;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * bw + bw * 0.22,
          chartHeight - h,
          bw * 0.56,
          math.max(h, 2),
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = (d.color ?? barColor).withValues(alpha: active ? 1.0 : 0.55),
      );

      // label: fontSize 9, label-assistive, middle anchor, y = height + 13
      final tp = TextPainter(
        text: TextSpan(
          text: d.label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 9,
            color: FnColors.labelAssistive,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(i * bw + bw / 2 - tp.width / 2, chartHeight + 13 - tp.height * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.data != data || old.activeIndex != activeIndex;
}

// ---------------------------------------------------------------------------
// LineChart
// ---------------------------------------------------------------------------
/// ```js
/// function LineChart({ data, width=320, height=100, color=blue-50 })
///   padX=14, padY=16
///   stepX = (width - padX*2) / (n-1)
///   x = padX + i*stepX
///   y = height - padY - ((v-min)/range) * (height - padY*2)
///   path strokeWidth 2.5 round;  circle r 3.5
///   text y = height+12, fontSize 9, anchor: first=start, last=end, else middle
///   svg height = height + 16
/// ```
class FnLineChart extends StatelessWidget {
  const FnLineChart({
    super.key,
    required this.data,
    this.width = 320,
    this.height = 100,
    this.color,
  });

  final List<FnChartDatum> data;
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height + 16,
      child: CustomPaint(
        size: Size(width, height + 16),
        painter: _LinePainter(
          data: data,
          chartHeight: height,
          color: color ?? FnColors.primaryNormal,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.data,
    required this.chartHeight,
    required this.color,
  });

  final List<FnChartDatum> data;
  final double chartHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final vals = data.map((d) => d.value).toList();
    final maxV = vals.reduce(math.max);
    final minV = vals.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    const padX = 14.0, padY = 16.0;
    final stepX = data.length > 1 ? (size.width - padX * 2) / (data.length - 1) : 0.0;

    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      pts.add(Offset(
        padX + i * stepX,
        chartHeight - padY - ((data[i].value - minV) / range) * (chartHeight - padY * 2),
      ));
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    final dot = Paint()..color = color;
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, dot);
    }

    for (var i = 0; i < pts.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: data[i].label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 9,
            color: FnColors.labelAssistive,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double dx;
      if (i == 0) {
        dx = pts[i].dx; // anchor start
      } else if (i == pts.length - 1) {
        dx = pts[i].dx - tp.width; // anchor end
      } else {
        dx = pts[i].dx - tp.width / 2; // middle
      }
      tp.paint(canvas, Offset(dx, chartHeight + 12 - tp.height * 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.data != data;
}

// ---------------------------------------------------------------------------
// Donut
// ---------------------------------------------------------------------------
/// ```js
/// function Donut({ data, size=132, thickness=24, onSlice, activeIndex, rotate=-90 })
///   pad = 4
///   r = (size - thickness)/2,  cx = cy = size/2 + pad,  C = 2πr
///   각 조각: strokeDasharray = frac*C,  strokeDashoffset = -acc*C
///   strokeWidth = active ? thickness+4 : thickness
///   전체 rotate(rotate) 적용
///   svg = (size + pad*2) 정사각
/// ```
class FnDonut extends StatelessWidget {
  const FnDonut({
    super.key,
    required this.data,
    this.size = 132,
    this.thickness = 24,
    this.activeIndex,
    this.rotate = -90,
    this.onSlice,
  });

  final List<FnChartDatum> data;
  final double size;
  final double thickness;
  final int? activeIndex;

  /// 시안과 동일하게 **도(degree)** 단위
  final double rotate;
  final ValueChanged<int>? onSlice;

  @override
  Widget build(BuildContext context) {
    const pad = 4.0;
    final box = size + pad * 2;
    Widget chart = CustomPaint(
      size: Size(box, box),
      painter: _DonutPainter(
        data: data,
        size: size,
        thickness: thickness,
        activeIndex: activeIndex,
        rotate: rotate,
      ),
    );
    if (onSlice != null) {
      chart = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final c = Offset(box / 2, box / 2);
          final v = d.localPosition - c;
          // 시안 rotate 기준으로 각도 환산
          var deg = math.atan2(v.dy, v.dx) * 180 / math.pi - rotate;
          deg %= 360;
          if (deg < 0) deg += 360;
          final total = data.fold<double>(0, (s, e) => s + e.value);
          if (total <= 0) return;
          var acc = 0.0;
          for (var i = 0; i < data.length; i++) {
            final sweep = data[i].value / total * 360;
            if (deg >= acc && deg < acc + sweep) {
              onSlice!(i);
              return;
            }
            acc += sweep;
          }
        },
        child: chart,
      );
    }
    return SizedBox(width: box, height: box, child: chart);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.data,
    required this.size,
    required this.thickness,
    required this.rotate,
    this.activeIndex,
  });

  final List<FnChartDatum> data;
  final double size;
  final double thickness;
  final double rotate;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final total = data.fold<double>(0, (s, d) => s + d.value);
    if (total <= 0) return;
    const pad = 4.0;
    final r = (size - thickness) / 2;
    final c = Offset(size / 2 + pad, size / 2 + pad);
    final rect = Rect.fromCircle(center: c, radius: r);
    final rotRad = rotate * math.pi / 180;

    var acc = 0.0;
    for (var i = 0; i < data.length; i++) {
      final frac = data[i].value / total;
      final active = activeIndex == i;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? thickness + 4 : thickness
        ..color = data[i].color ?? FnColors.primaryNormal;
      canvas.drawArc(
        rect,
        rotRad + acc * 2 * math.pi,
        frac * 2 * math.pi,
        false,
        paint,
      );
      acc += frac;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.data != data || old.activeIndex != activeIndex;
}
