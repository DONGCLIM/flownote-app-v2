import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// 시안 `DS.ContentBadge` + `window.FN.Badge` 오버라이드를 합친 최종 배지.
///
/// DS 원본:
/// ```js
/// SIZES = { xsmall:{h:20,r:6,padX:6,font:11}, small:{h:24,r:6,padX:7,font:12},
///           medium:{h:28,r:8,padX:8,font:13} }
/// COLORS = { neutral:{bg:fill-normal, fg:label-alternative, line:line-normal-normal},
///            accent:{bg:blue-95, fg:blue-50, line:blue-50},
///            positive:{bg:green-95, fg:green-50, line:green-50},
///            negative:{bg:red-95, fg:red-50, line:red-50},
///            violet:{bg:violet-95, fg:violet-50, line:violet-50} }
/// fontWeight 600, lineHeight 1.385
/// ```
/// FN.Badge 보정:
/// ```js
/// negative    -> color: var(--red-30)         = #C9566A
/// cautionary  -> bg: orange-95 #FCF4E6, color: orange-30 #A9762F,
///                inset 0 0 0 1px orange-50 #E0A45C
/// positive    -> color: var(--green-30)       = #5F8347
/// accent      -> color: var(--fn-rose-30)     = #C9566A
/// ```
enum FnBadgeColor { neutral, accent, positive, negative, cautionary, violet }

enum FnBadgeSize { xsmall, small, medium }

class FnBadge extends StatelessWidget {
  const FnBadge(
    this.text, {
    super.key,
    this.color = FnBadgeColor.neutral,
    this.size = FnBadgeSize.medium,
    this.outlined = false,
    this.leading,
  });

  final String text;
  final FnBadgeColor color;
  final FnBadgeSize size;
  final bool outlined;
  final Widget? leading;

  double get _h => switch (size) {
        FnBadgeSize.xsmall => 20,
        FnBadgeSize.small => 24,
        FnBadgeSize.medium => 28,
      };

  double get _r => size == FnBadgeSize.medium ? 8 : 6;

  double get _padX => switch (size) {
        FnBadgeSize.xsmall => 6,
        FnBadgeSize.small => 7,
        FnBadgeSize.medium => 8,
      };

  double get _font => switch (size) {
        FnBadgeSize.xsmall => 11,
        FnBadgeSize.small => 12,
        FnBadgeSize.medium => 13,
      };

  ({Color bg, Color fg, Color line}) get _c => switch (color) {
        // neutral: fill-normal / label-alternative / line-normal-normal
        FnBadgeColor.neutral => (
            bg: FnColors.fillNormal,
            fg: FnColors.labelAlternative,
            line: FnColors.lineNormal,
          ),
        // accent: blue-95(=rose95) bg, FN.Badge가 fg를 fn-rose-30으로 덮음
        FnBadgeColor.accent => (
            bg: FnColors.rose95,
            fg: FnColors.rose30,
            line: FnColors.rose50,
          ),
        // positive: green-95 bg, FN.Badge가 fg를 green-30으로 덮음
        FnBadgeColor.positive => (
            bg: FnColors.leaf95,
            fg: FnColors.leaf30,
            line: FnColors.leaf50,
          ),
        // negative: red-95 bg, FN.Badge가 fg를 red-30으로 덮음
        FnBadgeColor.negative => (
            bg: FnColors.statusNegativeBg,
            fg: FnColors.statusNegativeStrong,
            line: FnColors.statusNegative,
          ),
        // cautionary: FN.Badge 전용 — orange-95 / orange-30 / 1px orange-50 테두리
        FnBadgeColor.cautionary => (
            bg: FnColors.statusCautionaryBg,
            fg: FnColors.statusCautionaryStrong,
            line: FnColors.statusCautionary,
          ),
        // violet: violet-95 / violet-50
        FnBadgeColor.violet => (
            bg: const Color(0xFFFCEEEB),
            fg: const Color(0xFFF4796E),
            line: const Color(0xFFF4796E),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = _c;
    // cautionary는 solid여도 1px 테두리를 갖는다(FN.Badge boxShadow inset).
    final hasBorder = outlined || color == FnBadgeColor.cautionary;
    return Container(
      height: _h,
      padding: EdgeInsets.symmetric(horizontal: _padX),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : c.bg,
        borderRadius: BorderRadius.circular(_r),
        border: hasBorder ? Border.all(color: c.line, width: 1) : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: _font,
              fontWeight: FontWeight.w600,
              height: 1.385,
              color: c.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 시안 `DS.Divider` 1:1
/// normal: 1px `line-normal-neutral` / thick: 8px `fill-alternative`
class FnDsDivider extends StatelessWidget {
  const FnDsDivider({super.key, this.thick = false, this.vertical = false});
  final bool thick;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final t = thick ? 8.0 : 1.0;
    final c = thick ? FnColors.fillAlternative : FnColors.lineNeutral;
    return vertical
        ? Container(width: t, color: c)
        : Container(height: t, color: c);
  }
}

/// 시안 `DS.ListCell` 1:1
/// padding '14px 16px', gap 12, title 16/500 label-normal,
/// description 14 label-alternative,
/// divider ? inset 0 -1px 0 line-normal-neutral
class FnDsListCell extends StatelessWidget {
  const FnDsListCell({
    super.key,
    this.leading,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.divider = false,
    this.background,
    this.titleWeight = FontWeight.w500,
  });

  final Widget? leading;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final Color? background;

  /// 시안 프로필 화면은 title을 `<span style="fontWeight:600">`으로 감싼다.
  final FontWeight titleWeight;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background ?? FnColors.backgroundNormal,
        border: divider
            ? const Border(bottom: BorderSide(color: FnColors.lineNeutral, width: 1))
            : null,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: titleWeight,
                    color: FnColors.labelNormal,
                  ),
                ),
                if (description != null)
                  Text(
                    description!,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: FnColors.labelAlternative,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
