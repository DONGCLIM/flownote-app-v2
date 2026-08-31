import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/fn_brand.dart';
import '../design/fn_tokens.dart';
import '../design/fn_button.dart';
import '../design/fn_input.dart';
import '../design/fn_feedback.dart';
import '../providers/auth_provider.dart';
import 'signup_screen.dart';
import 'ds/main_ds_screen.dart';

/// [구버전] 로그인 화면. DS 앱은 `SignInDsScreen` 을 사용한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _showEmailForm = false;
  String? _emailError;
  String? _pwError;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _enter() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainDsScreen()),
      (r) => false,
    );
  }

  Future<void> _login() async {
    setState(() {
      _emailError = _email.text.trim().isEmpty
          ? '이메일을 입력해 주세요'
          : (!_email.text.contains('@') ? '올바른 이메일 형식이 아니에요' : null);
      _pwError = _password.text.isEmpty ? '비밀번호를 입력해 주세요' : null;
    });
    if (_emailError != null || _pwError != null) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (ok) {
      _enter();
    } else {
      showFnToast(context, auth.error ?? '로그인에 실패했어요',
          type: FnToastType.error);
    }
  }

  void _social(String provider) {
    showFnToast(context, '$provider 로그인은 준비 중이에요',
        type: FnToastType.normal);
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      backgroundColor: FnColors.backgroundApp,
      body: SafeArea(
        child: Stack(
          children: [
            FadeTransition(
              opacity: _anim,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    FnSpace.x24, FnSpace.x32, FnSpace.x24, FnSpace.x32),
                children: [
                  // 로고 — 시안 `__resources.fnLogo`
                  // 로고(심볼). 그림에 스쿼클이 있어 다시 자르지 않는다.
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: FnAppMark(size: 84),
                  ),
                  const SizedBox(height: FnSpace.x20),
                  // 텍스트로고(워드마크). display2 글자 크기에 맞춘 높이.
                  const FnWordmark(height: 28),
                  const SizedBox(height: FnSpace.x6),
                  Text(
                    '꽃 영수증을 찍기만 하면\n매입 장부가 완성돼요',
                    style: FnType.body1
                        .copyWith(color: FnColors.labelAlternative),
                  ),
                  const SizedBox(height: FnSpace.x40),

                  // 소셜 로그인
                  _SocialButton(
                    label: '카카오로 3초 만에 시작',
                    background: const Color(0xFFFEE500),
                    foreground: const Color(0xFF191600),
                    icon: Icons.chat_bubble_rounded,
                    onTap: () => _social('카카오'),
                  ),
                  const SizedBox(height: FnSpace.x8),
                  _SocialButton(
                    label: '네이버로 시작하기',
                    background: const Color(0xFF03C75A),
                    foreground: Colors.white,
                    icon: Icons.navigation_rounded,
                    onTap: () => _social('네이버'),
                  ),
                  const SizedBox(height: FnSpace.x8),
                  _SocialButton(
                    label: 'Google로 시작하기',
                    background: Colors.white,
                    foreground: FnColors.labelNormal,
                    icon: Icons.g_mobiledata_rounded,
                    bordered: true,
                    onTap: () => _social('Google'),
                  ),

                  const SizedBox(height: FnSpace.x24),
                  Row(
                    children: [
                      const Expanded(
                          child: Divider(color: FnColors.lineNeutral)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: FnSpace.x12),
                        child: Text('또는',
                            style: FnType.caption1
                                .copyWith(color: FnColors.labelAssistive)),
                      ),
                      const Expanded(
                          child: Divider(color: FnColors.lineNeutral)),
                    ],
                  ),
                  const SizedBox(height: FnSpace.x20),

                  // 이메일 로그인 (접힘)
                  if (!_showEmailForm)
                    Center(
                      child: FnTextButton(
                        label: '이메일로 로그인',
                        color: FnColors.labelAlternative,
                        onPressed: () =>
                            setState(() => _showEmailForm = true),
                      ),
                    )
                  else ...[
                    FnTextField(
                      label: '이메일',
                      hint: 'flower@example.com',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailError,
                      onChanged: (_) {
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                      },
                    ),
                    const SizedBox(height: FnSpace.x14),
                    FnTextField(
                      label: '비밀번호',
                      hint: '••••••••',
                      controller: _password,
                      obscureText: _obscure,
                      errorText: _pwError,
                      onSubmitted: (_) => _login(),
                      onChanged: (_) {
                        if (_pwError != null) setState(() => _pwError = null);
                      },
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 19,
                          color: FnColors.labelAssistive,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: FnSpace.x20),
                    FnButton(
                      label: '로그인',
                      size: FnButtonSize.large,
                      expand: true,
                      loading: loading,
                      onPressed: _login,
                    ),
                    const SizedBox(height: FnSpace.x12),
                    Center(
                      child: FnTextButton(
                        label: '접기',
                        color: FnColors.labelAssistive,
                        onPressed: () =>
                            setState(() => _showEmailForm = false),
                      ),
                    ),
                  ],

                  const SizedBox(height: FnSpace.x24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('아직 계정이 없으신가요?',
                          style: FnType.body2
                              .copyWith(color: FnColors.labelAlternative)),
                      const SizedBox(width: FnSpace.x4),
                      FnTextButton(
                        label: '회원가입',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (loading && !_showEmailForm)
              const FnLoadingOverlay(message: '들어가는 중...'),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onTap,
    this.bordered = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
  final VoidCallback onTap;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: FnRadius.br12,
      child: InkWell(
        onTap: onTap,
        borderRadius: FnRadius.br12,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: FnRadius.br12,
            border:
                bordered ? Border.all(color: FnColors.lineNormal) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: FnSpace.x16,
                child: Icon(icon, size: 21, color: foreground),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
