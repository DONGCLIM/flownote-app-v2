import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_badge_ds.dart';
import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_tokens.dart';
import '../../providers/auth_provider.dart';

/// 시안 `AppH4` 온보딩 6화면 1:1 포팅.
///
/// splash → business → biz-camera → biz-processing → biz-review → done
///
/// 시안은 단일 컴포넌트의 `screen` 상태로 전환하지만, Flutter 에서는
/// 화면별 라우트로 나누고 `FnBiz` 로 입력값을 물려준다.

/// 시안 `biz` state: `{ shop, regNo, owner, addr, tel, email }`
class FnBiz {
  FnBiz({
    this.shop = '',
    this.regNo = '',
    this.owner = '',
    this.addr = '',
    this.tel = '',
    this.email = '',
  });

  String shop;
  String regNo;
  String owner;
  String addr;
  String tel;
  String email;

  /// 시안 `직접 입력할게요` 분기 — 상호명만 채워 넣는다.
  factory FnBiz.manual() => FnBiz(shop: '플로우노트 김사장 꽃집');

  /// 시안 `biz-processing` 의 OCR 인식 결과 (데모 고정값)
  factory FnBiz.recognized() => FnBiz(
        shop: '플로우노트 김사장 꽃집',
        regNo: '123-45-67890',
        owner: '김민준',
        addr: '서울특별시 서초구 방배로 12',
        tel: '02-1234-5678',
        email: '',
      );
}

// ════════════════════════════════════════════════════════════
// 1. business — 사업자 정보 안내
// ════════════════════════════════════════════════════════════
/// ```js
/// Shell { navTitle:'사업자 정보', onBack: → splash }
///   div { height:100%, padding:20, column, justifyContent:center,
///         gap:24, alignItems:center, textAlign:center }
///     heading2 '사업자등록증을 촬영해주세요'
///     div 56x56 r28 bg blue-95 + Icon Camera 26
///     body2-normal label-alternative 400
///       '사업자등록증 내용은 자동으로 인식됩니다.' <br> '일부 정보는 따로 기재해주세요'
///     div { width:100%, column, gap:16 }
///       Button large '사업자등록증 촬영하기'   → biz-camera
///       Button large text '직접 입력할게요'    → biz-review (shop 만 채움)
/// ```
class BusinessDsScreen extends StatelessWidget {
  const BusinessDsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '사업자 정보',
      onBack: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '사업자등록증을 촬영해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.36,
                color: FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: FnColors.rose95,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.photo_camera,
                  size: 26, color: FnColors.rose50),
            ),
            const SizedBox(height: 24),
            const Text(
              '사업자등록증 내용은 자동으로 인식됩니다.\n일부 정보는 따로 기재해주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: FnColors.labelAlternative,
              ),
            ),
            const SizedBox(height: 24),
            FnDsButton(
              label: '사업자등록증 촬영하기',
              expand: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BizCameraDsScreen()),
              ),
            ),
            const SizedBox(height: 16),
            FnDsButton(
              label: '직접 입력할게요',
              variant: FnDsButtonVariant.text,
              expand: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BizReviewDsScreen(biz: FnBiz.manual()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 2. biz-camera — 촬영
// ════════════════════════════════════════════════════════════
/// ```js
/// Shell { navTitle:'', onBack: → business, bg:'var(--cool-neutral-10)' }
///   div { height:100%, column, justifyContent:space-between,
///         color:static-white, padding:'20px 20px 32px' }
///     ContentBadge accent { alignSelf:center,
///       background:'rgba(242,104,122,.3)', color:'#FFC9CE' } '사업자등록증'
///     div { flex:1, margin:'20px 0', border:'2px dashed rgba(255,255,255,.5)',
///           r16, center, color:'rgba(255,255,255,.6)', fontSize:14 }
///       '사업자등록증을 프레임 안에 맞춰주세요'
///     button 72x72 r36 bg static-white border '4px solid rgba(255,255,255,.4)'
/// ```
class BizCameraDsScreen extends StatelessWidget {
  const BizCameraDsScreen({super.key});

  /// `--cool-neutral-10` — 촬영 화면 배경(짙은 회색)
  static const _coolNeutral10 = Color(0xFF1B1D22);

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '',
      onBack: () => Navigator.of(context).maybePop(),
      bg: _coolNeutral10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          children: [
            // ContentBadge accent — style override (시안 alignSelf:'center')
            Center(
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: const Color(0x4DF2687A), // rgba(242,104,122,.3)
                  borderRadius: BorderRadius.circular(6),
                ),
                // NOTE: `alignment` 를 주면 Container 가 최대 폭으로 늘어난다.
                //       시안은 alignSelf:center 이므로 내용 크기만 차지해야 한다.
                child: const Text(
                  '사업자등록증',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.385,
                    color: Color(0xFFFFC9CE),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CustomPaint(
                  painter: _DashedBorderPainter(
                    color: const Color(0x80FFFFFF), // rgba(255,255,255,.5)
                    radius: 16,
                    strokeWidth: 2,
                  ),
                  child: const Center(
                    child: Text(
                      '사업자등록증을 프레임 안에 맞춰주세요',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0x99FFFFFF), // rgba(255,255,255,.6)
                      ),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => const BizProcessingDsScreen()),
              ),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x66FFFFFF), // rgba(255,255,255,.4)
                    width: 4,
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

/// `border: 2px dashed` 재현 — Flutter 기본 Border 는 점선을 못 그린다.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  static const double dash = 7;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var pos = 0.0;
      while (pos < metric.length) {
        final next = (pos + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(pos, next), paint);
        pos = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ════════════════════════════════════════════════════════════
// 3. biz-processing — 인식 중
// ════════════════════════════════════════════════════════════
/// ```js
/// Shell { navTitle:'' }
///   div { height:100%, column, center, gap:20, padding:24 }
///     Circular size 40
///     heading2 600 '사업자등록증을 읽고 있어요'
///     div width:100% → ProgressBar value 80
///     Button text '인식 결과 확인하기 →'   → biz-review (인식 결과 주입)
/// ```
class BizProcessingDsScreen extends StatefulWidget {
  const BizProcessingDsScreen({super.key});

  @override
  State<BizProcessingDsScreen> createState() => _BizProcessingDsScreenState();
}

class _BizProcessingDsScreenState extends State<BizProcessingDsScreen> {
  @override
  void initState() {
    super.initState();
    // 시안은 버튼을 눌러 넘어가지만, 실제 앱에서는 인식이 끝나면 자동 진행한다.
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _next();
    });
  }

  void _next() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BizReviewDsScreen(biz: FnBiz.recognized()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: FnCircular(size: 40)),
            const SizedBox(height: 20),
            const Text(
              '사업자등록증을 읽고 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 20),
            const FnProgressBar(value: 80),
            const SizedBox(height: 20),
            FnDsButton(
              label: '인식 결과 확인하기 →',
              variant: FnDsButtonVariant.text,
              expand: true,
              onPressed: _next,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 4. biz-review — 인식 결과 확인
// ════════════════════════════════════════════════════════════
/// ```js
/// Shell { navTitle:'인식 결과 확인', onBack: → business }
///   div { padding:20, column, gap:12 }
///     ContentBadge positive '자동 인식 완료 · 4개 항목'
///     TextField '상호명' / '사업자등록번호' / '대표자' / '사업장 소재지'
///     TextField '* 전화번호'    placeholder '직접 입력해주세요'
///     TextField '* 이메일 주소' placeholder '직접 입력해주세요'
///     div body2-normal fn-rose-40 marginTop:-4 600 14
///       '* 표시 항목은 직접 입력해 주셔야 하는 정보예요.'
///     Button large '확인하고 시작하기'   → done
///     div { bg fn-rose-99, border 1px fn-rose-95, r12, pad '12px 14px' }
///       '입력하신 사업자 정보는' <br> '매입 내역 정산서에 자동 반영돼요.'
/// ```
class BizReviewDsScreen extends StatefulWidget {
  const BizReviewDsScreen(
      {super.key, required this.biz, this.editMode = false});

  final FnBiz biz;

  /// `false`(기본) → 온보딩 흐름. 확인하면 `done` 화면으로 진행.
  /// `true`        → 프로필 › '사업자 정보 수정' 진입. 저장 후 그대로 pop.
  final bool editMode;

  /// 프로필 › 사업자 정보 수정 진입점.
  /// 저장된 사업자 정보를 채워서 편집 모드로 띄운다.
  static Future<bool> openEdit(BuildContext context) async {
    final u = context.read<AuthProvider>().currentUser;
    final r = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BizReviewDsScreen(
          editMode: true,
          biz: FnBiz(
            shop: u?.businessName ?? '',
            regNo: u?.businessNumber ?? '',
            owner: u?.ownerName ?? '',
            addr: u?.businessAddress ?? '',
            tel: u?.phoneNumber ?? '',
            email: u?.email ?? '',
          ),
        ),
      ),
    );
    return r ?? false;
  }

  @override
  State<BizReviewDsScreen> createState() => _BizReviewDsScreenState();
}

class _BizReviewDsScreenState extends State<BizReviewDsScreen> {
  late final _shop = TextEditingController(text: widget.biz.shop);
  late final _regNo = TextEditingController(text: widget.biz.regNo);
  late final _owner = TextEditingController(text: widget.biz.owner);
  late final _addr = TextEditingController(text: widget.biz.addr);
  late final _tel = TextEditingController(text: widget.biz.tel);
  late final _email = TextEditingController(text: widget.biz.email);

  @override
  void dispose() {
    for (final c in [_shop, _regNo, _owner, _addr, _tel, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 자동 인식된 항목 수 (시안은 '4개 항목' 고정, 실제 값에 맞춰 센다)
  int get _recognized => [
        _shop.text,
        _regNo.text,
        _owner.text,
        _addr.text,
      ].where((s) => s.trim().isNotEmpty).length;

  /// 시안: '확인하고 시작하기' → done.
  /// 게스트 세션 생성/저장은 done 화면의 마지막 버튼에서 수행한다
  /// (여기서 로그인하면 `_AppEntry` 가 즉시 MainDsScreen 으로 교체된다).
  FnBiz get _current => FnBiz(
        shop: _shop.text.trim(),
        regNo: _regNo.text.trim(),
        owner: _owner.text.trim(),
        addr: _addr.text.trim(),
        tel: _tel.text.trim(),
        email: _email.text.trim(),
      );

  Future<void> _confirm() async {
    // 편집 모드(프로필 › 사업자 정보 수정): 바로 저장하고 pop.
    if (widget.editMode) {
      final b = _current;
      await context.read<AuthProvider>().updateBusinessInfo(
            businessName: b.shop,
            businessNumber: b.regNo,
            ownerName: b.owner,
            businessAddress: b.addr,
            phoneNumber: b.tel,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사업자 정보를 저장했어요')),
      );
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingDoneDsScreen(biz: _current),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: widget.editMode ? '사업자 정보 수정' : '인식 결과 확인',
      onBack: () => Navigator.of(context).maybePop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.editMode)
              Align(
                alignment: Alignment.centerLeft,
                child: FnBadge(
                  '자동 인식 완료 · $_recognized개 항목',
                  color: FnBadgeColor.positive,
                ),
              ),
            const SizedBox(height: 12),
            FnDsTextField(label: '상호명', controller: _shop),
            const SizedBox(height: 12),
            FnDsTextField(label: '사업자등록번호', controller: _regNo),
            const SizedBox(height: 12),
            FnDsTextField(label: '대표자', controller: _owner),
            const SizedBox(height: 12),
            FnDsTextField(label: '사업장 소재지', controller: _addr),
            const SizedBox(height: 12),
            FnDsTextField(
              label: '* 전화번호',
              controller: _tel,
              placeholder: '직접 입력해주세요',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            FnDsTextField(
              label: '* 이메일 주소',
              controller: _email,
              placeholder: '직접 입력해주세요',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8), // gap12 + marginTop:-4
            const Text(
              '* 표시 항목은 직접 입력해 주셔야 하는 정보예요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: FnColors.rose40,
              ),
            ),
            const SizedBox(height: 12),
            FnDsButton(
              label: widget.editMode ? '저장하기' : '확인하고 시작하기',
              expand: true,
              onPressed: _confirm,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: FnColors.rose99,
                border: Border.all(color: FnColors.rose95),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '입력하신 사업자 정보는\n매입 내역 정산서에 자동 반영돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: FnColors.labelNormal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 5. done — 준비 완료
// ════════════════════════════════════════════════════════════
/// ```js
/// items = ['가입 완료', '사업자등록증 자동 인식 완료',
///          '상호명·사업자번호·대표자·이메일 주소 등록', '정산서 내보내기 준비 완료']
/// Shell { navTitle:'' }
///   div { height:100%, column, justifyContent:center, padding:24, gap:16, center }
///     div 64x64 r32 bg green-95, fontSize 30, color green-50, '✓'
///     heading2 '1분 만에 준비 끝났어요'
///     body2-normal label-alternative 600
///       '이제 영수증만 찍으면 매입내역이 자동으로 쌓여요'
///     Card bordered textAlign:left → items.map('✓ ' + t) pad'6px 0' 14
///     Button large '영수증 찍어보기'
/// ```
class OnboardingDoneDsScreen extends StatelessWidget {
  const OnboardingDoneDsScreen({super.key, this.biz});

  final FnBiz? biz;

  /// 사업자 정보 저장 → 메인.
  ///
  /// 이 화면에 도달했다면 이미 회원가입/로그인이 끝난 상태이므로
  /// 별도의 세션 생성은 하지 않는다. (게스트 모드 제거)
  Future<void> _start(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final b = biz;
    if (b != null) {
      await auth.updateBusinessInfo(
        businessName: b.shop,
        businessNumber: b.regNo,
        ownerName: b.owner,
        businessAddress: b.addr,
        phoneNumber: b.tel,
      );
    }
    if (!context.mounted) return;
    // 🔴 MainDsScreen 을 직접 push 하지 않는다.
    //
    // 루트 `_AppEntry` 가 이미 `isLoggedIn == true` 를 보고 MainDsScreen 을
    // 그리고 있다. 여기서 또 push 하면 홈이 두 겹으로 쌓이고, 더 나쁜 것은
    // `(r) => false` 가 루트의 `_AppEntry` 를 없애버려서 이후 로그아웃/
    // 재로그인 때 화면 전환이 완전히 멈춘다.
    // → 온보딩 스택만 걷어내고 루트로 돌아가면 홈이 그대로 나온다.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  static const _items = [
    '가입 완료',
    '사업자등록증 자동 인식 완료',
    '상호명·사업자번호·대표자·이메일 주소 등록',
    '정산서 내보내기 준비 완료',
  ];

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: FnColors.leaf95,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '✓',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 30,
                    height: 1,
                    color: FnColors.leaf50,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '1분 만에 준비 끝났어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: FnColors.labelNormal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '이제 영수증만 찍으면 매입내역이 자동으로 쌓여요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: FnColors.labelAlternative,
              ),
            ),
            const SizedBox(height: 16),
            FnCard(
              bordered: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in _items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '✓ $t',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          height: 1.5,
                          color: FnColors.labelNormal,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FnDsButton(
              label: '영수증 찍어보기',
              expand: true,
              onPressed: () => _start(context),
            ),
          ],
        ),
      ),
    );
  }
}
