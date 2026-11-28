import 'package:flutter/material.dart';
import 'fn_tokens.dart';

enum FnButtonVariant { solid, outlined, text }

enum FnButtonColor { primary, assistive }

enum FnButtonSize { large, medium, small }

class _SizeSpec {
  final double height, radius, padX, font, gap;
  const _SizeSpec(this.height, this.radius, this.padX, this.font, this.gap);
}

const _sizes = {
  FnButtonSize.large: _SizeSpec(48, 12, 28, 16, 6),
  FnButtonSize.medium: _SizeSpec(40, 10, 20, 15, 6),
  FnButtonSize.small: _SizeSpec(32, 8, 14, 14, 4),
};

/// Wanted DS — Button
///
/// 원본 스펙(Large): height 48 / radius 12 / padX 28 / 16px w600
class FnButton extends StatelessWidget {
  const FnButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FnButtonVariant.solid,
    this.color = FnButtonColor.primary,
    this.size = FnButtonSize.large,
    this.leadingIcon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
  });

  /// 화면 폭 전체를 채우는 주요 CTA
  const FnButton.cta({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
  })  : variant = FnButtonVariant.solid,
        color = FnButtonColor.primary,
        size = FnButtonSize.large,
        expand = true;

  final String label;
  final VoidCallback? onPressed;
  final FnButtonVariant variant;
  final FnButtonColor color;
  final FnButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool expand;
  final bool loading;

  bool get _disabled => onPressed == null || loading;

  @override
  Widget build(BuildContext context) {
    final s = _sizes[size]!;

    Color bg;
    Color fg;
    BoxBorder? border;

    switch (variant) {
      case FnButtonVariant.solid:
        if (color == FnButtonColor.primary) {
          bg = FnColors.primaryNormal;
          fg = Colors.white;
        } else {
          bg = FnColors.fillNormal;
          fg = FnColors.labelNormal;
        }
        break;
      case FnButtonVariant.outlined:
        bg = Colors.transparent;
        fg = color == FnButtonColor.primary
            ? FnColors.primaryNormal
            : FnColors.labelNormal;
        border = Border.all(
          color: color == FnButtonColor.primary
              ? FnColors.primaryNormal
              : FnColors.lineNormal,
          width: 1,
        );
        break;
      case FnButtonVariant.text:
        bg = Colors.transparent;
        fg = color == FnButtonColor.primary
            ? FnColors.primaryNormal
            : FnColors.labelAlternative;
        break;
    }

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          ),
          SizedBox(width: s.gap),
        ] else if (leadingIcon != null) ...[
          Icon(leadingIcon, color: fg, size: s.font + 4),
          SizedBox(width: s.gap),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: s.font,
              fontWeight: FontWeight.w600,
              height: 1.5,
              letterSpacing: s.font * 0.006,
              color: fg,
            ),
          ),
        ),
        if (trailingIcon != null) ...[
          SizedBox(width: s.gap),
          Icon(trailingIcon, color: fg, size: s.font + 4),
        ],
      ],
    );

    return Opacity(
      opacity: _disabled ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(s.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(s.radius),
          child: Container(
            height: s.height,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: s.padX),
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(s.radius),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Wanted DS — IconButton (정사각 터치 타깃)
class FnIconButton extends StatelessWidget {
  const FnIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.iconSize = 20,
    this.color,
    this.background,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: background ?? Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              color: color ?? FnColors.labelNormal,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Wanted DS — FloatingActionButton
class FnFab extends StatelessWidget {
  const FnFab({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 56,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: FnShadow.strong,
      ),
      child: Material(
        color: FnColors.primaryNormal,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Wanted DS — TextButton (인라인 링크형)
class FnTextButton extends StatelessWidget {
  const FnTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color,
    this.fontSize = 14,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double fontSize;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? FnColors.primaryNormal;
    return InkWell(
      onTap: onPressed,
      borderRadius: FnRadius.br8,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FnSpace.x8,
          vertical: FnSpace.x6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: FnSpace.x4),
              Icon(trailingIcon, color: c, size: fontSize + 2),
            ],
          ],
        ),
      ),
    );
  }
}
