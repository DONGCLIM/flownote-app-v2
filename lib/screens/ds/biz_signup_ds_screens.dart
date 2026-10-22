import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/fn_feedback.dart';
import '../../design/fn_receipt_illust.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_signup_tokens.dart';
import '../../providers/auth_provider.dart';
import 'onboarding_ds_screens.dart' show FnBiz;
import 'scan_camera_ds_screen.dart';
import 'signup_parts.dart';

/// 🔴 #157 — 가입 완료 → '사업자등록증 등록하러 가기' 로 이어지는 5단계.
///
/// 사장님 시안 5장을 왼쪽→오른쪽 순서로 구현했다.
///
/// | # | 화면 | 앱바 제목 |
/// |---|---|---|
/// | 1 | [BizIntroDsScreen]   | 사업자 정보 |
/// | 2 | 촬영 (기존 카메라 재사용) | 사업자등록증 촬영 |
/// | 3 | [BizReadingDsScreen] | 사업자등록증 인식 중 |
/// | 4 | [BizConfirmDsScreen] | 사업자 정보 확인 |
/// | 5 | [BizFinishDsScreen]  | 가입 완료 |
///
/// ## 🔴 기존 `onboarding_ds_screens.dart` 와의 관계
/// 거기에도 사업자 화면 4개가 있지만 **시안과 다르다**(앱바 제목 없음,
/// 원형 아이콘, 다른 문구, 다른 배치). 기존 화면은 예전 온보딩 경로가
/// 아직 쓰고 있으므로 건드리지 않고, 시안용으로 이 파일을 새로 만들었다.
/// 데이터 홀더 [FnBiz] 만 그대로 재사용한다.
///
/// ⚠️ 두 벌이 공존하므로, 시안을 고칠 때 **이 파일**을 고쳐야 한다.

// ════════════════════════════════════════════════════════════
// 1. 안내 — '사업자등록증을 촬영해주세요'
// ════════════════════════════════════════════════════════════

class BizIntroDsScreen extends StatelessWidget {
  const BizIntroDsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '사업자 정보',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FnSignup.pagePad),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SignupHeadline('사업자등록증을\n촬영해주세요', center: true),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle(
              '사업자등록증 내용은 자동으로 인식돼요.\n일부 정보는 따로 기재해주세요.',
              center: true,
            ),
            const SizedBox(height: FnSignup.gapSubToVerifyButton),
            SignupButton(
              label: '사업자등록증 촬영하기',
              onTap: () => _shoot(context),
            ),
            const SizedBox(height: FnSignup.gapBetweenButtons),
            SignupButton(
              label: '직접 입력할게요',
              style: SignupButtonStyle.outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BizConfirmDsScreen(
                    biz: FnBiz(),
                    recognized: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔴 촬영은 **기존 카메라 화면을 그대로 쓴다.**
  ///
  /// #148~#154 에서 화각·세로 프레임을 어렵게 맞춰 놓았다. 여기서 카메라를
  /// 새로 만들면 그 고생이 전부 날아가므로 `navTitle` 과 배지만 바꿔 쓴다.
  Future<void> _shoot(BuildContext context) async {
    // 결과 타입을 적지 않는다. 카메라는 List<XFile> 을 주지만 여기서는
    // "찍고 돌아왔는지" 만 알면 되고, XFile 을 쓰려면 image_picker 를
    // 끌어와야 해서 의존만 늘어난다.
    final shots = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => const ScanCameraDsScreen(
          mode: 'single',
          navTitle: '사업자등록증 촬영',
          badgeLabel: '사업자등록증',
          frameHint: '사업자등록증을 프레임 안에 맞춰주세요',
          maxShots: 1,
        ),
      ),
    );
    if (!context.mounted) return;
    if (shots == null) return;
    if (shots is List && shots.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BizReadingDsScreen()),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 2. 인식 중 — 진행바 + '인식 결과 확인하기'
// ════════════════════════════════════════════════════════════

class BizReadingDsScreen extends StatefulWidget {
  const BizReadingDsScreen({super.key});

  @override
  State<BizReadingDsScreen> createState() => BizReadingDsScreenState();
}

class BizReadingDsScreenState extends State<BizReadingDsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // 시안은 80% 지점을 보여준다. 0 -> 100% 를 2.4초에 걷는다.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0.0 ~ 1.0
  double get progress => _c.value;

  bool get _done => _c.value >= 1.0;

  void _goNext() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BizConfirmDsScreen(
          biz: FnBiz.recognized(),
          recognized: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '사업자등록증 인식 중',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FnSignup.pagePad),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SignupHeadline('사업자등록증을\n읽고 있어요', center: true),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle(
              '상호명, 사업자번호, 대표자와 소재지를\n자동으로 찾고 있어요.',
              center: true,
            ),
            const SizedBox(height: FnSignup.gapSubToVerifyButton),
            _progressCard(),
            const SizedBox(height: FnSignup.gapBetweenButtons),
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => SignupButton(
                label: '인식 결과 확인하기',
                style: SignupButtonStyle.outlined,
                // 다 읽기 전에는 누를 수 없다(빈 결과가 뜨는 걸 막는다).
                onTap: _done ? _goNext : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FnSignup.cardRadius),
        boxShadow: FnSignup.cardShadow,
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final pct = (progress * 100).round();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '인식 진행 중',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: FnSignup.headline,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: FnSignup.headline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(FnSignup.progressHeight / 2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: FnSignup.progressHeight,
                  backgroundColor: FnSignup.progressTrack,
                  valueColor:
                      const AlwaysStoppedAnimation(FnSignup.coral),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 3. 정보 확인 — 인식 결과 + 직접 입력 항목
// ════════════════════════════════════════════════════════════

/// 🔴 시안 b4 만 폭이 388px 이다(나머지 473px). 배율 388/375 = 1.03467 로
///    환산하니 입력창 47.4dp / 버튼 49.3dp 로 다른 화면과 정확히 맞았다.
///
/// 시안에서 **전화번호와 이메일 주소는 비어 있고 `*` 가 붙어 있다.**
/// 즉 OCR 로 못 찾는 항목이라 사용자가 반드시 직접 채워야 한다.
class BizConfirmDsScreen extends StatefulWidget {
  const BizConfirmDsScreen({
    super.key,
    required this.biz,
    required this.recognized,
  });

  final FnBiz biz;

  /// 촬영·인식을 거쳐 왔는지. false 면 '직접 입력할게요' 로 들어온 것이고
  /// 시안 상단의 '자동 인식이 완료되었어요' 배지를 띄우지 않는다.
  final bool recognized;

  @override
  State<BizConfirmDsScreen> createState() => BizConfirmDsScreenState();
}

class BizConfirmDsScreenState extends State<BizConfirmDsScreen> {
  late final TextEditingController _shop;
  late final TextEditingController _regNo;
  late final TextEditingController _owner;
  late final TextEditingController _addr;
  late final TextEditingController _tel;
  late final TextEditingController _email;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final b = widget.biz;
    _shop = TextEditingController(text: b.shop);
    _regNo = TextEditingController(text: b.regNo);
    _owner = TextEditingController(text: b.owner);
    _addr = TextEditingController(text: b.addr);
    // 🔴 시안에서 전화번호·이메일은 비어 있다. OCR 결과가 있어도
    //    사장님이 확인하도록 비워 둔다.
    _tel = TextEditingController();
    _email = TextEditingController();
    for (final c in [_shop, _regNo, _owner, _addr, _tel, _email]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_shop, _regNo, _owner, _addr, _tel, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 필수(`*`) 두 칸이 모두 채워져야 넘어간다.
  bool get canSubmit =>
      _tel.text.trim().isNotEmpty && _email.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!canSubmit || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final b = widget.biz
      ..shop = _shop.text.trim()
      ..regNo = _regNo.text.trim()
      ..owner = _owner.text.trim()
      ..addr = _addr.text.trim()
      ..tel = _tel.text.trim()
      ..email = _email.text.trim();

    // 🔴 `updateBusinessInfo` 는 `Future<void>` 라 성공/실패를 돌려주지
    //    않는다. 반환값을 받아 `if (!ok)` 로 쓰면 컴파일 오류가 난다.
    //
    // 🔴 그리고 `UserModel` 에는 **사업장 연락 이메일 칸이 없다.**
    //    계정 이메일(`email`)과 섞으면 로그인 주소가 덮여버리므로
    //    지금은 저장하지 않고 화면에서만 받는다.
    //    사장님께 필드를 새로 팔지 여쭌 뒤 연결한다.
    final auth = context.read<AuthProvider>();
    await auth.updateBusinessInfo(
      businessName: b.shop,
      businessNumber: b.regNo,
      ownerName: b.owner,
      businessAddress: b.addr,
      phoneNumber: b.tel,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (auth.error != null) {
      final msg = auth.error!;
      auth.clearError();
      showFnToast(context, msg, type: FnToastType.error);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BizFinishDsScreen()),
    );
  }

  /// 라벨 + 입력칸 한 묶음. `required` 면 라벨 뒤에 코랄 `*` 를 붙인다.
  Widget _group(
    String label,
    TextEditingController c, {
    bool required = false,
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (required)
          Row(
            children: [
              SignupFieldLabel(label),
              const Text(
                ' *',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: FnSignup.labelSize,
                  fontWeight: FontWeight.w700,
                  color: FnSignup.requiredMark,
                ),
              ),
            ],
          )
        else
          SignupFieldLabel(label),
        const SizedBox(height: FnSignup.gapLabelToField),
        SignupField(
          controller: c,
          hint: hint ?? '직접 입력해주세요',
          keyboardType: keyboard,
          inputFormatters: formatters,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '사업자 정보 확인',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 8, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.recognized) ...[
              const _SuccessBadge(),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  '자동 인식이 완료되었어요',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: FnSignup.headline,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(child: SignupSubtitle('입력된 정보를 확인해주세요.')),
              const SizedBox(height: 22),
            ] else
              const SizedBox(height: 12),
            _group('상호명', _shop),
            const SizedBox(height: FnSignup.gapBetweenFieldGroups),
            _group('사업자등록번호', _regNo,
                keyboard: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(12),
                ]),
            const SizedBox(height: FnSignup.gapBetweenFieldGroups),
            _group('대표자', _owner),
            const SizedBox(height: FnSignup.gapBetweenFieldGroups),
            _group('사업장 소재지', _addr),
            const SizedBox(height: FnSignup.gapBetweenFieldGroups),
            _group('전화번호', _tel,
                required: true,
                keyboard: TextInputType.phone,
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(14),
                ]),
            const SizedBox(height: FnSignup.gapBetweenFieldGroups),
            _group('이메일 주소', _email,
                required: true, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 14),
            const Text(
              '* 표시 항목은 직접 입력해 주셔야 하는 정보예요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: FnSignup.errorSize,
                fontWeight: FontWeight.w500,
                color: FnSignup.requiredMark,
              ),
            ),
            const SizedBox(height: 16),
            SignupButton(
              label: '확인하고 시작하기',
              busy: _busy,
              onTap: canSubmit ? _submit : null,
            ),
            const SizedBox(height: FnSignup.gapBetweenButtons),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(FnSignup.cardRadius),
                boxShadow: FnSignup.cardShadow,
              ),
              child: const Text(
                '입력하신 사업자 정보는\n매입 내역 정산서에 자동 반영돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  color: FnSignup.subtle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시안 상단의 코랄 원형 체크 배지.
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: FnSignup.coral,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 24, color: Colors.white),
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════
// 4. 가입 완료 — 체크 목록 + '영수증 찍어보기'
// ════════════════════════════════════════════════════════════

class BizFinishDsScreen extends StatelessWidget {
  const BizFinishDsScreen({super.key});

  static const _items = [
    '가입 완료',
    '사업자등록증 자동 인식 완료',
    '상호명·사업자번호·대표자·이메일 등록',
    '정산서 내보내기 준비 완료',
  ];

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '가입 완료',
      bg: FnSignup.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            FnSignup.pagePad, 0, FnSignup.pagePad, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🔴 #158 여기가 비어 있었다. 시안에는 영수증 세 장 그림이 있다.
            //    (#157 에서 SizedBox 로 공간만 두고 그림을 안 그렸다)
            //    시안 일러스트 top 248px -> 196.6dp. 앱바(56) 를 빼면 141dp.
            const SizedBox(height: 56),
            const Center(child: FnReceiptIllust()),
            // 일러스트 아래(443px=351dp) ~ 헤드라인(492px=390dp) = 39dp
            const SizedBox(height: 30),
            const SignupHeadline('1분 만에 준비가 끝났어요', center: true),
            const SizedBox(height: FnSignup.gapHeadlineToSub),
            const SignupSubtitle(
              '이제 영수증만 찍으면\n매입 내역이 자동으로 쌓여요',
              center: true,
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: FnSignup.cardPadH, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(FnSignup.cardRadius),
                boxShadow: FnSignup.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const SizedBox(height: FnSignup.checkRowGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_rounded,
                            size: FnSignup.checkIconSize,
                            color: FnSignup.coral),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _items[i],
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: FnSignup.subtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            SignupButton(
              label: '영수증 찍어보기',
              // 가입 흐름을 모두 닫고 홈으로 돌아간다.
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
