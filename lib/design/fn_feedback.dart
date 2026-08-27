import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// Wanted DS — Skeleton
///
/// 로딩 자리표시자. shimmer 애니메이션 내장(외부 패키지 불필요).
class FnSkeleton extends StatefulWidget {
  const FnSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = FnRadius.r8,
    this.circle = false,
  });

  /// 텍스트 한 줄 형태
  const FnSkeleton.text({super.key, this.width, this.height = 14})
      : radius = FnRadius.r4,
        circle = false;

  /// 원형(아바타)
  const FnSkeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        circle = true;

  /// 카드 블록
  const FnSkeleton.box({super.key, this.width, this.height = 80})
      : radius = FnRadius.r16,
        circle = false;

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<FnSkeleton> createState() => _FnSkeletonState();
}

class _FnSkeletonState extends State<FnSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius:
                widget.circle ? null : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t) + 1, 0),
              colors: const [
                FnColors.neutral98,
                FnColors.neutral95,
                FnColors.neutral98,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 리스트 로딩용 스켈레톤 묶음.
class FnSkeletonList extends StatelessWidget {
  const FnSkeletonList({super.key, this.count = 3, this.itemHeight = 76});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: FnSpace.x10),
          child: Container(
            padding: const EdgeInsets.all(FnSpace.x16),
            decoration: BoxDecoration(
              color: FnColors.backgroundElevated,
              borderRadius: FnRadius.br16,
            ),
            child: Row(
              children: [
                const FnSkeleton.circle(size: 40),
                const SizedBox(width: FnSpace.x12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      FnSkeleton.text(width: 120),
                      SizedBox(height: FnSpace.x8),
                      FnSkeleton.text(width: 80, height: 12),
                    ],
                  ),
                ),
                const FnSkeleton(width: 60, height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wanted DS — Circular (스피너)
class FnSpinner extends StatelessWidget {
  const FnSpinner({super.key, this.size = 24, this.color, this.stroke = 2.5});

  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: stroke,
        strokeCap: StrokeCap.round,
        valueColor:
            AlwaysStoppedAnimation(color ?? FnColors.primaryNormal),
        backgroundColor: FnColors.fillNormal,
      ),
    );
  }
}

/// 진행률 원형 인디케이터 (퍼센트 표시 포함).
class FnCircularProgress extends StatelessWidget {
  const FnCircularProgress({
    super.key,
    required this.value,
    this.size = 72,
    this.stroke = 8,
    this.color,
    this.label,
  });

  final double value; // 0.0 ~ 1.0
  final double size;
  final double stroke;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? FnColors.primaryNormal;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              value: value.clamp(0.0, 1.0),
              color: c,
              stroke: stroke,
            ),
          ),
          Text(
            label ?? '${(value * 100).round()}%',
            style: FnType.label1.copyWith(
              color: FnColors.labelNormal,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.22,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.stroke,
  });

  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    final bg = Paint()
      ..color = FnColors.neutral97
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);

    final fg = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

/// Wanted DS — Tooltip (탭하면 뜨는 말풍선)
class FnTooltip extends StatelessWidget {
  const FnTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      padding: const EdgeInsets.symmetric(
          horizontal: FnSpace.x12, vertical: FnSpace.x8),
      margin: const EdgeInsets.symmetric(horizontal: FnSpace.x20),
      decoration: BoxDecoration(
        color: FnColors.neutral20,
        borderRadius: FnRadius.br8,
      ),
      textStyle: FnType.caption1.copyWith(color: Colors.white),
      child: child,
    );
  }
}

/// 정보 아이콘 + 툴팁 조합.
class FnInfoTip extends StatelessWidget {
  const FnInfoTip({super.key, required this.message, this.size = 16});

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FnTooltip(
      message: message,
      child: Icon(Icons.info_outline_rounded,
          size: size, color: FnColors.labelAssistive),
    );
  }
}

/// Wanted DS — Toast (스낵바)
enum FnToastType { normal, success, warning, error }

void showFnToast(
  BuildContext context,
  String message, {
  FnToastType type = FnToastType.normal,
  Duration duration = const Duration(seconds: 2),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final (bg, icon) = switch (type) {
    FnToastType.success => (FnColors.statusPositive, Icons.check_circle_rounded),
    FnToastType.warning => (FnColors.statusCautionary, Icons.warning_rounded),
    FnToastType.error => (FnColors.statusNegative, Icons.error_rounded),
    FnToastType.normal => (FnColors.neutral20, null),
  };

  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: FnSpace.x8),
          ],
          Expanded(
            child: Text(message,
                style: FnType.body2.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      duration: duration,
      margin: const EdgeInsets.all(FnSpace.x16),
      shape: RoundedRectangleBorder(borderRadius: FnRadius.br12),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: Colors.white,
              onPressed: onAction ?? () {},
            ),
    ),
  );
}

/// 화면 전체 로딩 오버레이.
class FnLoadingOverlay extends StatelessWidget {
  const FnLoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(FnSpace.x24),
          decoration: BoxDecoration(
            color: FnColors.backgroundElevated,
            borderRadius: FnRadius.br16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FnSpinner(size: 32),
              if (message != null) ...[
                const SizedBox(height: FnSpace.x12),
                Text(message!,
                    style: FnType.body2
                        .copyWith(color: FnColors.labelNeutral)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
