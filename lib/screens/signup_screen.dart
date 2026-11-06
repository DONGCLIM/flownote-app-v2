import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/fn_tokens.dart';
import '../design/fn_button.dart';
import '../design/fn_input.dart';
import '../design/fn_scaffold.dart';
import '../design/fn_feedback.dart';
import '../providers/auth_provider.dart';
import 'onboarding/business_info_screen.dart';

/// 회원가입 화면.
///
/// 가입 후 곧바로 사업자 정보 입력(온보딩) 으로 넘어간다.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _obscure2 = true;
  bool _agreeService = false;
  bool _agreePrivacy = false;
  bool _agreeMarketing = false;

  String? _eName, _eEmail, _ePw, _eConfirm;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allAgreed =>
      _agreeService && _agreePrivacy && _agreeMarketing;

  bool get _canSubmit =>
      _name.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _password.text.length >= 6 &&
      _password.text == _confirm.text &&
      _agreeService &&
      _agreePrivacy;

  /// 비밀번호 강도 0~3
  int get _pwStrength {
    final p = _password.text;
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Za-z]').hasMatch(p) && RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(p)) s++;
    return s;
  }

  void _validate() {
    setState(() {
      _eName = _name.text.trim().isEmpty ? '이름을 입력해 주세요' : null;
      final e = _email.text.trim();
      _eEmail = e.isEmpty
          ? '이메일을 입력해 주세요'
          : (!RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$').hasMatch(e)
              ? '올바른 이메일 형식이 아니에요'
              : null);
      _ePw = _password.text.length < 6 ? '6자 이상 입력해 주세요' : null;
      _eConfirm =
          _confirm.text != _password.text ? '비밀번호가 서로 달라요' : null;
    });
  }

  Future<void> _submit() async {
    _validate();
    if (_eName != null || _eEmail != null || _ePw != null || _eConfirm != null) {
      return;
    }
    if (!_agreeService || !_agreePrivacy) {
      showFnToast(context, '필수 약관에 동의해 주세요', type: FnToastType.warning);
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;

    if (ok) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const BusinessInfoScreen()),
        (r) => false,
      );
    } else {
      showFnToast(context, auth.error ?? '가입에 실패했어요',
          type: FnToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;

    return Stack(
      children: [
        FnScaffold(
          title: '회원가입',
          bottomBar: FnButton(
            label: '가입하고 시작하기',
            size: FnButtonSize.large,
            expand: true,
            loading: loading,
            onPressed: _canSubmit ? _submit : null,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
                FnSpace.x20, FnSpace.x8, FnSpace.x20, FnSpace.x24),
            children: [
              Text('꽃집 사장님, 반가워요', style: FnType.title3),
              const SizedBox(height: FnSpace.x6),
              Text('가입하면 PRO 기능을 30일 무료로 써볼 수 있어요.',
                  style: FnType.body2
                      .copyWith(color: FnColors.labelAlternative)),
              const SizedBox(height: FnSpace.x24),

              FnTextField(
                label: '이름',
                hint: '예) 김꽃순',
                controller: _name,
                errorText: _eName,
                onChanged: (_) => setState(() => _eName = null),
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '이메일',
                hint: 'flower@example.com',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                errorText: _eEmail,
                onChanged: (_) => setState(() => _eEmail = null),
              ),
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '비밀번호',
                hint: '6자 이상',
                controller: _password,
                obscureText: _obscure,
                errorText: _ePw,
                onChanged: (_) => setState(() => _ePw = null),
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
              if (_password.text.isNotEmpty) ...[
                const SizedBox(height: FnSpace.x8),
                _StrengthBar(level: _pwStrength),
              ],
              const SizedBox(height: FnSpace.x16),
              FnTextField(
                label: '비밀번호 확인',
                hint: '한 번 더 입력',
                controller: _confirm,
                obscureText: _obscure2,
                errorText: _eConfirm,
                onChanged: (_) => setState(() => _eConfirm = null),
                suffix: _confirm.text.isNotEmpty &&
                        _confirm.text == _password.text
                    ? const Padding(
                        padding: EdgeInsets.only(right: FnSpace.x16),
                        child: Icon(Icons.check_circle_rounded,
                            size: 19, color: FnColors.statusPositive),
                      )
                    : IconButton(
                        icon: Icon(
                          _obscure2
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 19,
                          color: FnColors.labelAssistive,
                        ),
                        onPressed: () =>
                            setState(() => _obscure2 = !_obscure2),
                      ),
              ),
              const SizedBox(height: FnSpace.x24),

              // 약관
              Container(
                padding: const EdgeInsets.all(FnSpace.x4),
                decoration: BoxDecoration(
                  color: FnColors.backgroundElevated,
                  borderRadius: FnRadius.br16,
                  border: Border.all(color: FnColors.lineAlternative),
                ),
                child: Column(
                  children: [
                    _AgreeRow(
                      label: '전체 동의',
                      value: _allAgreed,
                      onChanged: (v) => setState(() {
                        _agreeService = v;
                        _agreePrivacy = v;
                        _agreeMarketing = v;
                      }),
                      bold: true,
                    ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: FnSpace.x12),
                      child: Divider(
                          height: 1, color: FnColors.lineAlternative),
                    ),
                    _AgreeRow(
                      label: '[필수] 서비스 이용약관',
                      value: _agreeService,
                      onChanged: (v) => setState(() => _agreeService = v),
                    ),
                    _AgreeRow(
                      label: '[필수] 개인정보 처리방침',
                      value: _agreePrivacy,
                      onChanged: (v) => setState(() => _agreePrivacy = v),
                    ),
                    _AgreeRow(
                      label: '[선택] 시세·혜택 알림 받기',
                      value: _agreeMarketing,
                      onChanged: (v) => setState(() => _agreeMarketing = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (loading) const FnLoadingOverlay(message: '가입하는 중...'),
      ],
    );
  }
}

class _AgreeRow extends StatelessWidget {
  const _AgreeRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.bold = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: FnRadius.br12,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: FnSpace.x12, vertical: FnSpace.x12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: FnDuration.fast,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? FnColors.primaryNormal : Colors.transparent,
                borderRadius: BorderRadius.circular(FnRadius.r6),
                border: Border.all(
                  color: value ? FnColors.primaryNormal : FnColors.lineStrong,
                  width: 1.5,
                ),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: FnSpace.x10),
            Expanded(
              child: Text(
                label,
                style: (bold ? FnType.label1 : FnType.body2).copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: bold
                      ? FnColors.labelNormal
                      : FnColors.labelNeutral,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    const labels = ['약함', '보통', '좋음', '아주 좋음'];
    const colors = [
      FnColors.statusNegative,
      FnColors.statusCautionary,
      FnColors.statusPositive,
      FnColors.statusPositiveStrong,
    ];
    final c = colors[level.clamp(0, 3)];

    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: i < level ? c : FnColors.fillNormal,
                  borderRadius: FnRadius.brFull,
                ),
              ),
            ),
          ),
        const SizedBox(width: FnSpace.x8),
        Text(labels[level.clamp(0, 3)],
            style: FnType.caption2.copyWith(color: c)),
      ],
    );
  }
}
