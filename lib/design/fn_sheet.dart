import 'package:flutter/material.dart';
import 'fn_tokens.dart';
import 'fn_button.dart';

/// Wanted DS — BottomSheet
///
/// 원본 스펙: radius top 20 / handle 40x4 / dim 40% / max-height 90%
class FnBottomSheet extends StatelessWidget {
  const FnBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.showHandle = true,
    this.showClose = false,
    this.padding = const EdgeInsets.fromLTRB(
        FnSpace.x20, 0, FnSpace.x20, FnSpace.x20),
    this.footer,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final bool showHandle;
  final bool showClose;
  final EdgeInsetsGeometry padding;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.9;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: FnColors.backgroundElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(FnRadius.r20),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle)
                Padding(
                  padding: const EdgeInsets.only(
                      top: FnSpace.x8, bottom: FnSpace.x4),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FnColors.lineNormal,
                      borderRadius: FnRadius.brFull,
                    ),
                  ),
                ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      FnSpace.x20, FnSpace.x12, FnSpace.x8, FnSpace.x4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title!, style: FnType.heading2),
                            if (subtitle != null) ...[
                              const SizedBox(height: FnSpace.x4),
                              Text(subtitle!,
                                  style: FnType.body2.copyWith(
                                      color: FnColors.labelAlternative)),
                            ],
                          ],
                        ),
                      ),
                      if (showClose)
                        FnIconButton(
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(context),
                          size: 36,
                          iconSize: 20,
                        ),
                    ],
                  ),
                )
              else
                const SizedBox(height: FnSpace.x12),
              Flexible(
                child: SingleChildScrollView(
                  padding: padding,
                  child: child,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      FnSpace.x20, 0, FnSpace.x20, FnSpace.x12),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 바텀시트 표시 헬퍼.
Future<T?> showFnSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
  String? subtitle,
  bool showClose = true,
  bool isDismissible = true,
  Widget? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => FnBottomSheet(
      title: title,
      subtitle: subtitle,
      showClose: showClose,
      footer: footer,
      child: child,
    ),
  );
}

/// 선택 목록용 바텀시트 아이템.
class FnSheetOption<T> {
  const FnSheetOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.color,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;
  final Color? color;
  final bool destructive;
}

/// 옵션 선택 바텀시트.
Future<T?> showFnOptionSheet<T>(
  BuildContext context, {
  required List<FnSheetOption<T>> options,
  String? title,
  String? subtitle,
  T? selected,
}) {
  return showFnSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    showClose: title != null,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in options)
          _SheetOptionTile<T>(option: o, isSelected: o.value == selected),
      ],
    ),
  );
}

class _SheetOptionTile<T> extends StatelessWidget {
  const _SheetOptionTile({required this.option, required this.isSelected});

  final FnSheetOption<T> option;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final fg = option.destructive
        ? FnColors.statusNegative
        : (option.color ?? FnColors.labelNormal);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, option.value),
        borderRadius: FnRadius.br12,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: FnSpace.x4, vertical: FnSpace.x12),
          child: Row(
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 20, color: fg),
                const SizedBox(width: FnSpace.x12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label,
                        style: FnType.body1.copyWith(
                          color: fg,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        )),
                    if (option.description != null) ...[
                      const SizedBox(height: 2),
                      Text(option.description!,
                          style: FnType.caption1
                              .copyWith(color: FnColors.labelAlternative)),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_rounded,
                    size: 20, color: FnColors.primaryNormal),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wanted DS — Alert (Dialog)
///
/// 원본 스펙: width 320 / radius 20 / padding 24 / title heading2 + body body2
class FnAlert extends StatelessWidget {
  const FnAlert({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel = '확인',
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
    this.destructive = false,
    this.icon,
    this.iconColor,
    this.content,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String? cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool destructive;
  final IconData? icon;
  final Color? iconColor;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FnColors.backgroundElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: FnSpace.x32),
      shape: RoundedRectangleBorder(borderRadius: FnRadius.br20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(FnSpace.x24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: (iconColor ?? FnColors.primaryNormal)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        size: 28,
                        color: iconColor ?? FnColors.primaryNormal),
                  ),
                ),
                const SizedBox(height: FnSpace.x16),
              ],
              Text(title,
                  textAlign: TextAlign.center, style: FnType.heading2),
              if (message != null) ...[
                const SizedBox(height: FnSpace.x8),
                Text(message!,
                    textAlign: TextAlign.center,
                    style: FnType.body2
                        .copyWith(color: FnColors.labelAlternative)),
              ],
              if (content != null) ...[
                const SizedBox(height: FnSpace.x16),
                content!,
              ],
              const SizedBox(height: FnSpace.x24),
              if (cancelLabel != null)
                Row(
                  children: [
                    Expanded(
                      child: FnButton(
                        label: cancelLabel!,
                        variant: FnButtonVariant.solid,
                        color: FnButtonColor.assistive,
                        expand: true,
                        onPressed: () {
                          Navigator.pop(context, false);
                          onCancel?.call();
                        },
                      ),
                    ),
                    const SizedBox(width: FnSpace.x8),
                    Expanded(
                      child: FnButton(
                        label: confirmLabel,
                        expand: true,
                        onPressed: () {
                          Navigator.pop(context, true);
                          onConfirm?.call();
                        },
                      ),
                    ),
                  ],
                )
              else
                FnButton(
                  label: confirmLabel,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(context, true);
                    onConfirm?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 확인 다이얼로그 헬퍼. true = 확인, false/null = 취소
Future<bool> showFnAlert(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '확인',
  String? cancelLabel,
  bool destructive = false,
  IconData? icon,
  Color? iconColor,
  Widget? content,
  bool barrierDismissible = true,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => FnAlert(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
      iconColor: iconColor,
      content: content,
    ),
  );
  return r ?? false;
}
