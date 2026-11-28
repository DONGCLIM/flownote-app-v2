import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// Wanted DS — ListCell
///
/// 프로필 메뉴, 설정 목록 등에 쓰는 한 줄 항목.
class FnListCell extends StatelessWidget {
  const FnListCell({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.height,
    this.padding = const EdgeInsets.symmetric(
        horizontal: FnSpace.x20, vertical: FnSpace.x16),
    this.titleColor,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Color? titleColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: padding,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: FnSpace.x12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: (dense ? FnType.body2 : FnType.body1).copyWith(
                        color: titleColor ?? FnColors.labelNormal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: FnSpace.x8),
                trailing!,
              ],
              if (showChevron && onTap != null) ...[
                const SizedBox(width: FnSpace.x4),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: FnColors.labelAssistive),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 라벨 + 값 한 줄 — 정산서 합계, 상세 정보 등
class FnKeyValueRow extends StatelessWidget {
  const FnKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
    this.padding = const EdgeInsets.symmetric(vertical: FnSpace.x8),
    this.labelWidget,
    this.valueWidget,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;
  final EdgeInsetsGeometry padding;
  final Widget? labelWidget;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final ls = emphasize
        ? FnType.headline2.copyWith(color: FnColors.labelNormal)
        : FnType.body2.copyWith(color: FnColors.labelAlternative);
    final vs = emphasize
        ? FnType.headline2.copyWith(
            color: valueColor ?? FnColors.labelNormal,
            fontWeight: FontWeight.w700)
        : FnType.body2.copyWith(
            color: valueColor ?? FnColors.labelNormal,
            fontWeight: FontWeight.w500);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          labelWidget ?? Text(label, style: ls),
          const Spacer(),
          valueWidget ?? Text(value, style: vs),
        ],
      ),
    );
  }
}

/// 구분선
class FnDivider extends StatelessWidget {
  const FnDivider({
    super.key,
    this.height = 1,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    this.thick = false,
  });

  /// 섹션 사이 두꺼운 구분 (8px 회색 띠)
  const FnDivider.section({super.key})
      : height = 8,
        indent = 0,
        endIndent = 0,
        color = null,
        thick = true;

  final double height;
  final double indent;
  final double endIndent;
  final Color? color;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    if (thick) {
      return Container(height: height, color: FnColors.backgroundAlternative);
    }
    return Padding(
      padding: EdgeInsets.only(left: indent, right: endIndent),
      child: Container(height: height, color: color ?? FnColors.lineAlternative),
    );
  }
}

/// 체크박스 — 원본 accent-color #EE7686
class FnCheckbox extends StatelessWidget {
  const FnCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 22,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: FnDuration.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? FnColors.primaryNormal : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value ? FnColors.primaryNormal : FnColors.lineStrong,
            width: 1.5,
          ),
        ),
        child: value
            ? Icon(Icons.check_rounded, size: size * 0.7, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 라디오 버튼
class FnRadio<T> extends StatelessWidget {
  const FnRadio({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.size = 22,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T>? onChanged;
  final double size;

  bool get _selected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: FnDuration.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _selected ? FnColors.primaryNormal : Colors.transparent,
          border: Border.all(
            color: _selected ? FnColors.primaryNormal : FnColors.lineStrong,
            width: 1.5,
          ),
        ),
        child: _selected
            ? Icon(Icons.check_rounded, size: size * 0.65, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 스위치
class FnSwitch extends StatelessWidget {
  const FnSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: FnColors.primaryNormal,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: FnColors.neutral90,
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    );
  }
}

/// 체크 목록 항목 — 구독 혜택 리스트 등
class FnCheckItem extends StatelessWidget {
  const FnCheckItem({
    super.key,
    required this.text,
    this.color,
    this.icon = Icons.check_rounded,
    this.fontSize = 13.5,
  });

  final String text;
  final Color? color;
  final IconData icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = color ?? FnColors.primaryNormal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FnSpace.x6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 11, color: c),
          ),
          const SizedBox(width: FnSpace.x8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: fontSize,
                height: 1.45,
                color: FnColors.labelNeutral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
