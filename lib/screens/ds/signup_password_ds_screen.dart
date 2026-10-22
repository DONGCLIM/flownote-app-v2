import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../../design/fn_brand.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_shell.dart';
import '../../providers/auth_provider.dart';
import 'legal_doc_ds_screen.dart';
import '../../design/fn_signup_tokens.dart';
import 'signup_parts.dart';

/// 🔴 #156 — 회원가입 2단계: 비밀번호 설정.
///
/// 사장님 시안 3장(비었음 / 채워짐 / 오류) 그대로다.
///
/// | 상태 | 비밀번호 | 비밀번호 확인 | 버튼 |
/// |---|---|---|---|
/// | 비었음 | 회색 테두리 | 회색 테두리 | 회색 `다음` |
/// | 채워짐 | 회색 테두리 | 회색 테두리 | 코랄 `다음` |
/// | 오류 | 코랄 + 오류문 | 코랄 + 오류문 | 코랄 `다시 입력하기` |
///
/// ## 규칙 (시안 부제 그대로)
/// `영문과 숫자를 포함한 8~16자`
///
/// 시안 3번은 두 오류를 **동시에** 보여준다.
///   비밀번호     → `영문과 숫자를 포함한 8~16자로 입력해주세요.`
///   비밀번호 확인 → `비밀번호가 일치하지 않습니다.`
/// 그래서 오류를 한 번에 하나만 띄우지 않고 칸마다 따로 들고 있는다.
class SignupPasswordDsScreen extends StatefulWidget {
  const SignupPasswordDsScreen({super.key, required this.email});

  final String email;

  @override
  State<SignupPasswordDsScreen> createState() => SignupPasswordDsScreenState();
}

class SignupPasswordDsScreenState extends State<SignupPasswordDsScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _pwFocus = FocusNode();

  String? _pwErr;
  String? _pw2Err;

  /// 오류를 한 번이라도 띄웠는지. 띄운 뒤에는 버튼 글자가 `다시 입력하기` 다.
  bool get _hasError => _pwErr != null || _pw2Err != null;

  @override
  void initState() {
    super.initState();
    _pw.addListener(_onChanged);
    _pw2.addListener(_onChanged);
  }

  @override
  void dispose() {
    _pw.removeListener(_onChanged);
    _pw2.removeListener(_onChanged);
    _pw.dispose();
    _pw2.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    // 글자를 고치면 오류 표시를 즉시 걷는다(시안 흐름).
    if (_hasError) {
      setState(() {
        _pwErr = null;
        _pw2Err = null;
      });
    } else {
      setState(() {});
    }
  }

  /// 🔴 시안 부제의 규칙 — 영문과 숫자를 **둘 다** 포함한 8~16자.
  ///
  /// ⚠️ 길이만 보게 고치지 말 것. 시안 3번이 8자 미만(`••••••` 6자)을
  ///    거절하는 화면이고, 부제가 '영문과 숫자를 포함한' 이라고 못 박는다.
  static bool isValidPassword(String s) {
    if (s.length < 8 || s.length > 16) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(s)) return false;
    if (!RegExp(r'[0-9]').hasMatch(s)) return false;
    return true;
  }

  /// 두 칸 모두 글자가 있으면 버튼을 누를 수 있다(시안 2번).
  bool get _canPress => _pw.text.isNotEmpty && _pw2.text.isNotEmpty;

  String get _buttonLabel => _hasError ? '다시 입력하기' : '다음';

  void _onPressed() {
    if (!_canPress) return;
    FocusScope.of(context).unfocus();

    // 시안 3번의 `다시 입력하기` — 두 칸을 비우고 처음으로.
    if (_hasError) {
      _pw.clear();
      _pw2.clear();
      setState(() {
        _pwErr = null;
        _pw2Err = null;
      });
      _pwFocus.requestFocus();
      return;
    }

    String? e1;
    String? e2;
    if (!isValidPassword(_pw.text)) {
      e1 = '영문과 숫자를 포함한 8~16자로 입력해주세요.';
    }
    if (_pw2.text != _pw.text) {
      e2 = '비밀번호가 일치하지 않습니다.';
    }

    if (e1 != null || e2 != null) {
      setState(() {
        _pwErr = e1;
        _pw2Err = e2;
      });
      return;
    }

    // 통과 → 휴대폰 인증 화면으로.
    //
    // 🔴 계정은 여기서 만들지 않는다. 시안 흐름(이메일→비번→인증→완료)에는
    //    **약관 동의 화면이 없는데**, 약관·개인정보 동의는 법적으로 받아야
    //    하고 `AuthProvider.signUp` 도 동의 없이는 거절한다.
    //    그래서 실제 계정 생성은 마지막 완료 직전(인증 화면)에서 하고,
    //    동의는 그 직전에 시트로 받는다. 사장님께 약관 화면을 시안에
    //    추가할지 여쭌 뒤 정식 단계로 뺄 예정이다.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignupVerifyDsScreen(
          email: widget.email,
          password: _pw.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '회원가입',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 0, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: FnSignup.headlineTop),
            const SignupHeadline('사용할 비밀번호를\n설정해주세요.'),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle('영문과 숫자를 포함한 8~16자'),
            const SizedBox(height: FnSignup.gapSubToLabel),
            const SignupFieldLabel('비밀번호'),
            const SizedBox(height: FnSignup.gapLabelToField),
            SignupField(
              controller: _pw,
              focusNode: _pwFocus,
              hint: '비밀번호를 입력해주세요',
              obscure: true,
              error: _pwErr != null,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                LengthLimitingTextInputFormatter(16),
              ],
            ),
            if (_pwErr != null) SignupFieldError(_pwErr!),
            const SizedBox(height: FnSignup.gapFieldToLabel2),
            const SignupFieldLabel('비밀번호 확인'),
            const SizedBox(height: FnSignup.gapLabelToField),
            SignupField(
              controller: _pw2,
              hint: '비밀번호를 한 번 더 입력해주세요',
              obscure: true,
              error: _pw2Err != null,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
                LengthLimitingTextInputFormatter(16),
              ],
              onSubmitted: (_) => _onPressed(),
            ),
            if (_pw2Err != null) SignupFieldError(_pw2Err!),
            SizedBox(
                height: _hasError
                    ? FnSignup.gapErrorToButton
                    : FnSignup.gapField2ToButton),
            SignupButton(
              label: _buttonLabel,
              onTap: _canPress ? _onPressed : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 🔴 #156 — 회원가입 3단계: 휴대폰 인증.
///
/// 시안은 제목·부제·버튼 하나가 전부다. 실제 본인확인(PASS/NICE 등)은
/// 아직 계약된 수단이 없으므로, 지금은 **건너뛸 수 있게** 두고 사장님께
/// 어떤 업체를 쓸지 여쭙는다.
///
/// ⚠️ 여기서 가짜 인증(아무 번호나 통과)을 넣지 말 것. 본인확인은 법적
///    효력이 걸린 절차라, 흉내만 내면 나중에 더 큰 문제가 된다.
class SignupVerifyDsScreen extends StatefulWidget {
  const SignupVerifyDsScreen({
    super.key,
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  @override
  State<SignupVerifyDsScreen> createState() => SignupVerifyDsScreenState();
}

class SignupVerifyDsScreenState extends State<SignupVerifyDsScreen> {
  bool _busy = false;

  /// 🔴 여기서 **실제 계정을 만든다.**
  ///
  /// 시안 흐름에는 약관 화면이 없지만 동의는 법적 필수이고
  /// `AuthProvider.signUp` 도 동의 없이는 거절한다. 그래서 가입 직전에
  /// 한 번 확인받는다. (사장님이 약관을 별도 화면으로 빼라고 하시면
  /// 이 시트를 정식 단계로 옮긴다.)
  Future<void> _verify() async {
    if (_busy) return;

    final agreed = await showFnAlert(
      context,
      title: '약관에 동의해 주세요',
      message: '서비스 이용약관과 개인정보 처리방침에 동의하면\n가입이 완료됩니다.',
      confirmLabel: '동의하고 가입',
      cancelLabel: '약관 보기',
      icon: Icons.verified_user_outlined,
    );
    if (!mounted) return;

    // '약관 보기' 를 누르면 문서를 띄우고 이 화면에 머문다.
    if (!agreed) {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => const LegalDocDsScreen(kind: LegalDocKind.terms)),
      );
      return;
    }

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: widget.email,
      // 상호명은 시안에 칸이 없다. 사업자등록증 온보딩에서 받으므로
      // 지금은 이메일 아이디 부분을 임시 표시 이름으로 둔다.
      name: widget.email.split('@').first,
      password: widget.password,
      agreeTerms: true,
      agreePrivacy: true,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      final msg = auth.error ?? '회원가입에 실패했습니다.';
      auth.clearError();

      // 이미 가입된 메일이면 이메일 단계까지 되돌려 시안 4번 화면을 띄운다.
      if (msg.contains('이미 가입')) {
        Navigator.of(context).popUntil((r) => r.isFirst || !r.willHandlePopInternally);
        if (!mounted) return;
        showFnToast(context, msg, type: FnToastType.error);
        return;
      }

      showFnToast(context, msg, type: FnToastType.error);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignupDoneDsScreen(email: widget.email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '회원가입',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 0, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: FnSignup.headlineTop),
            const SignupHeadline('휴대폰 인증을\n진행해주세요.'),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle('원활한 서비스 이용을 위해\n본인확인이 필요해요.'),
            const SizedBox(height: FnSignup.gapSubToVerifyButton),
            SignupButton(
              label: '휴대폰 인증하기',
              busy: _busy,
              onTap: _verify,
            ),
          ],
        ),
      ),
    );
  }
}

/// 🔴 #156 — 회원가입 4단계: 완료.
///
/// 시안은 워드마크(코랄 꽃잎 판) + 가운데 정렬 문구 + 코랄 버튼 하나다.
/// 사장님 요청으로 **두 번째 버튼**(사업자등록증 등록)을 아래에 더했고,
/// 톤이 깨지지 않도록 같은 코랄 계열의 연한 배경을 쓴다.
class SignupDoneDsScreen extends StatelessWidget {
  const SignupDoneDsScreen({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '회원가입',
      bg: FnSignup.bg,
      showNavBar: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 0, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 시안 워드마크 top 425px -> 337dp. 앱바(56)를 빼면 281dp.
            const SizedBox(height: 281),
            const Center(
              child: FnWordmark(
                height: FnSignup.doneWordmarkHeight,
                color: true,
              ),
            ),
            const SizedBox(height: FnSignup.gapWordmarkToHeadline),
            const SignupHeadline('회원가입이\n완료되었어요.', center: true),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle('로그인하고 영수증 정리를 시작해보세요.', center: true),
            const SizedBox(height: FnSignup.gapSubToVerifyButton),
            SignupButton(
              label: '로그인하기',
              onTap: () => Navigator.of(context)
                  .popUntil((r) => r.isFirst),
            ),
            const SizedBox(height: FnSignup.gapBetweenButtons),
            SignupButton(
              label: '사업자등록증 등록하러 가기',
              style: SignupButtonStyle.secondary,
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
