import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fn_tokens.dart';

/// Wanted DS — TextField
class FnTextField extends StatelessWidget {
  const FnTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.prefix,
    this.enabled = true,
    this.maxLines = 1,
    this.errorText,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.onSubmitted,
    this.focusNode,
    this.helperText,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final Widget? prefix;
  final bool enabled;
  final int maxLines;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: FnType.label2.copyWith(color: FnColors.labelNeutral),
          ),
          const SizedBox(height: FnSpace.x8),
        ],
        TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          maxLines: maxLines,
          textAlign: textAlign,
          autofocus: autofocus,
          focusNode: focusNode,
          inputFormatters: inputFormatters,
          style: FnType.body1.copyWith(color: FnColors.labelNormal),
          cursorColor: FnColors.primaryNormal,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: FnType.body1.copyWith(color: FnColors.labelAssistive),
            filled: true,
            fillColor: enabled
                ? FnColors.backgroundElevated
                : FnColors.backgroundAlternative,
            prefixIcon: prefix,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: FnSpace.x16, vertical: FnSpace.x12),
            border: OutlineInputBorder(
              borderRadius: FnRadius.br12,
              borderSide: BorderSide(color: FnColors.lineNormal),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: FnRadius.br12,
              borderSide: BorderSide(
                  color: hasError ? FnColors.statusNegative : FnColors.lineNormal),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: FnRadius.br12,
              borderSide: const BorderSide(
                  color: FnColors.primaryNormal, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: FnRadius.br12,
              borderSide: BorderSide(color: FnColors.lineAlternative),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: FnRadius.br12,
              borderSide: const BorderSide(color: FnColors.statusNegative),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: FnSpace.x6),
          Text(
            errorText!,
            style: FnType.caption1.copyWith(color: FnColors.statusNegative),
          ),
        ] else if (helperText != null) ...[
          const SizedBox(height: FnSpace.x6),
          Text(
            helperText!,
            style: FnType.caption1.copyWith(color: FnColors.labelAssistive),
          ),
        ],
      ],
    );
  }
}

/// Wanted DS — SearchBar
class FnSearchBar extends StatelessWidget {
  const FnSearchBar({
    super.key,
    this.hint = '검색',
    this.controller,
    this.onChanged,
    this.onClear,
    this.margin,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: 44,
      decoration: BoxDecoration(
        color: FnColors.backgroundElevated,
        borderRadius: FnRadius.br12,
        border: Border.all(color: FnColors.lineNeutral),
      ),
      child: Row(
        children: [
          const SizedBox(width: FnSpace.x12),
          Icon(Icons.search_rounded, size: 18, color: FnColors.labelAssistive),
          const SizedBox(width: FnSpace.x8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: FnType.body2.copyWith(color: FnColors.labelNormal),
              cursorColor: FnColors.primaryNormal,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    FnType.body2.copyWith(color: FnColors.labelAssistive),
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              icon: Icon(Icons.cancel_rounded,
                  size: 16, color: FnColors.labelAssistive),
              onPressed: onClear,
              splashRadius: 16,
            ),
          const SizedBox(width: FnSpace.x4),
        ],
      ),
    );

    return margin == null ? field : Padding(padding: margin!, child: field);
  }
}

/// 금액 입력 — 천 단위 콤마 자동
class FnAmountField extends StatelessWidget {
  const FnAmountField({
    super.key,
    this.label,
    this.controller,
    this.onChanged,
    this.hint = '0',
    this.suffix = '원',
    this.enabled = true,
  });

  final String? label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  final String suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FnTextField(
      label: label,
      hint: hint,
      controller: controller,
      onChanged: onChanged,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.end,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _ThousandsFormatter(),
      ],
      suffix: Padding(
        padding: const EdgeInsets.only(right: FnSpace.x16),
        child: Text(
          suffix,
          style: FnType.body2.copyWith(color: FnColors.labelAlternative),
        ),
      ),
    );
  }
}

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _comma(n);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _comma(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// 드롭다운 선택
class FnDropdown<T> extends StatelessWidget {
  const FnDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.itemLabel,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final String Function(T)? itemLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!,
              style: FnType.label2.copyWith(color: FnColors.labelNeutral)),
          const SizedBox(height: FnSpace.x8),
        ],
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: FnSpace.x16),
          decoration: BoxDecoration(
            color: FnColors.backgroundElevated,
            borderRadius: FnRadius.br12,
            border: Border.all(color: FnColors.lineNormal),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              hint: hint == null
                  ? null
                  : Text(hint!,
                      style: FnType.body2
                          .copyWith(color: FnColors.labelAssistive)),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: FnColors.labelAlternative),
              style: FnType.body2.copyWith(color: FnColors.labelNormal),
              borderRadius: FnRadius.br12,
              items: items
                  .map((e) => DropdownMenuItem<T>(
                        value: e,
                        child: Text(itemLabel?.call(e) ?? e.toString()),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// 세그먼트 토글 — 기간 선택 등
class FnSegmented<T> extends StatelessWidget {
  const FnSegmented({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelOf,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: FnColors.fillNormal,
        borderRadius: FnRadius.br10,
      ),
      child: Row(
        children: items.map((e) {
          final sel = e == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: FnDuration.fast,
                decoration: BoxDecoration(
                  color: sel ? FnColors.backgroundElevated : Colors.transparent,
                  borderRadius: FnRadius.br8,
                  boxShadow: sel ? FnShadow.normal : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  labelOf?.call(e) ?? e.toString(),
                  style: FnType.label2.copyWith(
                    color:
                        sel ? FnColors.labelNormal : FnColors.labelAlternative,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
