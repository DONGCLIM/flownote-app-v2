import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/fn_signup_tokens.dart';

/// 🔴 #156 — 회원가입 흐름 공용 조각.
///
/// 시안 9장(이메일 4 + 비밀번호/인증/완료 5)이 **같은 뼈대**를 쓴다.
///   앱바 '회원가입' → 헤드라인 두 줄 → 부제 → (내용) → 버튼
/// 화면마다 복사하면 한 곳만 고쳐도 나머지가 어긋나므로 여기로 모았다.
///
/// ⚠️ 여기 수치를 바꾸면 9개 화면이 전부 바뀐다. 시안 실측값은
///    `FnSignup` 토큰에 근거가 적혀 있으니 그쪽을 먼저 볼 것.

/// 시안 공통 헤드라인(두 줄, 800 굵기).
class SignupHeadline extends StatelessWidget {
  const SignupHeadline(this.text, {super.key, this.center = false});

  final String text;

  /// 완료 화면만 가운데 정렬이다(시안 실측: 글자 x 범위가 화면 중심 대칭).
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: FnSignup.headlineSize,
          fontWeight: FontWeight.w800,
          height: FnSignup.headlineHeight,
          color: FnSignup.headline,
        ),
      );
}

/// 시안 공통 부제.
class SignupSubtitle extends StatelessWidget {
  const SignupSubtitle(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: FnSignup.subtitleSize,
          fontWeight: FontWeight.w500,
          height: 1.45,
          color: FnSignup.subtle,
        ),
      );
}

/// 시안 공통 필드 라벨 ('이메일' · '비밀번호' · '비밀번호 확인').
class SignupFieldLabel extends StatelessWidget {
  const SignupFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: FnSignup.labelSize,
          fontWeight: FontWeight.w600,
          color: FnSignup.subtle,
        ),
      );
}

/// 시안 공통 입력창.
///
/// 오류일 때 테두리가 코랄로 바뀌는 것까지 여기서 처리한다.
class SignupField extends StatelessWidget {
  const SignupField({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.error = false,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final bool error;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  static OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(FnSignup.fieldRadius),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: FnSignup.fieldHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        obscuringCharacter: '●',
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: inputFormatters,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: FnSignup.fieldTextSize,
          fontWeight: FontWeight.w500,
          color: FnSignup.headline,
        ),
        cursorColor: FnSignup.coral,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnSignup.fieldTextSize,
            fontWeight: FontWeight.w500,
            color: FnSignup.placeholder,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: FnSignup.fieldPadH,
            vertical: 13,
          ),
          enabledBorder: border(
            error ? FnSignup.coral : FnSignup.fieldBorder,
            error
                ? FnSignup.fieldBorderWidthError
                : FnSignup.fieldBorderWidth,
          ),
          focusedBorder:
              border(FnSignup.coral, FnSignup.fieldBorderWidthError),
          border: border(FnSignup.fieldBorder, FnSignup.fieldBorderWidth),
        ),
      ),
    );
  }
}

/// 입력창 아래 코랄 오류문.
class SignupFieldError extends StatelessWidget {
  const SignupFieldError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: FnSignup.gapFieldToError),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnSignup.errorSize,
            fontWeight: FontWeight.w500,
            color: FnSignup.coral,
          ),
        ),
      );
}

/// 시안 공통 버튼.
///
/// 세 가지 모양을 쓴다.
///   [SignupButtonStyle.primary]   코랄 바탕 + 흰 글자 (비활성이면 회색)
///   [SignupButtonStyle.outlined]  흰 바탕 + 코랄 테두리 + 코랄 글자
///   [SignupButtonStyle.secondary] 연한 코랄 바탕 + 코랄 글자
enum SignupButtonStyle { primary, outlined, secondary }

class SignupButton extends StatefulWidget {
  const SignupButton({
    super.key,
    required this.label,
    this.onTap,
    this.style = SignupButtonStyle.primary,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final SignupButtonStyle style;
  final bool busy;

  @override
  State<SignupButton> createState() => _SignupButtonState();
}

class _SignupButtonState extends State<SignupButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;

    late final Color fill;
    late final Color fg;
    BorderSide? side;
    switch (widget.style) {
      case SignupButtonStyle.primary:
        fill = enabled ? FnSignup.coral : FnSignup.disabledFill;
        fg = enabled ? Colors.white : FnSignup.disabledFg;
      case SignupButtonStyle.outlined:
        fill = Colors.white;
        fg = FnSignup.coral;
        side = const BorderSide(
            color: FnSignup.coral, width: FnSignup.fieldBorderWidthError);
      case SignupButtonStyle.secondary:
        fill = FnSignup.secondaryFill;
        fg = FnSignup.secondaryFg;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.985 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: FnSignup.buttonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(FnSignup.buttonRadius),
            border: side == null ? null : Border.fromBorderSide(side),
          ),
          child: widget.busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: FnSignup.buttonTextSize,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}
