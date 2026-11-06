import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_signup_tokens.dart';
import '../../providers/auth_provider.dart';
import 'auth_ds_screens.dart';
import 'signup_parts.dart';
import 'signup_password_ds_screen.dart';

/// 🔴 #155 — 회원가입 1단계: 이메일 입력.
///
/// 사장님 시안 4장을 왼쪽→오른쪽 순서로 그대로 구현한 화면이다.
/// 한 화면이 네 가지 상태를 오가며, 상태 전환은 아래 표가 전부다.
///
/// | # | 상태 | 입력창 | 버튼 | 아래 |
/// |---|---|---|---|---|
/// | 1 | [_Phase.empty]    | 회색 테두리 | 회색 `다음` (비활성) | — |
/// | 2 | [_Phase.filled]   | 회색 테두리 | 코랄 `다음` | — |
/// | 3 | [_Phase.invalid]  | 코랄 테두리 | 코랄 `다시 입력하기` | 코랄 오류문 |
/// | 4 | [_Phase.taken]    | (숨김) | 코랄 `로그인하기` + 외곽선 `비밀번호 찾기` | 가입된 이메일 카드 |
///
/// ## 🔴 4번 화면을 "미리" 띄울 수 없는 이유 (직접 확인함)
///
/// 이 Firebase 프로젝트는 **이메일 열거 보호가 켜져 있다.** 임시 계정을
/// 만들어 확인한 결과는 이렇다(확인 후 계정은 삭제했다).
///
/// ```
/// accounts:createAuthUri  (가입된 이메일)  -> { sessionId } 만 옴. registered 없음
/// accounts:signInWithPassword (없는 메일) -> INVALID_LOGIN_CREDENTIALS (구분 불가)
/// accounts:signUp  (중복 이메일)          -> EMAIL_EXISTS  ✅ 이것만 정확함
/// ```
///
/// 즉 "타이핑만으로 이미 가입된 메일인지" 알아내는 방법은 막혀 있고,
/// 그게 정상이다(계정 유무를 캐낼 수 있으면 보안 구멍이다). 그래서
/// 4번 화면은 **가입을 실제로 시도한 뒤** `email-already-in-use` 를
/// 받았을 때 보여준다.
///
/// ⚠️ 여기에 `fetchSignInMethodsForEmail` 을 다시 넣지 말 것.
///    열거 보호가 켜진 프로젝트에서는 **항상 빈 배열**을 돌려주므로,
///    "가입 안 된 메일" 로 잘못 판정해 4번 화면이 영영 안 뜬다.
class SignupEmailDsScreen extends StatefulWidget {
  const SignupEmailDsScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<SignupEmailDsScreen> createState() => SignupEmailDsScreenState();
}

/// 시안 4장에 대응하는 화면 상태.
enum _Phase { empty, filled, invalid, taken }

/// 🔴 #155 테스트가 [isValidEmail] 과 [showTaken] 을 직접 부른다.
/// private 으로 되돌리면 `Member not found` 로 테스트가 깨진다(#148 과 같은 실수).
class SignupEmailDsScreenState extends State<SignupEmailDsScreen> {
  late final TextEditingController _email;
  final _focus = FocusNode();

  _Phase _phase = _Phase.empty;
  bool _busy = false;

  /// 4번 화면에 보여줄, 이미 가입된 이메일.
  String _takenEmail = '';

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
    _email.addListener(_onChanged);
    if (_email.text.trim().isNotEmpty) _phase = _Phase.filled;
  }

  @override
  void dispose() {
    _email.removeListener(_onChanged);
    _email.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 🔴 이메일 형식 검사.
  ///
  /// 시안 3번은 `flownote@` 를 "형식을 확인해주세요" 로 막는다. 즉 `@` 뒤에
  /// 점이 있는 도메인까지 있어야 통과다. 공백도 허용하지 않는다.
  static bool isValidEmail(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.contains(' ')) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(t);
  }

  void _onChanged() {
    // 글자를 고치면 오류/중복 상태에서 즉시 빠져나온다.
    final has = _email.text.trim().isNotEmpty;
    final next = has ? _Phase.filled : _Phase.empty;
    if (_phase != next) setState(() => _phase = next);
  }

  /// 버튼을 누를 수 있는지. 1번 화면에서만 false.
  bool get _canPress => _phase != _Phase.empty && !_busy;

  String get _buttonLabel => switch (_phase) {
        _Phase.invalid => '다시 입력하기',
        _Phase.taken => '로그인하기',
        _ => '다음',
      };

  Future<void> _onPressed() async {
    if (!_canPress) return;
    FocusScope.of(context).unfocus();

    // 3번 화면의 `다시 입력하기` — 입력창을 비우고 1번으로 되돌린다.
    if (_phase == _Phase.invalid) {
      _email.clear();
      setState(() => _phase = _Phase.empty);
      _focus.requestFocus();
      return;
    }

    // 4번 화면의 `로그인하기`
    if (_phase == _Phase.taken) {
      _goSignIn();
      return;
    }

    final email = _email.text.trim();

    // 2번 -> 3번: 형식이 틀리면 서버를 부르지 않는다.
    if (!isValidEmail(email)) {
      setState(() => _phase = _Phase.invalid);
      return;
    }

    // 형식이 맞으면 다음 단계(비밀번호/약관)로 넘긴다.
    //
    // 🔴 이미 가입된 메일인지는 여기서 알 수 없다(위 주석 참고).
    //    다음 단계가 가입을 시도하다 `email-already-in-use` 를 받으면
    //    [showTaken] 으로 이 화면의 4번 상태를 띄운다.
    setState(() => _busy = true);
    final taken = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SignupPasswordDsScreen(email: email),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (taken == true) showTaken(email);
  }

  /// 다음 단계에서 "이미 가입된 이메일" 을 만났을 때 4번 화면으로 전환.
  void showTaken(String email) {
    setState(() {
      _takenEmail = email;
      _phase = _Phase.taken;
    });
  }

  void _goSignIn() {
    final email = _takenEmail.isNotEmpty ? _takenEmail : _email.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SignInDsScreen(initialEmail: email)),
    );
  }

  Future<void> _onFindPassword() async {
    final email = _takenEmail.isNotEmpty ? _takenEmail : _email.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '$email 로 비밀번호 재설정 메일을 보냈어요.'
            : (auth.error ?? '메일 발송에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      ),
    );
    auth.clearError();
  }

  // ── 조각들 ───────────────────────────────────────────────

  Widget _headline() => SignupHeadline(_phase == _Phase.taken
      ? '이미 가입된\n이메일이에요.'
      : '가입할 이메일을\n입력해주세요.');

  Widget _subtitle() => SignupSubtitle(_phase == _Phase.taken
      ? '기존 계정으로 로그인해 서비스를 이용해주세요.'
      : '로그인에 사용할 이메일을 입력해주세요.');

  Widget _field() => SignupField(
        controller: _email,
        focusNode: _focus,
        hint: '이메일을 입력해주세요',
        error: _phase == _Phase.invalid,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          // 이메일에 공백이 들어갈 일은 없다. 붙여넣기 사고를 막는다.
          FilteringTextInputFormatter.deny(RegExp(r'\s')),
        ],
        onSubmitted: (_) => _onPressed(),
      );

  /// 4번 화면의 흰 카드.
  Widget _takenCard() {
    return Container(
      height: FnSignup.cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: FnSignup.cardPadH),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FnSignup.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '가입된 이메일',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: FnSignup.cardLabelSize,
              fontWeight: FontWeight.w500,
              color: FnSignup.cardLabel,
            ),
          ),
          const SizedBox(height: FnSignup.cardGap),
          Text(
            _takenEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: FnSignup.cardValueSize,
              fontWeight: FontWeight.w600,
              color: FnSignup.cardValue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton() => SignupButton(
        label: _buttonLabel,
        busy: _busy,
        onTap: _canPress ? _onPressed : null,
      );

  Widget _outlinedButton() => SignupButton(
        label: '비밀번호 찾기',
        style: SignupButtonStyle.outlined,
        onTap: _busy ? null : _onFindPassword,
      );

  @override
  Widget build(BuildContext context) {
    final taken = _phase == _Phase.taken;
    final invalid = _phase == _Phase.invalid;

    return FnShell(
      navTitle: '회원가입',
      bg: FnSignup.bg,
      onBack: () {
        // 4번 화면에서 뒤로가면 이메일 입력으로 되돌린다(화면을 닫지 않는다).
        if (taken) {
          setState(() => _phase =
              _email.text.trim().isEmpty ? _Phase.empty : _Phase.filled);
          return;
        }
        Navigator.of(context).maybePop();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 0, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: FnSignup.headlineTop),
            _headline(),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            _subtitle(),
            if (taken) ...[
              const SizedBox(height: FnSignup.gapSubToCard),
              _takenCard(),
              const SizedBox(height: FnSignup.gapCardToButton),
              _primaryButton(),
              const SizedBox(height: FnSignup.gapBetweenButtons),
              _outlinedButton(),
            ] else ...[
              const SizedBox(height: FnSignup.gapSubToLabel),
              const Text(
                '이메일',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: FnSignup.labelSize,
                  fontWeight: FontWeight.w600,
                  color: FnSignup.subtle,
                ),
              ),
              const SizedBox(height: FnSignup.gapLabelToField),
              _field(),
              if (invalid) ...[
                const SignupFieldError('이메일 형식을 확인해주세요.'),
                const SizedBox(height: FnSignup.gapErrorToButton),
              ] else
                const SizedBox(height: FnSignup.gapFieldToButton),
              _primaryButton(),
            ],
          ],
        ),
      ),
    );
  }
}
