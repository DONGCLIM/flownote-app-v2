import 'package:flutter/material.dart';
import 'fn_tokens.dart';

enum FnBadgeSize { xsmall, small, medium }

enum FnBadgeColor { neutral, accent, positive, negative, cautionary }

class _BadgeSize {
  final double h, r, padX, font;
  const _BadgeSize(this.h, this.r, this.padX, this.font);
}

const _badgeSizes = {
  FnBadgeSize.xsmall: _BadgeSize(20, 6, 6, 11),
  FnBadgeSize.small: _BadgeSize(24, 6, 7, 12),
  FnBadgeSize.medium: _BadgeSize(28, 8, 8, 13),
};

/// Wanted DS — ContentBadge
///
/// 원본 스펙 그대로. 프로토타입에서 FN.Badge 로 색 보정한 값 반영.
class FnBadge extends StatelessWidget {
  const FnBadge({
    super.key,
    required this.label,
    this.size = FnBadgeSize.small,
    this.color = FnBadgeColor.neutral,
    this.outlined = false,
    this.icon,
  });

  /// 면세 (생화)
  const FnBadge.taxExempt({super.key, this.size = FnBadgeSize.xsmall})
      : label = '면세',
        color = FnBadgeColor.positive,
        outlined = false,
        icon = null;

  /// 과세 (부자재)
  const FnBadge.taxable({super.key, this.size = FnBadgeSize.xsmall})
      : label = '과세',
        color = FnBadgeColor.accent,
        outlined = false,
        icon = null;

  /// Pro 잠금 표시
  const FnBadge.pro({super.key, this.size = FnBadgeSize.xsmall})
      : label = 'Pro',
        color = FnBadgeColor.accent,
        outlined = false,
        icon = Icons.lock_rounded;

  final String label;
  final FnBadgeSize size;
  final FnBadgeColor color;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = _badgeSizes[size]!;

    late final Color bg, fg, line;
    switch (color) {
      case FnBadgeColor.neutral:
        bg = FnColors.fillNormal;
        fg = FnColors.labelAlternative;
        line = FnColors.lineNormal;
        break;
      case FnBadgeColor.accent:
        bg = FnColors.rose95;
        fg = FnColors.rose30;
        line = FnColors.rose50;
        break;
      case FnBadgeColor.positive:
        bg = FnColors.statusPositiveBg;
        fg = FnColors.statusPositiveStrong;
        line = FnColors.statusPositive;
        break;
      case FnBadgeColor.negative:
        bg = FnColors.statusNegativeBg;
        fg = FnColors.statusNegativeStrong;
        line = FnColors.statusNegative;
        break;
      case FnBadgeColor.cautionary:
        bg = FnColors.statusCautionaryBg;
        fg = FnColors.statusCautionaryStrong;
        line = FnColors.statusCautionary;
        break;
    }

    return Container(
      height: s.h,
      padding: EdgeInsets.symmetric(horizontal: s.padX),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(s.r),
        border: outlined ? Border.all(color: line, width: 1) : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: s.font, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: s.font,
              fontWeight: FontWeight.w600,
              height: 1.385,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 증감률 표시 — +16% / -5%
///
/// 지출 맥락에서는 증가가 부정(빨강), 감소가 긍정(초록).
class FnDeltaBadge extends StatelessWidget {
  const FnDeltaBadge({
    super.key,
    required this.percent,
    this.size = FnBadgeSize.xsmall,
    this.increaseIsBad = true,
    this.showArrow = false,
  });

  final num percent;
  final FnBadgeSize size;

  /// 지출·비용이면 true(증가=경고), 매출이면 false(증가=긍정)
  final bool increaseIsBad;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final bad = increaseIsBad ? up : !up;
    final sign = up ? '+' : '';
    final txt = '$sign${percent.toStringAsFixed(0)}%';

    return FnBadge(
      label: showArrow ? '${up ? '▲' : '▼'} $txt' : txt,
      size: size,
      color: bad ? FnBadgeColor.cautionary : FnBadgeColor.positive,
    );
  }
}

/// 알림 점 / 개수
class FnPushBadge extends StatelessWidget {
  const FnPushBadge({super.key, this.count, this.size = 10});

  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count == null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: FnColors.statusNegative,
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: FnColors.statusNegative,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count! > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// 필터 칩 — 선택 가능한 토글
class FnFilterChip extends StatelessWidget {
  const FnFilterChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.trailingIcon,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final fg = locked
        ? FnColors.labelAssistive
        : selected
            ? FnColors.rose30
            : FnColors.labelAlternative;
    final bg = selected ? FnColors.rose95 : FnColors.backgroundElevated;
    final bd = selected ? FnColors.rose50 : FnColors.lineNeutral;

    return Material(
      color: bg,
      borderRadius: FnRadius.br8,
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: FnRadius.br8,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: FnSpace.x12),
          decoration: BoxDecoration(
            borderRadius: FnRadius.br8,
            border: Border.all(color: bd, width: 1),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: FnType.label2.copyWith(color: fg),
              ),
              if (locked) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock_rounded, size: 12, color: fg),
              ] else if (trailingIcon != null) ...[
                const SizedBox(width: 2),
                Icon(trailingIcon, size: 14, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
