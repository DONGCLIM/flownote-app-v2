import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_brand.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_tokens.dart';
import '../../providers/auth_provider.dart';
import 'auth_ds_screens.dart';
import '../../services/firebase_status.dart';
import '../../services/kakao_config.dart';
import '../../services/pwa_install.dart';
import 'add_to_home_sheet.dart';
import 'auth_unavailable_banner.dart';
import 'legal_doc_ds_screen.dart';

/// 시안 `AppH4` → `screen === 'splash'` 1:1 포팅 (가입 · 간편 로그인).
///
/// ```js
/// Shell { navTitle: '' }
///   div { height:'100%', column, justifyContent:center, padding:24, gap:16 }
///     div { column, alignItems:center, gap:10, marginBottom:14 }
///       img fnLogo 84x84 r22 shadow '0 6px 18px rgba(238,118,134,.22)' mb14
///     div 33/700 font-brand blue-50 ls-0.03em center 'FlowNote'
///     div 15/400 label-neutral center lh1.5 '꽃집 사장님을 위한 영수증 매입 정산 노트'
///     TextField '이메일'   placeholder 'shop@flownote.kr'
///     TextField '비밀번호' placeholder '••••••••'
///     Button large '가입하기'                       → business
///     div { row, alignItems:center, gap:10, margin:'4px 0' }
///       span flex1 h1 line-normal-neutral
///       span 12 label-assistive 'SNS 계정으로 간편 시작'
///       span flex1 h1 line-normal-neutral
///     div { row, gap:10 } → SNS.map(카드)
/// ```
class SplashDsScreen extends StatefulWidget {
  const SplashDsScreen({super.key});

  @override
  State<SplashDsScreen> createState() => _SplashDsScreenState();
}

/// 시안 `SNS` 배열 (`05fd03e0.js` @8)
/// ```js
/// [ { name:'카카오', bg:'#FEE500', logo:<말풍선 #3C1E1E> },
///   { name:'네이버', bg:'#03C75A', logo:<N #fff> },
///   { name:'구글',   bg:'#fff',   dsIcon:'IconColorLogoGoogleNameLogoGoogle' } ]
/// ```
enum _Sns { kakao, naver, google, apple }

class _SplashDsScreenState extends State<SplashDsScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 🔴 카카오 웹 로그인 리다이렉트가 실패했으면 그 사유를 보여준다.
    //
    // 웹 카카오 로그인은 페이지가 통째로 카카오로 갔다 돌아온다. 실패하면
    // `AuthProvider.init()` 이 `error` 에 사유를 담아두는데, 그 시점엔
    // 화면이 아직 없어서 토스트를 띄울 수 없다. 그래서 로그인 화면이
    // 처음 그려질 때 여기서 꺼내 보여준다.
    //
    // 이걸 안 하면 사장님 입장에서는 "카카오 눌렀는데 아무 일도 없이
    // 로그인 화면으로 되돌아왔다" 로만 보인다 — 원인을 감추는 셈이다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final msg = auth.error;
      if (msg == null || msg.isEmpty) return;
      showFnToast(context, msg,
          type: FnToastType.error, duration: const Duration(seconds: 6));
      auth.clearError();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 이 기기에서 보여줄 SNS 목록.
  ///
  /// 애플 로그인은 iOS/macOS 에서만 동작하므로 안드로이드에서는 숨긴다.
  /// (반대로 iOS 에서 소셜 로그인을 제공하면서 애플 로그인이 없으면
  ///  App Store 심사에서 반려된다 — 가이드라인 4.8)
  List<_Sns> get _visibleSns => [
        _Sns.kakao,
        _Sns.naver,
        _Sns.google,
        if (context.read<AuthProvider>().isAppleSignInSupported) _Sns.apple,
      ];

  /// 시안의 SNS 카드.
  /// - 카카오 / 구글 / 애플: 실제 로그인 수행
  /// - 네이버: 아직 키 발급 전이므로 준비 중 안내
  Future<void> _sns(_Sns s) async {
    if (s == _Sns.naver) {
      showFnComingSoon(context, '네이버');
      return;
    }
    // 카카오 키가 주입되지 않은 빌드(개발용 등)에서는 로그인을 시도하지
    // 않는다. 시도하면 카카오 서버가 거절해서 "로그인 실패" 만 뜨는데,
    // 사용자는 자기 계정 문제로 오해한다.
    if (s == _Sns.kakao && !KakaoConfig.isConfigured) {
      // 웹은 네이티브 앱 키가 아니라 JavaScript 키를 써야 한다.
      // (kakao_flutter_sdk_common: `appKey => kIsWeb ? _jsKey : _nativeKey`)
      // 앱에서는 카카오 로그인이 되는데 웹에서만 안 되는 상황이므로,
      // "준비 중" 이라고만 하면 사장님이 앱 쪽도 고장난 줄 오해한다.
      if (KakaoConfig.isWebKeyMissing) {
        showFnToast(
          context,
          '웹에서는 카카오 로그인 준비가 아직 안 됐어요.\n'
          '휴대폰 앱에서는 그대로 쓰실 수 있고,\n'
          '웹에서는 이메일 또는 구글로 시작해 주세요.',
          duration: const Duration(seconds: 5),
        );
        return;
      }
      showFnComingSoon(context, '카카오');
      return;
    }

    if (_busy) return;
    // 서버가 안 붙은 상태에서 구글 계정 선택창까지 띄우면, 계정을 고른 뒤
    // 아무 일도 안 일어나는 것처럼 보인다. 사유를 먼저 알려준다.
    if (AuthUnavailableBanner.blocked) {
      showFnToast(context, FirebaseStatus.userMessage,
          type: FnToastType.error, duration: const Duration(seconds: 5));
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = switch (s) {
      _Sns.kakao => await auth.signInWithKakao(),
      _Sns.apple => await auth.signInWithApple(),
      _ => await auth.signInWithGoogle(),
    };
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      final msg = auth.error;
      if (msg != null) {
        showFnToast(context, msg, type: FnToastType.error);
        auth.clearError();
      }
      return;
    }
    _leaveAfterSuccess();
    // 성공 → `_AppEntry` 가 MainDsScreen 으로 자동 전환.
    // 사업자 정보가 없으면 홈에서 온보딩 배너로 안내한다.
  }

  /// 스플래시의 '가입하기' → 회원가입 화면 (약관 동의 포함)
  void _signUp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignUpDsScreen(
          initialEmail: _email.text.trim(),
          initialPassword: _password.text,
        ),
      ),
    );
  }

  /// 로그인 — 스플래시의 주(主) 동작.
  ///
  /// 입력칸이 비어 있으면 로그인 전용 화면으로 보내지 않고 바로 안내한다.
  /// (예전에는 화면 이동을 시켜서 "왜 가입만 되냐"는 혼란을 만들었다)
  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      showFnToast(context, '이메일과 비밀번호를 입력해 주세요.',
          type: FnToastType.error);
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(email: email, password: _password.text);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      showFnToast(context, auth.error ?? '로그인에 실패했습니다.',
          type: FnToastType.error);
      auth.clearError();
      return;
    }
    _leaveAfterSuccess();
  }

  /// 로그인 성공 후 확실하게 홈으로 보낸다.
  ///
  /// 정상 경로에서는 루트 `_AppEntry` 가 `isLoggedIn` 변화를 감지해서
  /// 스스로 MainDsScreen 으로 바꾼다. 하지만 이 화면이 **직접 push 되어**
  /// 루트 위에 얹혀 있는 경우(예: 로그아웃 직후)에는 `_AppEntry` 가 화면에
  /// 보이지 않으므로, 아무리 로그인에 성공해도 이 스플래시가 그대로 남는다.
  /// → 그 상황에서만 스스로 물러난다. (안전장치)
  void _leaveAfterSuccess() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);
  }

  void _openDoc(LegalDocKind kind) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LegalDocDsScreen(kind: kind)),
      );

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 로고(심볼) — 새 앱로고는 스쿼클이 이미 그려져 있어서
            // 따로 잘라내지 않는다. `FnAppMark` 참고.
            //
            // 요청 #116: 로그인 화면 아이콘은 글로우가 그려진 판을 쓴다.
            // 글로우가 그림에 들어 있으므로 위젯 그림자는 자동으로 꺼진다.
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: FnAppMark(size: 84, glow: true),
              ),
            ),
            const SizedBox(height: 16),
            // 텍스트로고(워드마크) — 예전에는 Pretendard 33/w700 로
            // 그린 `Text('FlowNote')` 였다. 확정된 워드마크 그림으로 바꾼다.
            // 높이 33 은 예전 글자 크기와 같게 맞춘 값이다.
            const Center(child: FnWordmark(height: 33)),
            const SizedBox(height: 16),
            const Text(
              '꽃집 사장님을 위한 영수증 매입 정산 노트',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: FnColors.labelNeutral,
              ),
            ),
            const SizedBox(height: 16),
            // 로그인 서버가 붙지 않았으면 사유를 그대로 보여준다.
            // (정상이면 아무것도 그리지 않는다)
            const AuthUnavailableBanner(),
            FnDsTextField(
              label: '이메일',
              controller: _email,
              placeholder: 'shop@flownote.kr',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            FnDsTextField(
              label: '비밀번호',
              controller: _password,
              placeholder: '••••••••',
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: FnSpinner(),
                ),
              )
            else ...[
              // 주 동작 = 로그인 (이미 가입한 사장님이 매일 쓰는 버튼)
              FnDsButton(
                label: '로그인',
                expand: true,
                // 서버가 안 붙었으면 눌러도 성공할 수 없다 → 비활성화해서
                // "눌렀는데 아무 일도 안 일어남" 을 원천 차단한다.
                disabled: AuthUnavailableBanner.blocked,
                onPressed: _signIn,
              ),
              const SizedBox(height: 10),
              // 보조 동작 = 회원가입 (처음 한 번만 쓰는 버튼)
              FnDsButton(
                label: '회원가입',
                expand: true,
                variant: FnDsButtonVariant.outlined,
                disabled: AuthUnavailableBanner.blocked,
                onPressed: _signUp,
              ),
            ],
            // div { row, gap:10, margin:'4px 0' }
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20), // gap16 + margin4
              child: Row(
                children: [
                  Expanded(
                      child: Divider(
                          height: 1,
                          thickness: 1,
                          color: FnColors.lineNeutral)),
                  SizedBox(width: 10),
                  Text(
                    'SNS 계정으로 간편 시작',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      color: FnColors.labelAssistive,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                      child: Divider(
                          height: 1,
                          thickness: 1,
                          color: FnColors.lineNeutral)),
                ],
              ),
            ),
            Row(
              children: [
                for (final s in _visibleSns) ...[
                  if (s != _visibleSns.first) const SizedBox(width: 10),
                  Expanded(child: _snsCard(s)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // 약관 안내 (SNS 간편 가입 시에도 동의로 간주되므로 반드시 노출)
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('가입 시 ', style: _legalStyle),
                  _legalLink('이용약관', () => _openDoc(LegalDocKind.terms)),
                  const Text(' 및 ', style: _legalStyle),
                  _legalLink(
                      '개인정보 처리방침', () => _openDoc(LegalDocKind.privacy)),
                  const Text('에 동의합니다', style: _legalStyle),
                ],
              ),
            ),

            // ── 홈 화면에 추가 안내 ─────────────────────────────────
            //
            // 🔴 왜 로그인 화면에 두는가
            //
            // 원래는 프로필 > 설정에만 있었다. 그런데 그 화면은 **로그인해야**
            // 볼 수 있다. 로그인이 막힌 상태에서 "홈화면 추가 어떻게 해?" 를
            // 물으셨는데, 정작 안내는 로그인 뒤에 숨어 있었던 것이다.
            //
            // 홈 화면 추가는 로그인과 아무 상관이 없는 기능이므로,
            // 로그인 전에도 닿을 수 있어야 한다.
            //
            // 이미 홈 화면에서 실행 중이거나 네이티브 앱이면 `shouldGuide` 가
            // false 라서 아예 그리지 않는다 — 쓸모없는 줄을 남기지 않는다.
            if (pwaState().shouldGuide) ...[
              const SizedBox(height: 14),
              Center(child: _addToHomeLink()),
            ],
          ],
        ),
      ),
    );
  }

  /// "앱처럼 쓰고 싶으세요? 홈 화면에 추가하기"
  ///
  /// 로그인 버튼들과 경쟁하지 않도록 약관 안내와 같은 급의 조용한 링크로 둔다.
  /// 이게 주된 행동은 아니지만, 찾을 수 없으면 없는 것과 같다.
  Widget _addToHomeLink() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => AddToHomeSheet.open(context),
        child: Padding(
          // 손가락으로 누를 수 있는 높이를 확보한다. 11pt 글자는
          // 그대로 두면 탭 영역이 너무 얇아서 잘 안 눌린다.
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_to_home_screen_rounded,
                  size: 15, color: FnColors.labelNeutral),
              const SizedBox(width: 5),
              Text(
                '앱처럼 쓰기 — 홈 화면에 추가',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNeutral,
                  height: 1.4,
                  decoration: TextDecoration.underline,
                  decorationColor: FnColors.labelNeutral,
                ),
              ),
            ],
          ),
        ),
      );

  static const _legalStyle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 11,
    color: FnColors.labelAssistive,
    height: 1.6,
  );

  Widget _legalLink(String text, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FnColors.labelNeutral,
            height: 1.6,
            decoration: TextDecoration.underline,
            decorationColor: FnColors.labelNeutral,
          ),
        ),
      );

  /// ```js
  /// button { flex:1, height:76, borderRadius:14,
  ///          boxShadow:'inset 0 0 0 1px line-normal-normal',
  ///          background:background-normal-normal, column, center, gap:6 }
  ///   span 34x34 r17 bg s.bg [+ inset 1px line-normal-neutral (dsIcon)] → 로고
  ///   span 12/600 label-normal → s.name
  /// ```
  Widget _snsCard(_Sns s) {
    final (String name, Color bg, bool ring) = switch (s) {
      _Sns.kakao => ('카카오', const Color(0xFFFEE500), false),
      _Sns.naver => ('네이버', const Color(0xFF03C75A), false),
      _Sns.google => ('구글', Colors.white, true),
      _Sns.apple => ('애플', const Color(0xFF000000), false),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _sns(s),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: FnColors.backgroundNormal,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FnColors.lineNormal),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: ring ? Border.all(color: FnColors.lineNeutral) : null,
              ),
              alignment: Alignment.center,
              child: CustomPaint(
                size: switch (s) {
                  _Sns.kakao => const Size(19, 19),
                  _Sns.naver => const Size(15, 15),
                  _Sns.google => const Size(19, 19),
                  _Sns.apple => const Size(17, 20),
                },
                painter: _SnsLogoPainter(s),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: FnColors.labelNormal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시안 SVG path 를 그대로 옮긴 로고 페인터.
class _SnsLogoPainter extends CustomPainter {
  _SnsLogoPainter(this.sns);

  final _Sns sns;

  @override
  void paint(Canvas canvas, Size size) {
    // 시안 SVG 는 모두 viewBox="0 0 24 24"
    final k = size.width / 24;
    canvas.scale(k, k);

    switch (sns) {
      case _Sns.kakao:
        // M12 4C7.03 4 3 7.14 3 11.02c0 2.48 1.66 4.66 4.16 5.9
        //  -.14.5-.72 2.6-.75 2.78 ... 말풍선
        final p = Path()
          ..moveTo(12, 4)
          ..cubicTo(7.03, 4, 3, 7.14, 3, 11.02)
          ..cubicTo(3, 13.5, 4.66, 15.68, 7.16, 16.92)
          ..cubicTo(7.02, 17.42, 6.44, 19.52, 6.41, 19.7)
          ..cubicTo(6.41, 19.7, 6.39, 19.83, 6.48, 19.88)
          ..cubicTo(6.57, 19.93, 6.67, 19.89, 6.67, 19.89)
          ..cubicTo(6.92, 19.86, 9.53, 18.02, 9.98, 17.7)
          ..cubicTo(10.64, 17.79, 11.31, 17.84, 12, 17.84)
          ..cubicTo(16.97, 17.84, 21, 14.7, 21, 10.82)
          ..cubicTo(21, 6.94, 16.97, 4, 12, 4)
          ..close();
        canvas.drawPath(p, Paint()..color = const Color(0xFF3C1E1E));

      case _Sns.naver:
        // M15.2 12.6 8.5 3H3v18h5.6v-9.7L15.5 21H21V3h-5.8z
        final p = Path()
          ..moveTo(15.2, 12.6)
          ..lineTo(8.5, 3)
          ..lineTo(3, 3)
          ..lineTo(3, 21)
          ..lineTo(8.6, 21)
          ..lineTo(8.6, 11.3)
          ..lineTo(15.5, 21)
          ..lineTo(21, 21)
          ..lineTo(21, 3)
          ..lineTo(15.2, 3)
          ..close();
        canvas.drawPath(p, Paint()..color = Colors.white);

      case _Sns.google:
        // DS `IconColorLogoGoogle` — 4색 G
        final blue = Paint()..color = const Color(0xFF4285F4);
        final green = Paint()..color = const Color(0xFF34A853);
        final yellow = Paint()..color = const Color(0xFFFBBC05);
        final red = Paint()..color = const Color(0xFFEA4335);
        canvas.drawPath(
          Path()
            ..moveTo(21.6, 12.23)
            ..cubicTo(21.6, 11.55, 21.54, 10.89, 21.42, 10.27)
            ..lineTo(12, 10.27)
            ..lineTo(12, 14.05)
            ..lineTo(17.46, 14.05)
            ..cubicTo(17.22, 15.32, 16.5, 16.4, 15.42, 17.12)
            ..lineTo(15.42, 19.6)
            ..lineTo(18.6, 19.6)
            ..cubicTo(20.46, 17.88, 21.6, 15.32, 21.6, 12.23)
            ..close(),
          blue,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 22)
            ..cubicTo(14.7, 22, 16.96, 21.1, 18.6, 19.6)
            ..lineTo(15.42, 17.12)
            ..cubicTo(14.52, 17.72, 13.38, 18.08, 12, 18.08)
            ..cubicTo(9.4, 18.08, 7.19, 16.33, 6.4, 13.98)
            ..lineTo(3.12, 13.98)
            ..lineTo(3.12, 16.56)
            ..cubicTo(4.75, 19.79, 8.11, 22, 12, 22)
            ..close(),
          green,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.4, 13.98)
            ..cubicTo(6.2, 13.38, 6.08, 12.7, 6.08, 12)
            ..cubicTo(6.08, 11.3, 6.2, 10.62, 6.4, 10.02)
            ..lineTo(6.4, 7.44)
            ..lineTo(3.12, 7.44)
            ..cubicTo(2.4, 8.86, 2, 10.38, 2, 12)
            ..cubicTo(2, 13.62, 2.4, 15.14, 3.12, 16.56)
            ..close(),
          yellow,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 5.92)
            ..cubicTo(13.47, 5.92, 14.78, 6.42, 15.81, 7.41)
            ..lineTo(18.66, 4.56)
            ..cubicTo(16.95, 2.97, 14.7, 2, 12, 2)
            ..cubicTo(8.11, 2, 4.75, 4.21, 3.12, 7.44)
            ..lineTo(6.4, 10.02)
            ..cubicTo(7.19, 7.67, 9.4, 5.92, 12, 5.92)
            ..close(),
          red,
        );

      case _Sns.apple:
        // Apple 로고 (흰색). 원본 좌표계 17x20 을 size 에 맞춰 정규화한다.
        final w = Paint()..color = Colors.white;
        final sx = size.width / 17.0;
        final sy = size.height / 20.0;
        canvas.save();
        canvas.scale(sx, sy);

        // 잎사귀
        canvas.drawPath(
          Path()
            ..moveTo(10.3, 3.2)
            ..cubicTo(10.9, 2.5, 11.3, 1.5, 11.2, 0.5)
            ..cubicTo(10.3, 0.5, 9.2, 1.1, 8.6, 1.8)
            ..cubicTo(8.0, 2.5, 7.6, 3.5, 7.7, 4.4)
            ..cubicTo(8.7, 4.5, 9.7, 3.9, 10.3, 3.2)
            ..close(),
          w,
        );
        // 몸통
        canvas.drawPath(
          Path()
            ..moveTo(11.2, 4.6)
            ..cubicTo(9.8, 4.5, 8.6, 5.4, 7.9, 5.4)
            ..cubicTo(7.2, 5.4, 6.2, 4.6, 5.0, 4.7)
            ..cubicTo(3.4, 4.7, 2.0, 5.9, 1.3, 7.7)
            ..cubicTo(-0.2, 11.3, 1.1, 15.9, 2.5, 18.0)
            ..cubicTo(3.2, 19.0, 4.1, 20.2, 5.2, 20.1)
            ..cubicTo(6.2, 20.1, 6.7, 19.4, 8.0, 19.4)
            ..cubicTo(9.3, 19.4, 9.6, 20.1, 10.7, 20.1)
            ..cubicTo(11.9, 20.1, 12.5, 19.0, 13.3, 17.9)
            ..cubicTo(14.0, 16.7, 14.4, 15.5, 14.4, 15.4)
            ..cubicTo(14.4, 15.4, 12.1, 14.5, 12.1, 12.0)
            ..cubicTo(12.1, 9.8, 13.9, 8.7, 14.0, 8.7)
            ..cubicTo(13.0, 7.2, 11.4, 7.0, 11.2, 4.6)
            ..close(),
          w,
        );
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SnsLogoPainter old) => old.sns != sns;
}
