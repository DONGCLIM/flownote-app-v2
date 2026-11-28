import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// 시안 DS(`WantedDesignSystem`) 컨트롤 3종 1:1 포팅.
///
/// - `Button`   components/buttons/Button.jsx
/// - `Chip`     components/chips/Chip.jsx
/// - `SearchBar` components/inputs/SearchBar.jsx
///
/// 색상 토큰 매핑: 시안은 `--blue-50` 을 `#EE7686`(rose) 로 재정의하므로
/// 여기서도 `FnColors.rose50` 계열을 사용한다.

// ─────────────────────────────────────────────────────────────
// Button
// ─────────────────────────────────────────────────────────────

/// ```js
/// const SIZES = {
///   large:  { height:48, radius:12, padX:28, font:16, gap:6, iconBox:48 },
///   medium: { height:40, radius:10, padX:20, font:15, gap:6, iconBox:40 },
///   small:  { height:32, radius:8,  padX:14, font:14, gap:4, iconBox:32 },
/// };
/// ```
enum FnDsButtonSize { large, medium, small }

/// `variant`: solid | outlined | text
enum FnDsButtonVariant { solid, outlined, text }

/// `color`: primary | neutral
enum FnDsButtonColor { primary, neutral }

class FnDsButton extends StatelessWidget {
  const FnDsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FnDsButtonVariant.solid,
    this.color = FnDsButtonColor.primary,
    this.size = FnDsButtonSize.large,
    this.disabled = false,
    this.expand = false,
    this.leadingIcon,
    this.trailingIcon,
    // `style` 오버라이드 (시안에서 style prop 으로 덮어쓰는 경우)
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final FnDsButtonVariant variant;
  final FnDsButtonColor color;
  final FnDsButtonSize size;
  final bool disabled;
  final bool expand;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final Color? background;
  final Color? foreground;

  double get _h => switch (size) {
        FnDsButtonSize.large => 48,
        FnDsButtonSize.medium => 40,
        FnDsButtonSize.small => 32,
      };
  double get _r => switch (size) {
        FnDsButtonSize.large => 12,
        FnDsButtonSize.medium => 10,
        FnDsButtonSize.small => 8,
      };
  double get _padX => switch (size) {
        FnDsButtonSize.large => 28,
        FnDsButtonSize.medium => 20,
        FnDsButtonSize.small => 14,
      };
  double get _font => switch (size) {
        FnDsButtonSize.large => 16,
        FnDsButtonSize.medium => 15,
        FnDsButtonSize.small => 14,
      };
  double get _gap => size == FnDsButtonSize.small ? 4 : 6;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    Color fg = FnColors.labelNormal;
    Border? border;

    switch (variant) {
      case FnDsButtonVariant.solid:
        if (color == FnDsButtonColor.primary) {
          bg = FnColors.rose50;
          fg = Colors.white;
        } else {
          bg = FnColors.fillNormal;
          fg = FnColors.labelNormal;
        }
      case FnDsButtonVariant.outlined:
        bg = Colors.transparent;
        border = Border.all(color: FnColors.lineNormal, width: 1);
        fg = color == FnDsButtonColor.primary
            ? FnColors.rose50
            : FnColors.labelNormal;
      case FnDsButtonVariant.text:
        bg = Colors.transparent;
        fg = color == FnDsButtonColor.primary
            ? FnColors.rose50
            : FnColors.labelAlternative;
    }

    bg = background ?? bg;
    fg = foreground ?? fg;

    final body = Container(
      height: _h,
      padding: EdgeInsets.symmetric(horizontal: _padX),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_r),
        border: border,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leadingIcon != null) ...[
            SizedBox(width: 20, height: 20, child: leadingIcon),
            SizedBox(width: _gap),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: _font,
                fontWeight: FontWeight.w600,
                height: 1.5,
                letterSpacing: _font * 0.006,
                color: fg,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            SizedBox(width: _gap),
            SizedBox(width: 20, height: 20, child: trailingIcon),
          ],
        ],
      ),
    );

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(_r),
          child: body,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Chip
// ─────────────────────────────────────────────────────────────

/// ```js
/// const SIZES = {
///   xsmall: { h:28, r:8,  padX:8,  font:12 },
///   small:  { h:32, r:8,  padX:10, font:13 },
///   medium: { h:36, r:10, padX:11, font:14 },
///   large:  { h:44, r:12, padX:14, font:15 },
/// };
/// bg  = fill-alternative        (outlined → transparent + inset 1px line-normal-normal)
/// active → bg blue-95 / fg blue-50 / inset 1px blue-50
/// fontWeight 500, gap 4
/// ```
enum FnDsChipSize { xsmall, small, medium, large }

class FnDsChip extends StatelessWidget {
  const FnDsChip({
    super.key,
    required this.label,
    this.onTap,
    this.size = FnDsChipSize.medium,
    this.active = false,
    this.outlined = false,
    this.disabled = false,
    this.fontWeight = FontWeight.w500,
    this.leading,
    this.trailing,
  });

  final String label;
  final VoidCallback? onTap;
  final FnDsChipSize size;
  final bool active;
  final bool outlined;
  final bool disabled;
  final FontWeight fontWeight;
  final Widget? leading;
  final Widget? trailing;

  double get _h => switch (size) {
        FnDsChipSize.xsmall => 28,
        FnDsChipSize.small => 32,
        FnDsChipSize.medium => 36,
        FnDsChipSize.large => 44,
      };
  double get _r => switch (size) {
        FnDsChipSize.xsmall => 8,
        FnDsChipSize.small => 8,
        FnDsChipSize.medium => 10,
        FnDsChipSize.large => 12,
      };
  double get _padX => switch (size) {
        FnDsChipSize.xsmall => 8,
        FnDsChipSize.small => 10,
        FnDsChipSize.medium => 11,
        FnDsChipSize.large => 14,
      };
  double get _font => switch (size) {
        FnDsChipSize.xsmall => 12,
        FnDsChipSize.small => 13,
        FnDsChipSize.medium => 14,
        FnDsChipSize.large => 15,
      };

  @override
  Widget build(BuildContext context) {
    Color bg = FnColors.fillAlternative;
    Color fg = FnColors.labelNormal;
    Border? border;

    if (outlined) {
      bg = Colors.transparent;
      border = Border.all(color: FnColors.lineNormal, width: 1);
    }
    if (active) {
      bg = FnColors.rose95;
      fg = FnColors.rose50;
      border = Border.all(color: FnColors.rose50, width: 1);
    }

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(_r),
          child: Container(
            height: _h,
            padding: EdgeInsets.symmetric(horizontal: _padX),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(_r),
              border: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  SizedBox(width: 16, height: 16, child: leading),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: _font,
                    fontWeight: fontWeight,
                    color: fg,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  SizedBox(width: 16, height: 16, child: trailing),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SearchBar
// ─────────────────────────────────────────────────────────────

/// ```js
/// span: flex, gap 8, height 44, padding '0 14px', radius 12,
///       background var(--fill-normal)
///   svg 18x18 (circle r7 + M20 20l-3.5-3.5) color label-alternative
///   input flex:1 fontSize 15 color label-normal
///   value && button 18x18 원형 fill-strong + X 아이콘 10x10
/// ```
class FnSearchBar extends StatelessWidget {
  const FnSearchBar({
    super.key,
    required this.controller,
    this.placeholder = '검색',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: FnColors.fillNormal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 18, color: FnColors.labelAlternative),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                color: FnColors.labelNormal,
              ),
              cursorColor: FnColors.rose50,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  color: FnColors.labelAssistive,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClear,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: FnColors.fillStrong,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded,
                    size: 11, color: FnColors.labelAlternative),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Dropdown (시안의 `position:absolute top:110%` 팝오버)
// ─────────────────────────────────────────────────────────────

class FnDropdownItem {
  const FnDropdownItem({
    required this.label,
    required this.active,
    this.onTap,
    this.divider = false,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// 항목 위에 1px 구분선 (시안: years 목록 뒤 divider)
  final bool divider;
}

/// ```js
/// div { position:absolute, top:'110%', left:0, zIndex:20,
///       minWidth, maxHeight, overflowY:auto, column, gap:2, padding:6,
///       borderRadius:10, background: background-normal-normal,
///       boxShadow:'0 4px 16px rgba(0,0,0,.12)' }
///   item: padding '8px 10px', radius 8, fontSize 14,
///         active → 700 / blue-50 / blue-95, else 400 / label-normal / transparent
/// ```
class FnDropdown extends StatelessWidget {
  const FnDropdown({
    super.key,
    required this.items,
    this.minWidth = 140,
    this.maxHeight,
  });

  final List<FnDropdownItem> items;
  final double minWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final list = <Widget>[];
    for (final it in items) {
      if (it.divider) {
        list.add(Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: FnColors.lineNeutral,
        ));
      }
      list.add(Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: it.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: it.active ? FnColors.rose95 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              it.label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: it.active ? FontWeight.w700 : FontWeight.w400,
                color: it.active ? FnColors.rose50 : FnColors.labelNormal,
              ),
            ),
          ),
        ),
      ));
      if (it != items.last) list.add(const SizedBox(height: 2));
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: FnColors.backgroundNormal,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: list,
          ),
        ),
      ),
    );
  }
}

/// 시안의 `Pro 전용` 모달 — `Card 320 center` + `구독 안내 보기` / `닫기`
Future<void> showFnProModal(
  BuildContext context, {
  required String title,
  required String desc,
  VoidCallback? onSubscribe,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FnColors.backgroundNormal,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  height: 1.6,
                  color: FnColors.labelAlternative,
                ),
              ),
              const SizedBox(height: 12),
              FnDsButton(
                label: '구독 안내 보기',
                expand: true,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onSubscribe?.call();
                },
              ),
              const SizedBox(height: 12),
              FnDsButton(
                label: '닫기',
                expand: true,
                variant: FnDsButtonVariant.text,
                color: FnDsButtonColor.neutral,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// BottomSheet
// ─────────────────────────────────────────────────────────────

/// ```js
/// function BottomSheet({ title, children, footer })
///   div { background: background-elevated-normal,
///         borderRadius: '20px 20px 0 0',
///         boxShadow: var(--shadow-heavy),
///         padding: '8px 20px 20px', column }
///     span 36x4 r2 fill-strong  alignSelf center  margin '6px 0 14px'
///     title → wds-heading2  marginBottom 12  color label-strong
///     div flex:1  children
///     footer → marginTop 16
/// ```
class FnDsBottomSheet extends StatelessWidget {
  const FnDsBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.footer,
  });

  final String? title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: 8,
        left: 20,
        right: 20,
        bottom: 20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: FnColors.backgroundElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 6, bottom: 14),
              decoration: BoxDecoration(
                color: FnColors.fillStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: FnColors.labelStrong,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
          if (footer != null) ...[
            const SizedBox(height: 16),
            footer!,
          ],
        ],
      ),
    );
  }
}

Future<T?> showFnDsBottomSheet<T>(
  BuildContext context, {
  String? title,
  required Widget child,
  Widget? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000), // rgba(0,0,0,.35)
    isScrollControlled: true,
    builder: (_) => FnDsBottomSheet(title: title, footer: footer, child: child),
  );
}

// ─────────────────────────────────────────────────────────────
// TextField — 시안 `d2354c3d.js` @1918
//   label span 14/600 label-normal, gap 6
//   box   h48 pad'0 16' r12 bg background-normal-normal
//         boxShadow inset 0 0 0 {focused?1.5:1}px {focused?blue-50:line}
//   input 16 label-normal
//   helper 13 (negative→red-50 / positive→green-50 / else label-alternative)
// ─────────────────────────────────────────────────────────────
enum FnDsFieldStatus { normal, negative, positive }

class FnDsTextField extends StatefulWidget {
  const FnDsTextField({
    super.key,
    this.label,
    this.controller,
    this.placeholder,
    this.helper,
    this.status = FnDsFieldStatus.normal,
    this.disabled = false,
    this.trailing,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
  });

  final String? label;
  final TextEditingController? controller;
  final String? placeholder;
  final String? helper;
  final FnDsFieldStatus status;
  final bool disabled;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  State<FnDsTextField> createState() => _FnDsTextFieldState();
}

class _FnDsTextFieldState extends State<FnDsTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Color get _line {
    if (_focus.hasFocus && widget.status == FnDsFieldStatus.normal) {
      return FnColors.rose50;
    }
    switch (widget.status) {
      case FnDsFieldStatus.negative:
        return FnColors.statusNegative;
      case FnDsFieldStatus.positive:
        return FnColors.statusPositive;
      case FnDsFieldStatus.normal:
        return FnColors.lineNormal;
    }
  }

  Color get _helperColor {
    switch (widget.status) {
      case FnDsFieldStatus.negative:
        return FnColors.statusNegative;
      case FnDsFieldStatus.positive:
        return FnColors.statusPositive;
      case FnDsFieldStatus.normal:
        return FnColors.labelAlternative;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ring =
        _focus.hasFocus && widget.status == FnDsFieldStatus.normal ? 1.5 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FnColors.labelNormal,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.disabled
                ? FnColors.fillAlternative
                : FnColors.backgroundNormal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line, width: ring),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: !widget.disabled,
                  onChanged: widget.onChanged,
                  keyboardType: widget.keyboardType,
                  obscureText: widget.obscureText,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    color: FnColors.labelNormal,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.placeholder,
                    hintStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      color: FnColors.labelAssistive,
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helper!,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: _helperColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Circular — 시안 @1332
/// `stroke = max(2, round(size*0.11))`, track fill-normal, arc dasharray 42/100
class FnCircular extends StatelessWidget {
  const FnCircular({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final stroke = (size * 0.11).round().clamp(2, 99).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: stroke,
        strokeCap: StrokeCap.round,
        // dasharray 42/100 ≈ 원주의 42%
        value: null,
        backgroundColor: FnColors.fillNormal,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? FnColors.rose50),
      ),
    );
  }
}

/// ProgressBar — 시안 @1597
/// `h6 r3 bg fill-normal`, 채움 blue-50
class FnProgressBar extends StatelessWidget {
  const FnProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
  });

  /// 0~100
  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pct = value.clamp(0, 100) / 100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: FnColors.fillNormal,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: pct.toDouble(),
          child: Container(color: color ?? FnColors.rose50),
        ),
      ),
    );
  }
}
