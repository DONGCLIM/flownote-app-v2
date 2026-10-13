import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_button.dart';
import '../../providers/auth_provider.dart';
import '../../services/pwa_install.dart';
import '../../services/subscription_service.dart';
import 'add_to_home_sheet.dart';
import 'auth_ds_screens.dart';
import 'legal_doc_ds_screen.dart';
import 'onboarding_ds_screens.dart';
import 'paywall_ds_screen.dart';
import 'notification_settings_ds_screen.dart';

/// 시안 `AppH7 / screen === 'profile'` 1:1 포팅
///
/// ```
/// Shell(navTitle:'프로필', tabs, activeTab:'profile')
///   div p16 column gap:14
///     Card bordered  ── 사업자 정보 (접이식)
///       header: '사업자 정보 ▾'  /  [Badge accent '전자세금계산서 연동용'] [chevron]
///       open이면 info 7행: [key label-alternative] [value 600 right]  padding '10px 0' 15
///     div ── '계정/서비스 관리' 13/700 blue-50, padding '0 4px 6px'
///       ListCell × 3 (divider는 마지막 제외), trailing chevron 14
///     div ── '고객 지원 및 안내' 13/700 green-50
///       ListCell × 4
///     Button variant:text color:assistive  '로그아웃'
/// ```
class ProfileDsScreen extends StatefulWidget {
  const ProfileDsScreen({super.key});

  @override
  State<ProfileDsScreen> createState() => _ProfileDsScreenState();
}

class _ProfileDsScreenState extends State<ProfileDsScreen> {
  bool _bizOpen = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final u = auth.currentUser;

    // 사업자 정보.
    //
    // 🔴 값이 없을 때 예시값(`123-45-67890`, `김민준`, `서울특별시 서초구
    //    방배로 12` …)을 보여주면 안 된다. 사용자는 자기가 입력한 정보라고
    //    믿게 되고, 정작 정산서를 내보낼 때 "사업자 정보가 없다" 는 말을
    //    들으면 앱이 고장난 것처럼 보인다.
    //    실제로 저장된 값은 전원 빈 문자열이었는데도 화면은 멀쩡해 보였다.
    //    비어 있으면 비어 있다고 말한다.
    const empty = '미입력';
    String v(String? s) => (s != null && s.isNotEmpty) ? s : empty;

    final info = <(String, String)>[
      ('상호명', v(u?.businessName)),
      ('사업자등록번호', v(u?.businessNumber)),
      ('대표자', v(u?.ownerName)),
      ('사업장 소재지', v(u?.businessAddress)),
      ('전화번호', v(u?.phoneNumber)),
      // 카카오는 이메일 제공 동의를 받지 않으면 이메일이 아예 없다.
      // 그때는 빈칸 대신 무엇으로 로그인했는지를 보여준다.
      ('이메일', u != null ? u.accountLabel : empty),
    ];

    // 정산서(세금계산서 발행 요청서)에 반드시 들어가야 하는 항목.
    // 하나라도 비면 도매상이 세금계산서를 발행할 수 없어서 문서가 무효다.
    final missing = <String>[
      if (u == null || u.businessName.isEmpty) '상호명',
      if (u == null || u.businessNumber.isEmpty) '사업자등록번호',
      if (u == null || u.ownerName.isEmpty) '대표자',
      if (u == null || u.businessAddress.isEmpty) '사업장 소재지',
      if (u == null || u.phoneNumber.isEmpty) '전화번호',
    ];

    // 🔴 #141 시안 상단: 배지 + 아바타 + 상호명 + `대표자 · 사업자번호`.
    //
    //    값이 없으면 시안 예시값(`플로우노트`, `김민준 대표님`)을 쓰지
    //    않는다. 위 `empty` 와 같은 원칙이다.
    final shopName = (u?.businessName.isNotEmpty ?? false)
        ? u!.businessName
        : '상호명을 입력해 주세요';
    final ownerBits = <String>[
      if (u != null && u.ownerName.isNotEmpty) '${u.ownerName} 대표님',
      if (u != null && u.businessNumber.isNotEmpty) '사업자 ${u.businessNumber}',
    ];
    final ownerLine =
        ownerBits.isEmpty ? '사업자 정보를 입력하면 여기에 보여요' : ownerBits.join(' · ');

    return FnColumn(
      gap: 14,
      children: [
        // ── 시안 프로필 상단 ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: _ProfileHeader(
            shopName: shopName,
            ownerLine: ownerLine,
            // 연필을 누르면 기존 '사업자 정보 수정' 과 같은 곳으로 간다.
            onEdit: () => BizReviewDsScreen.openEdit(context),
            // 🔴 `isPro` 를 보면 안 된다.
            // `SubscriptionService.unlockEverything = true` 라서 `isPro` 는
            // 항상 true 다(결제 전 전면 개방). 그래서 `!isPro` 로 걸면 이
            // 배지는 영원히 안 보인다 — 시안에는 있는 배지다.
            // **실제로 돈을 낸** 사람에게만 감춰야 하므로 `purchasedPro`
            // 를 본다. 결제가 붙는 날 조건을 다시 손댈 필요가 없다.
            showPlanBadge: !SubscriptionService.instance.purchasedPro,
          ),
        ),

        // ── 사업자 정보 카드 ────────────────────────────────────────────
        FnCard(
          bordered: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _bizOpen = !_bizOpen),
                child: Padding(
                  padding: EdgeInsets.only(bottom: _bizOpen ? 10 : 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '사업자 정보',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: FnColors.labelNormal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _bizOpen ? 0.5 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: const Text(
                              '▾',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                color: FnColors.labelAlternative,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // #141 좁은 화면(320dp)에서 이 줄이 42px 넘쳤다.
                      // 제목 + 배지 + 화살표 합이 254dp 를 넘긴다.
                      // 배지를 지우면 '이 정보가 왜 필요한지' 안내가 사라지고,
                      // 글자를 줄이면 읽기 어려워진다. 그래서 #140 금액 칸과
                      // 같은 방법으로 배지만 비례 축소한다(잘리지 않는다).
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: FnBadge('전자세금계산서 연동용',
                                    color: FnBadgeColor.accent,
                                    size: FnBadgeSize.small),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedRotation(
                            turns: _bizOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: FnColors.labelAlternative,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 필수 항목이 비어 있으면 카드를 접어놔도 보이게 알린다.
              // 정산서를 내보내려다 막히는 것보다 미리 아는 게 낫다.
              if (missing.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: _bizOpen ? 0 : 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: FnColors.rose99,
                      border: Border.all(color: FnColors.rose95),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 16, color: FnColors.rose50),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${missing.join(' · ')} 이(가) 비어 있어요',
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: FnColors.rose50,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '정산서를 내보내려면 사업자 정보가 필요해요.\n'
                                '아래 [사업자 정보 수정] 에서 입력해 주세요.',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  height: 1.4,
                                  color: FnColors.labelAlternative,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_bizOpen)
                ...info.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.$1,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            color: FnColors.labelAlternative,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.$2,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: FnColors.labelNormal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── 계정/서비스 관리 ────────────────────────────────────────────
        _Section(
          title: '계정/서비스 관리',
          titleColor: FnColors.primaryNormal, // blue-50 → 로즈
          items: [
            (
              '사업자 정보 수정',
              () => BizReviewDsScreen.openEdit(context),
            ),
            // 🔴 웹에서는 '구독 관리' 를 목록에서 **빼 버린다.**
            //    (사장님 요청 #120 — 웹앱에서 구독료 화면을 감춘다)
            //
            //    ⚠️ 지우지 말 것: [PaywallDsScreen] 화면 파일은 그대로 살아
            //       있다. 앱(APK)에서는 계속 보인다. 판단은
            //       `SubscriptionService.showPaywallEntry` 한 곳에만 있다.
            if (SubscriptionService.showPaywallEntry)
              (
                '구독 관리',
                () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PaywallDsScreen()),
                    ),
              ),
            // 🔴 'AI 인식(Gemini) API 키 설정' 진입 경로를 의도적으로 뺐다.
            //    (사장님 요청 — 앱/웹 어디서도 이 화면에 못 들어가게)
            //
            //    ⚠️ 지우지 말 것: 화면 파일과 저장된 API 키·프롬프트·모델
            //       설정은 **그대로 살아 있다**. 영수증 OCR 은
            //       `ApiKeyService` 가 저장소에서 직접 읽어 쓰기 때문에,
            //       입구만 막아도 인식 기능은 정상 동작한다.
            //       다시 열어야 하면 gemini_key_screen.dart 를 import 하고
            //       이 자리에 항목 한 줄을 되살리면 된다.
            // #141 '알림 설정' 을 실제 화면으로 연결했다.
            //      (예전에는 '준비 중' 스낵바였다)
            (
              '알림 설정',
              () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsDsScreen(),
                    ),
                  ),
            ),
            // 웹(PWA) 에서만 의미가 있다. 설치된 앱이거나 이미 홈 화면에서
            // 실행 중이면 `shouldGuide` 가 false 라 아예 안 보여준다.
            if (pwaState().shouldGuide)
              (
                '홈 화면에 추가하기',
                () => AddToHomeSheet.open(context),
              ),
            // 🔴 #141 시안은 로그아웃이 **이 카드의 마지막 항목**이다.
            //    (실측: 카드1 안 구분선 3개 = 항목 4개)
            //    예전에는 화면 아래 글자 버튼이었다. 동작은 그대로다.
            ('로그아웃', () => _signOut(context)),
          ],
        ),

        // ── 고객 지원 및 안내 ───────────────────────────────────────────
        _Section(
          title: '고객 지원 및 안내',
          titleColor: FnColors.leaf50, // green-50
          items: [
            ('공지사항', () => _todo(context, '공지사항')),
            ('제안 및 피드백(1:1문의)', () => _todo(context, '1:1 문의')),
            ('자주 묻는 질문 (FAQ)', () => _todo(context, 'FAQ')),
            (
              '서비스 이용약관',
              () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const LegalDocDsScreen(kind: LegalDocKind.terms),
                    ),
                  ),
            ),
            (
              '개인정보 처리방침',
              () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const LegalDocDsScreen(kind: LegalDocKind.privacy),
                    ),
                  ),
            ),
          ],
        ),

        // ── 마케팅 수신 동의 (언제든 철회 가능해야 함) ─────────────────
        const _MarketingConsentRow(),

        // 로그아웃은 위 '계정/서비스 관리' 카드 안으로 옮겼다. (#141)
        Center(
          child: FnTextButton(
            label: '회원 탈퇴',
            color: FnColors.labelAssistive,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DeleteAccountDsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 로그아웃.
  ///
  /// 🔴 절대로 SplashDsScreen 을 직접 push 하지 않는다.
  ///
  /// `pushAndRemoveUntil(..., (r) => false)` 로 스플래시를 띄우면
  /// 루트에 있던 `_AppEntry` 가 스택에서 **완전히 제거**된다.
  /// `_AppEntry` 는 `auth.isLoggedIn` 을 watch 해서 MainDsScreen 으로
  /// 바꿔주는 **유일한** 주체이므로, 이후 로그인에 성공해도 화면을
  /// 바꿔줄 위젯이 없어서 "로그인은 되는데 다음으로 안 넘어감" 이 된다.
  ///
  /// → 루트까지만 pop 하면 `_AppEntry` 가 살아난 채로
  ///   isLoggedIn == false 를 보고 스스로 스플래시를 그린다.
  static Future<void> _signOut(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  static void _todo(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label은 준비 중이에요')),
    );
  }
}

/// 시안 섹션: 제목(13/700 컬러) + ListCell 목록
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.titleColor,
    required this.items,
  });

  final String title;
  final Color titleColor;
  final List<(String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🔴 #141 시안 제목은 색 글자가 아니라 **진한 검정 굵은 글자**다.
        //    (실측: 계정/서비스 관리 · 고객 지원 및 안내 둘 다 같은 색)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _kProfTitle,
            ),
          ),
        ),
        // 🔴 #141 시안은 목록이 **흰 카드 안**에 들어 있다.
        //    실측: 카드 좌우 19.3~20.2dp, 모서리 둥글고 흰 배경.
        //    예전에는 카드 없이 배경 위에 줄만 놓여 있었다.
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kProfRadius),
            border: Border.all(color: _kProfLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(items.length, (i) {
              final it = items[i];
              return FnDsListCell(
                title: it.$1,
                divider: i < items.length - 1,
                titleWeight: FontWeight.w600,
                onTap: it.$2,
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: FnColors.labelAlternative,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// 마케팅 정보 수신 동의 토글.
///
/// 개인정보보호법상 선택 동의는 **언제든 철회할 수 있어야** 하므로
/// 가입 후에도 프로필에서 켜고 끌 수 있게 노출한다.
class _MarketingConsentRow extends StatelessWidget {
  const _MarketingConsentRow();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final on = auth.currentUser?.consents.marketingAgreed ?? false;

    return FnCard(
      bordered: true,
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '마케팅 정보 수신',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: FnColors.labelNormal,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '신규 기능·이벤트 안내 (선택)',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: FnColors.labelAlternative,
                  ),
                ),
              ],
            ),
          ),
          // 시안 Switch: w48 h28 r14, knob 22, on=blue-50 / off=line-normal
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.read<AuthProvider>().setMarketingConsent(!on),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 28,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? FnColors.rose50 : FnColors.lineNormal,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── #141 프로필 시안 실측 (425x1024, 환산비 0.9176) ────────────────
//
//   배경            #FEF9F5
//   무료 플랜 배지   y 127.6dp  204.6 x 26.6dp  #FF6D78
//   아바타 원        98.2 x 99.1dp  대각 #FF787C -> #FFA08E
//   편집 뱃지        20.2 x 20.2dp  #FFD4C4
//   카드1(계정)      y 383.6..601.1dp (h 218)  좌우 19.3~20.2dp
//   카드2(고객지원)   y 657.0..822.2dp (h 166)

/// 시안 섹션 제목 색.
const Color _kProfTitle = Color(0xFF17150F);

/// 시안 카드 테두리 — 홈/캘린더와 같은 연한 선.
const Color _kProfLine = Color(0x14C9A79B);

/// 시안 카드 모서리.
const double _kProfRadius = 16.0;

/// 시안 코랄 (배지).
const Color _kProfCoral = Color(0xFFFF6D78);

/// 시안 프로필 상단 — 배지 + 아바타 + 이름 + 부가정보.
///
/// 🔴 값이 없을 때 시안의 예시값(`플로우노트`, `김민준 대표님`,
///    `123-45-67890`)을 그대로 보여주면 안 된다. 사장님이 자기가 입력한
///    정보라고 믿게 된다. 비어 있으면 비어 있다고 말한다.
///    (이 파일 위쪽 `const empty = '미입력'` 과 같은 원칙)
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.shopName,
    required this.ownerLine,
    required this.onEdit,
    required this.showPlanBadge,
  });

  /// 상호명. 없으면 안내 문구가 들어온다.
  final String shopName;

  /// `대표자 · 사업자 번호` 한 줄. 없으면 안내 문구.
  final String ownerLine;

  final VoidCallback onEdit;

  /// 무료 플랜 안내 배지를 보일지. 이미 Pro 면 보이지 않는다.
  final bool showPlanBadge;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlanBadge) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _kProfCoral,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              '대표님, 한달 무료 플랜을 이용해보세요!',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        // ── 아바타 (대각 코랄 그라디언트 + 편집 뱃지) ──
        SizedBox(
          width: 104,
          height: 100,
          child: Stack(
            children: [
              Container(
                width: 98,
                height: 99,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF787C), Color(0xFFFFA08E)],
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEdit,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD4C4),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          shopName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: _kProfTitle,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          ownerLine,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12.5,
            color: Color(0xFF8A8580),
          ),
        ),
      ],
    );
  }
}
