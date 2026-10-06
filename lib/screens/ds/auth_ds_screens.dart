import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/fn_controls_ds.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_sheet.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_tokens.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import 'auth_unavailable_banner.dart';
import 'legal_doc_ds_screen.dart';
import 'onboarding_ds_screens.dart';

// ═══════════════════════════════════════════════════════════════
// 공용 — 동의 체크박스 (DS 에 체크박스 위젯이 없어 직접 구성)
// ═══════════════════════════════════════════════════════════════

/// 시안 Checkbox 스펙: 20x20 r6, 체크 시 blue-50 배경 + 흰 체크,
/// 미체크 시 흰 배경 + 1px line-normal-normal 테두리
class FnConsentCheck extends StatelessWidget {
  const FnConsentCheck({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.bold = false,
    this.onViewDoc,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool bold;
  final VoidCallback? onViewDoc;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: value ? FnColors.rose50 : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: value ? FnColors.rose50 : FnColors.lineNormal,
                        width: 1,
                      ),
                    ),
                    child: value
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: bold ? 15 : 13,
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
          ),
        ),
        if (onViewDoc != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onViewDoc,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Text(
                '보기',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelAssistive,
                  decoration: TextDecoration.underline,
                  decorationColor: FnColors.labelAssistive,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 회원가입
// ═══════════════════════════════════════════════════════════════

class SignUpDsScreen extends StatefulWidget {
  const SignUpDsScreen({super.key, this.initialEmail, this.initialPassword});

  /// 스플래시에서 이미 입력한 값을 이어받는다.
  final String? initialEmail;
  final String? initialPassword;

  @override
  State<SignUpDsScreen> createState() => _SignUpDsScreenState();
}

class _SignUpDsScreenState extends State<SignUpDsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _pw;
  late final TextEditingController _pw2;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _agreeMarketing = false;
  bool _busy = false;

  String? _emailErr;
  String? _pwErr;
  String? _pw2Err;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _email = TextEditingController(text: widget.initialEmail ?? '');
    _pw = TextEditingController(text: widget.initialPassword ?? '');
    _pw2 = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  bool get _allAgreed => _agreeTerms && _agreePrivacy && _agreeMarketing;

  void _toggleAll(bool v) => setState(() {
        _agreeTerms = v;
        _agreePrivacy = v;
        _agreeMarketing = v;
      });

  bool _validate() {
    final email = _email.text.trim();
    final pw = _pw.text;
    setState(() {
      _emailErr = null;
      _pwErr = null;
      _pw2Err = null;
    });

    var ok = true;
    if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailErr = '이메일 형식을 확인해 주세요.');
      ok = false;
    }
    if (pw.length < 6) {
      setState(() => _pwErr = '비밀번호는 6자 이상이어야 합니다.');
      ok = false;
    }
    if (_pw2.text != pw) {
      setState(() => _pw2Err = '비밀번호가 일치하지 않습니다.');
      ok = false;
    }
    if (_name.text.trim().isEmpty) {
      showFnToast(context, '이름(또는 상호명)을 입력해 주세요.',
          type: FnToastType.error);
      ok = false;
    }
    if (ok && !(_agreeTerms && _agreePrivacy)) {
      showFnToast(context, '필수 약관에 동의해 주세요.', type: FnToastType.error);
      ok = false;
    }
    return ok;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_validate()) return;

    setState(() => _busy = true);
    final email = _email.text.trim();
    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: email,
      name: _name.text.trim(),
      password: _pw.text,
      agreeTerms: _agreeTerms,
      agreePrivacy: _agreePrivacy,
      agreeMarketing: _agreeMarketing,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      final msg = auth.error ?? '회원가입에 실패했습니다.';
      auth.clearError();

      // 이미 가입된 이메일이면 그냥 오류만 띄우지 말고 로그인으로 안내한다.
      if (msg.contains('이미 가입')) {
        final go = await showFnAlert(
          context,
          title: '이미 가입된 이메일이에요',
          message: '$email 로 가입한 계정이 있습니다.\n로그인 화면으로 이동할까요?',
          confirmLabel: '로그인하기',
          cancelLabel: '다른 이메일 쓰기',
          icon: Icons.info_outline_rounded,
        );
        if (!mounted) return;
        if (go) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SignInDsScreen(initialEmail: email),
            ),
          );
        }
        return;
      }

      showFnToast(context, msg, type: FnToastType.error);
      return;
    }

    // 가입 성공 → 사업자등록증 온보딩으로
    //
    // 🔴 `(r) => false` 로 스택을 통째로 비우면 루트의 `_AppEntry` 까지
    // 사라진다. `_AppEntry` 는 `isLoggedIn` 을 보고 MainDsScreen 을
    // 그려주는 유일한 주체이므로, 사라지면 온보딩을 마쳐도 홈으로
    // 넘어가지 못한다. → 루트(`_AppEntry`)는 남기고 그 위에 얹는다.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BusinessDsScreen()),
      (r) => r.isFirst,
    );
  }

  void _openDoc(LegalDocKind kind) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LegalDocDsScreen(kind: kind)),
      );

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '회원가입',
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '영수증 기록을 안전하게 보관해 드릴게요',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '계정을 만들면 휴대폰을 바꿔도 기록이 그대로 유지됩니다.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                height: 1.5,
                color: FnColors.labelNeutral,
              ),
            ),
            const SizedBox(height: 22),
            const AuthUnavailableBanner(),
            FnDsTextField(
              label: '이름 (또는 상호명)',
              controller: _name,
              placeholder: '김꽃순',
            ),
            const SizedBox(height: 14),
            FnDsTextField(
              label: '이메일',
              controller: _email,
              placeholder: 'shop@flownote.kr',
              keyboardType: TextInputType.emailAddress,
              helper: _emailErr,
              status: _emailErr != null
                  ? FnDsFieldStatus.negative
                  : FnDsFieldStatus.normal,
              onChanged: (_) {
                if (_emailErr != null) setState(() => _emailErr = null);
              },
            ),
            const SizedBox(height: 14),
            FnDsTextField(
              label: '비밀번호',
              controller: _pw,
              placeholder: '6자 이상',
              obscureText: true,
              helper: _pwErr,
              status: _pwErr != null
                  ? FnDsFieldStatus.negative
                  : FnDsFieldStatus.normal,
              onChanged: (_) {
                if (_pwErr != null) setState(() => _pwErr = null);
              },
            ),
            const SizedBox(height: 14),
            FnDsTextField(
              label: '비밀번호 확인',
              controller: _pw2,
              placeholder: '••••••••',
              obscureText: true,
              helper: _pw2Err,
              status: _pw2Err != null
                  ? FnDsFieldStatus.negative
                  : FnDsFieldStatus.normal,
              onChanged: (_) {
                if (_pw2Err != null) setState(() => _pw2Err = null);
              },
            ),
            const SizedBox(height: 22),

            // ── 약관 동의 ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: FnColors.rose99,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  FnConsentCheck(
                    value: _allAgreed,
                    label: '전체 동의',
                    bold: true,
                    onChanged: _toggleAll,
                  ),
                  const Divider(
                      height: 9, thickness: 1, color: FnColors.lineAlternative),
                  FnConsentCheck(
                    value: _agreeTerms,
                    label: '[필수] 서비스 이용약관',
                    onChanged: (v) => setState(() => _agreeTerms = v),
                    onViewDoc: () => _openDoc(LegalDocKind.terms),
                  ),
                  FnConsentCheck(
                    value: _agreePrivacy,
                    label: '[필수] 개인정보 처리방침',
                    onChanged: (v) => setState(() => _agreePrivacy = v),
                    onViewDoc: () => _openDoc(LegalDocKind.privacy),
                  ),
                  FnConsentCheck(
                    value: _agreeMarketing,
                    label: '[선택] 마케팅 정보 수신',
                    onChanged: (v) => setState(() => _agreeMarketing = v),
                    onViewDoc: () => _openDoc(LegalDocKind.marketing),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: FnSpinner(),
              ))
            else
              FnDsButton(
                label: '가입하기',
                expand: true,
                disabled: AuthUnavailableBanner.blocked,
                onPressed: _submit,
              ),
            const SizedBox(height: 12),
            Center(
              child: FnDsButton(
                label: '이미 계정이 있어요 · 로그인',
                variant: FnDsButtonVariant.text,
                size: FnDsButtonSize.small,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => SignInDsScreen(
                      initialEmail: _email.text.trim(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 로그인
// ═══════════════════════════════════════════════════════════════

class SignInDsScreen extends StatefulWidget {
  const SignInDsScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<SignInDsScreen> createState() => _SignInDsScreenState();
}

class _SignInDsScreenState extends State<SignInDsScreen> {
  late final TextEditingController _email;
  final _pw = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;

    final email = _email.text.trim();
    if (email.isEmpty || _pw.text.isEmpty) {
      showFnToast(context, '이메일과 비밀번호를 입력해 주세요.',
          type: FnToastType.error);
      return;
    }

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(email: email, password: _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      showFnToast(context, auth.error ?? '로그인에 실패했습니다.',
          type: FnToastType.error);
      auth.clearError();
      return;
    }
    // 성공 → 루트 `_AppEntry` 가 MainDsScreen 을 그린다.
    // 이 화면은 루트 위에 push 되어 있으므로 반드시 걷어내야 홈이 보인다.
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showFnToast(context, '비밀번호를 재설정할 이메일을 먼저 입력해 주세요.',
          type: FnToastType.error);
      return;
    }
    final confirmed = await showFnAlert(
      context,
      title: '비밀번호 재설정',
      message: '$email 주소로\n재설정 링크를 보내드릴까요?',
      confirmLabel: '메일 보내기',
      cancelLabel: '취소',
      icon: Icons.mail_outline_rounded,
    );
    if (!confirmed || !mounted) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;
    if (ok) {
      showFnToast(context, '재설정 메일을 보냈습니다. 메일함을 확인해 주세요.',
          type: FnToastType.success);
    } else {
      showFnToast(context, auth.error ?? '메일 발송에 실패했습니다.',
          type: FnToastType.error);
      auth.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '로그인',
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              '다시 오셨네요!',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '가입하신 이메일로 로그인해 주세요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                height: 1.5,
                color: FnColors.labelNeutral,
              ),
            ),
            const SizedBox(height: 24),
            const AuthUnavailableBanner(),
            FnDsTextField(
              label: '이메일',
              controller: _email,
              placeholder: 'shop@flownote.kr',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            FnDsTextField(
              label: '비밀번호',
              controller: _pw,
              placeholder: '••••••••',
              obscureText: true,
            ),
            const SizedBox(height: 22),
            if (_busy)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: FnSpinner(),
              ))
            else
              FnDsButton(
                label: '로그인',
                expand: true,
                disabled: AuthUnavailableBanner.blocked,
                onPressed: _submit,
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FnDsButton(
                  label: '비밀번호 찾기',
                  variant: FnDsButtonVariant.text,
                  size: FnDsButtonSize.small,
                  onPressed: _reset,
                ),
                const Text('·',
                    style: TextStyle(color: FnColors.labelAssistive)),
                FnDsButton(
                  label: '회원가입',
                  variant: FnDsButtonVariant.text,
                  size: FnDsButtonSize.small,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          SignUpDsScreen(initialEmail: _email.text.trim()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 회원 탈퇴
// ═══════════════════════════════════════════════════════════════

class DeleteAccountDsScreen extends StatefulWidget {
  const DeleteAccountDsScreen({super.key});

  @override
  State<DeleteAccountDsScreen> createState() => _DeleteAccountDsScreenState();
}

class _DeleteAccountDsScreenState extends State<DeleteAccountDsScreen> {
  final _pw = TextEditingController();
  final _confirmText = TextEditingController();
  bool _busy = false;

  static const _phrase = '탈퇴합니다';

  @override
  void dispose() {
    _pw.dispose();
    _confirmText.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;

    if (_confirmText.text.trim() != _phrase) {
      showFnToast(context, '확인 문구를 정확히 입력해 주세요.',
          type: FnToastType.error);
      return;
    }

    final ok = await showFnAlert(
      context,
      title: '정말 탈퇴하시겠어요?',
      message: '계정과 클라우드에 저장된 영수증·사업자 정보가\n모두 삭제되며 복구할 수 없습니다.',
      confirmLabel: '탈퇴하기',
      cancelLabel: '취소',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();

    Future<void> attempt() => auth.deleteAccount();

    try {
      await attempt();
    } on AuthReauthRequired {
      // 재인증 후 재시도
      try {
        if (auth.isKakaoAccount) {
          await auth.reauthenticateWithKakao();
        } else if (auth.isAppleAccount) {
          await auth.reauthenticateWithApple();
        } else if (auth.isGoogleAccount) {
          await auth.reauthenticateWithGoogle();
        } else {
          if (_pw.text.isEmpty) {
            if (!mounted) return;
            setState(() => _busy = false);
            showFnToast(context, '보안을 위해 비밀번호를 입력해 주세요.',
                type: FnToastType.error);
            return;
          }
          await auth.reauthenticateWithPassword(_pw.text);
        }
        await attempt();
      } catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        showFnToast(context, '재인증에 실패했습니다. 다시 시도해 주세요.',
            type: FnToastType.error);
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFnToast(context, auth.error ?? '탈퇴 처리 중 오류가 발생했습니다.',
          type: FnToastType.error);
      auth.clearError();
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    // 로그아웃 상태가 되면 `_AppEntry` 가 스플래시로 되돌린다.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // 소셜 계정(구글/애플)은 비밀번호가 없으므로 비밀번호 입력칸을 숨긴다.
    final isSocial = auth.isSocialAccount;

    return FnShell(
      navTitle: '회원 탈퇴',
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FnColors.statusNegativeBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '탈퇴하면 아래 정보가 모두 삭제됩니다',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: FnColors.rose30,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '· 계정 정보 (이메일, 이름)\n'
                    '· 사업자 정보 (상호명, 사업자번호, 대표자, 주소)\n'
                    '· 클라우드에 백업된 영수증 내역\n'
                    '· 약관 동의 이력',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      height: 1.7,
                      color: FnColors.labelNeutral,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!isSocial) ...[
              FnDsTextField(
                label: '비밀번호 확인',
                controller: _pw,
                placeholder: '현재 비밀번호',
                obscureText: true,
                helper: '보안을 위해 다시 한 번 확인합니다.',
              ),
              const SizedBox(height: 14),
            ],
            FnDsTextField(
              label: '확인 문구',
              controller: _confirmText,
              placeholder: _phrase,
              helper: "정확히 '$_phrase' 라고 입력해 주세요.",
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(child: FnSpinner())
            else
              FnDsButton(
                label: '탈퇴하기',
                expand: true,
                background: FnColors.statusNegative,
                foreground: Colors.white,
                disabled: _confirmText.text.trim() != _phrase,
                onPressed: _submit,
              ),
            const SizedBox(height: 10),
            Center(
              child: FnDsButton(
                label: '취소하고 돌아가기',
                variant: FnDsButtonVariant.text,
                size: FnDsButtonSize.small,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 스플래시/프로필에서 공통으로 쓰는 "준비 중" 안내
void showFnComingSoon(BuildContext context, String what) {
  HapticFeedback.selectionClick();
  showFnToast(context, '$what 로그인은 준비 중이에요.\n이메일 또는 구글로 시작해 주세요.');
}
