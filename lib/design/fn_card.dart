import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// Wanted DS — Card
///
/// 원본 스펙: radius 20 / padding 16 / shadow-normal
/// `bordered: true` 이면 그림자 대신 1px 내부 테두리.
class FnCard extends StatelessWidget {
  const FnCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FnSpace.x16),
    this.margin,
    this.bordered = false,
    this.onTap,
    this.color,
    this.radius = 20,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool bordered;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? FnColors.backgroundElevated,
        borderRadius: br,
        border: bordered
            ? Border.all(color: borderColor ?? FnColors.lineNeutral, width: 1)
            : null,
        boxShadow: bordered ? null : FnShadow.normal,
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: content,
        ),
      );
    }

    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

/// 강조 카드 — 선택된 플랜, 활성 항목 등
class FnHighlightCard extends StatelessWidget {
  const FnHighlightCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FnSpace.x16),
    this.margin,
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? FnColors.primaryNormal;
    return FnCard(
      padding: padding,
      margin: margin,
      onTap: onTap,
      bordered: true,
      borderColor: a,
      child: child,
    );
  }
}

/// 안내 배너 — 아이콘 + 제목 + 본문
///
/// 프로토타입의 "매달 반복되는 거래처 정산, 클릭 한 번으로!" 스타일.
class FnInfoBanner extends StatelessWidget {
  const FnInfoBanner({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.info_outline_rounded,
    this.tone = FnBannerTone.accent,
    this.margin,
    this.trailing,
  });

  final String title;
  final String? body;
  final IconData icon;
  final FnBannerTone tone;
  final EdgeInsetsGeometry? margin;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    late final Color bg, fg;
    switch (tone) {
      case FnBannerTone.accent:
        bg = FnColors.rose95;
        fg = FnColors.rose30;
        break;
      case FnBannerTone.positive:
        bg = FnColors.statusPositiveBg;
        fg = FnColors.statusPositiveStrong;
        break;
      case FnBannerTone.cautionary:
        bg = FnColors.statusCautionaryBg;
        fg = FnColors.statusCautionaryStrong;
        break;
      case FnBannerTone.neutral:
        bg = FnColors.backgroundAlternative;
        fg = FnColors.labelAlternative;
        break;
    }

    final content = Container(
      padding: const EdgeInsets.all(FnSpace.x16),
      decoration: BoxDecoration(color: bg, borderRadius: FnRadius.br16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: FnSpace.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FnType.label1.copyWith(color: fg),
                ),
                if (body != null) ...[
                  const SizedBox(height: FnSpace.x4),
                  Text(
                    body!,
                    style: FnType.caption1.copyWith(
                      color: FnColors.labelAlternative,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

enum FnBannerTone { accent, positive, cautionary, neutral }

/// 섹션 제목 — 카드 그룹 위에 붙는 헤더
class FnSectionHeader extends StatelessWidget {
  const FnSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
        FnSpace.x20, FnSpace.x24, FnSpace.x20, FnSpace.x10),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: FnType.headline2.copyWith(color: FnColors.labelNormal),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                children: [
                  Text(
                    action!,
                    style: FnType.label2
                        .copyWith(color: FnColors.labelAlternative),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: FnColors.labelAssistive),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
