import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// 차트 데이터 한 점
class FnChartDatum {
  const FnChartDatum({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final double value;
  final Color? color;
}

// ═══════════════════════════════════════════════
// Bar Chart
// ═══════════════════════════════════════════════

/// 프로토타입 FN.BarChart 이식
///
/// 막대 폭 = 슬롯의 56%, 반경 3, 비활성 투명도 0.55
class FnBarChart extends StatelessWidget {
  const FnBarChart({
    super.key,
    required this.data,
    this.height = 120,
    this.barColor,
    this.activeIndex,
    this.onBarTap,
    this.showLabels = true,
  });

  final List<FnChartDatum> data;
  final double height;
  final Color? barColor;
  final int? activeIndex;
  final ValueChanged<int>? onBarTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);
    final max = data.map((d) => d.value).reduce(math.max);
    final c = barColor ?? FnColors.primaryNormal;

    return SizedBox(
      height: height + (showLabels ? 18 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(data.length, (i) {
          final d = data[i];
          final h = max > 0 ? (d.value / max) * height : 0.0;
          final active = activeIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: onBarTap == null ? null : () => onBarTap!(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.56,
                    child: AnimatedContainer(
                      duration: FnDuration.normal,
                      curve: Curves.easeOutCubic,
                      height: math.max(h, 2),
                      decoration: BoxDecoration(
                        color: (d.color ?? c)
                            .withValues(alpha: active ? 1.0 : 0.55),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                          bottom: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  if (showLabels)
                    SizedBox(
                      height: 18,
                      child: Center(
                        child: Text(
                          d.label,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 9,
                            color: active
                                ? FnColors.labelNormal
                                : FnColors.labelAssistive,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Line Chart
// ═══════════════════════════════════════════════

/// 프로토타입 FN.LineChart 이식
class FnLineChart extends StatelessWidget {
  const FnLineChart({
    super.key,
    required this.data,
    this.height = 100,
    this.color,
    this.showLabels = true,
    this.showArea = true,
  });

  final List<FnChartDatum> data;
  final double height;
  final Color? color;
  final bool showLabels;
  final bool showArea;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);
    return SizedBox(
      height: height + (showLabels ? 16 : 0),
      child: CustomPaint(
        painter: _LinePainter(
          data: data,
          color: color ?? FnColors.primaryNormal,
          showLabels: showLabels,
          showArea: showArea,
          chartHeight: height,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.data,
    required this.color,
    required this.showLabels,
    required this.showArea,
    required this.chartHeight,
  });

  final List<FnChartDatum> data;
  final Color color;
  final bool showLabels;
  final bool showArea;
  final double chartHeight;

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 14.0;
    const padY = 16.0;

    final vals = data.map((d) => d.value).toList();
    final maxV = vals.reduce(math.max);
    final minV = vals.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);

    final stepX =
        data.length > 1 ? (size.width - padX * 2) / (data.length - 1) : 0.0;

    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = padX + i * stepX;
      final y = chartHeight -
          padY -
          ((data[i].value - minV) / range) * (chartHeight - padY * 2);
      pts.add(Offset(x, y));
    }

    // 면 채우기
    if (showArea && pts.length > 1) {
      final area = Path()..moveTo(pts.first.dx, chartHeight);
      for (final p in pts) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(pts.last.dx, chartHeight)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, chartHeight)),
      );
    }

    // 선
    final linePath = Path();
    for (var i = 0; i < pts.length; i++) {
      i == 0
          ? linePath.moveTo(pts[i].dx, pts[i].dy)
          : linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 점
    final dotPaint = Paint()..color = color;
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, dotPaint);
    }

    // 라벨
    if (showLabels) {
      for (var i = 0; i < data.length; i++) {
        final tp = TextPainter(
          text: TextSpan(
            text: data[i].label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 9,
              color: FnColors.labelAssistive,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double dx;
        if (i == 0) {
          dx = pts[i].dx;
        } else if (i == data.length - 1) {
          dx = pts[i].dx - tp.width;
        } else {
          dx = pts[i].dx - tp.width / 2;
        }
        tp.paint(canvas, Offset(dx, chartHeight + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.data != data || old.color != color;
}

// ═══════════════════════════════════════════════
// Donut Chart
// ═══════════════════════════════════════════════

/// 프로토타입 FN.Donut 이식
///
/// 면세/과세 비중 등에 사용. 활성 조각은 두께 +4.
class FnDonutChart extends StatelessWidget {
  const FnDonutChart({
    super.key,
    required this.data,
    this.size = 132,
    this.thickness = 24,
    this.activeIndex,
    this.onSliceTap,
    this.center,
  });

  final List<FnChartDatum> data;
  final double size;
  final double thickness;
  final int? activeIndex;
  final ValueChanged<int>? onSliceTap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTapDown: onSliceTap == null
                ? null
                : (d) {
                    final i = _hitTest(d.localPosition);
                    if (i != null) onSliceTap!(i);
                  },
            child: CustomPaint(
              size: Size(size, size),
              painter: _DonutPainter(
                data: data,
                thickness: thickness,
                activeIndex: activeIndex,
              ),
            ),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }

  int? _hitTest(Offset pos) {
    final c = Offset(size / 2, size / 2);
    final v = pos - c;
    final dist = v.distance;
    final rOuter = size / 2;
    final rInner = rOuter - thickness;
    if (dist < rInner || dist > rOuter) return null;

    var angle = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final total = data.fold<double>(0, (s, d) => s + d.value);
    if (total == 0) return null;
    var acc = 0.0;
    for (var i = 0; i < data.length; i++) {
      final frac = data[i].value / total;
      if (angle >= acc * 2 * math.pi && angle < (acc + frac) * 2 * math.pi) {
        return i;
      }
      acc += frac;
    }
    return null;
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.data,
    required this.thickness,
    this.activeIndex,
  });

  final List<FnChartDatum> data;
  final double thickness;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(0, (s, d) => s + d.value);
    if (total <= 0) return;

    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - thickness) / 2;

    var start = -math.pi / 2;
    for (var i = 0; i < data.length; i++) {
      final sweep = (data[i].value / total) * 2 * math.pi;
      final active = activeIndex == i;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        Paint()
          ..color = data[i].color ?? FnColors.primaryNormal
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? thickness + 4 : thickness,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.data != data || old.activeIndex != activeIndex;
}

/// 차트 범례
class FnChartLegend extends StatelessWidget {
  const FnChartLegend({
    super.key,
    required this.data,
    this.activeIndex,
    this.onTap,
    this.showPercent = true,
    this.axis = Axis.vertical,
  });

  final List<FnChartDatum> data;
  final int? activeIndex;
  final ValueChanged<int>? onTap;
  final bool showPercent;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final total = data.fold<double>(0, (s, d) => s + d.value);
    final items = List.generate(data.length, (i) {
      final d = data[i];
      final pct = total > 0 ? (d.value / total * 100) : 0.0;
      final active = activeIndex == i;
      return GestureDetector(
        onTap: onTap == null ? null : () => onTap!(i),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: d.color ?? FnColors.primaryNormal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: FnSpace.x6),
              Text(
                d.label,
                style: FnType.caption1.copyWith(
                  color: active
                      ? FnColors.labelNormal
                      : FnColors.labelAlternative,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (showPercent) ...[
                const SizedBox(width: FnSpace.x6),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: FnType.caption1.copyWith(
                    color: FnColors.labelNormal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });

    return axis == Axis.vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: items)
        : Wrap(spacing: FnSpace.x12, children: items);
  }
}

/// 진행률 바
class FnProgressBar extends StatelessWidget {
  const FnProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.backgroundColor,
  });

  /// 0.0 ~ 1.0
  final double value;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: backgroundColor ?? FnColors.fillNormal,
        valueColor:
            AlwaysStoppedAnimation(color ?? FnColors.primaryNormal),
      ),
    );
  }
}
