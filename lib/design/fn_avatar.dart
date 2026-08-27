import 'package:flutter/material.dart';
import 'fn_tokens.dart';

/// Wanted DS — Avatar
///
/// 이미지가 없으면 이름 이니셜을 표시. 이름 해시로 배경색을 결정한다.
class FnAvatar extends StatelessWidget {
  const FnAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 40,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.badge,
    this.onTap,
    this.squircle = false,
  });

  final String? name;
  final String? imageUrl;
  final double size;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool squircle;

  static const List<Color> _palette = [
    FnColors.rose50,
    FnColors.leaf50,
    FnColors.statusCautionary,
    FnColors.roseTint,
    FnColors.sage,
    FnColors.rose40,
  ];

  static Color colorFor(String seed) {
    if (seed.isEmpty) return FnColors.neutral80;
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '';
    // 한글은 첫 글자, 영문은 최대 두 단어의 첫 글자
    final isKo = RegExp(r'[가-힣]').hasMatch(n);
    if (isKo) return n.characters.first;
    final parts = n.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? colorFor(name ?? '');
    final fg = foregroundColor ?? Colors.white;
    final br = squircle
        ? BorderRadius.circular(size * 0.3)
        : BorderRadius.circular(size / 2);

    Widget inner;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      inner = ClipRRect(
        borderRadius: br,
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(bg, fg, br),
        ),
      );
    } else {
      inner = _fallback(bg, fg, br);
    }

    if (badge != null) {
      inner = Stack(
        clipBehavior: Clip.none,
        children: [
          inner,
          Positioned(right: -2, bottom: -2, child: badge!),
        ],
      );
    }

    if (onTap != null) {
      inner = InkWell(borderRadius: br, onTap: onTap, child: inner);
    }
    return inner;
  }

  Widget _fallback(Color bg, Color fg, BorderRadius br) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: br),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: fg)
          : Text(
              _initials,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
                color: fg,
                height: 1,
              ),
            ),
    );
  }
}

/// Wanted DS — AvatarGroup (겹쳐 보이는 아바타 목록)
class FnAvatarGroup extends StatelessWidget {
  const FnAvatarGroup({
    super.key,
    required this.names,
    this.size = 32,
    this.max = 4,
    this.overlap = 0.32,
  });

  final List<String> names;
  final double size;
  final int max;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final rest = names.length - shown.length;
    final step = size * (1 - overlap);
    final width = shown.isEmpty
        ? 0.0
        : step * (shown.length + (rest > 0 ? 1 : 0) - 1) + size;

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(1.5),
                child: FnAvatar(name: shown[i], size: size - 3),
              ),
            ),
          if (rest > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: FnColors.neutral97,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text('+$rest',
                    style: FnType.caption2.copyWith(
                        color: FnColors.labelNeutral,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wanted DS — Chip / Category
class FnChip extends StatelessWidget {
  const FnChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.trailing,
    this.color,
    this.onDelete,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;
  final Color? color;
  final VoidCallback? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? FnColors.primaryNormal;
    final bg = selected ? accent : FnColors.backgroundElevated;
    final fg = selected ? Colors.white : FnColors.labelNeutral;
    final border = selected ? accent : FnColors.lineNeutral;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: FnRadius.brFull,
        child: AnimatedContainer(
          duration: FnDuration.fast,
          height: compact ? 30 : 36,
          padding: EdgeInsets.symmetric(
              horizontal: compact ? FnSpace.x10 : FnSpace.x14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: FnRadius.brFull,
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 13 : 15, color: fg),
                const SizedBox(width: FnSpace.x4),
              ],
              Text(
                label,
                style: (compact ? FnType.caption1 : FnType.label1).copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: FnSpace.x4),
                trailing!,
              ],
              if (onDelete != null) ...[
                const SizedBox(width: FnSpace.x4),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.close_rounded, size: 14, color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 가로 스크롤 칩 목록.
class FnChipBar extends StatelessWidget {
  const FnChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding =
        const EdgeInsets.symmetric(horizontal: FnSpace.x20),
    this.color,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: FnSpace.x8),
        itemBuilder: (context, i) => FnChip(
          label: labels[i],
          selected: i == selectedIndex,
          color: color,
          onTap: () => onSelected(i),
        ),
      ),
    );
  }
}

/// Wanted DS — ToggleIcon (좋아요/북마크 등 상태 토글 아이콘)
class FnToggleIcon extends StatelessWidget {
  const FnToggleIcon({
    super.key,
    required this.value,
    required this.onChanged,
    required this.iconOn,
    required this.iconOff,
    this.colorOn,
    this.colorOff,
    this.size = 24,
    this.tapSize = 40,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData iconOn;
  final IconData iconOff;
  final Color? colorOn;
  final Color? colorOff;
  final double size;
  final double tapSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tapSize,
      height: tapSize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Center(
            child: AnimatedSwitcher(
              duration: FnDuration.fast,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                value ? iconOn : iconOff,
                key: ValueKey(value),
                size: size,
                color: value
                    ? (colorOn ?? FnColors.primaryNormal)
                    : (colorOff ?? FnColors.labelAssistive),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 자주 쓰는 토글 프리셋.
class FnBookmarkToggle extends StatelessWidget {
  const FnBookmarkToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 22,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => FnToggleIcon(
        value: value,
        onChanged: onChanged,
        iconOn: Icons.bookmark_rounded,
        iconOff: Icons.bookmark_border_rounded,
        size: size,
      );
}
