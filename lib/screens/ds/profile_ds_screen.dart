import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_controls_ds.dart';
import '../../design/fn_profile_tokens.dart';
import '../../design/fn_sheet.dart';
import '../../providers/auth_provider.dart';
import '../../services/guest_service.dart';
import '../../services/pwa_install.dart';
import '../../services/subscription_service.dart';
import '../../widgets/fn_inquiry_parts.dart';
import '../../widgets/fn_signup_sheet.dart';
import 'add_to_home_sheet.dart';
import 'auth_ds_screens.dart';
import 'inquiry_list_ds_screen.dart';
import 'legal_doc_ds_screen.dart';
import 'notice_list_ds_screen.dart';
import 'notification_settings_ds_screen.dart';
import 'onboarding_ds_screens.dart';
import 'paywall_ds_screen.dart';

/// 프로필 화면 — 요청 #164 시안 1:1.
///
/// ## 시안 실측 (425x1024, 환산비 1.0897 → 390dp)
///
/// ```
///   배경            #FEF9F5
///   무료 플랜 배지    y 127.6..153.2dp (h 26.6)  w 204.6  #FF6D78
///   아바타          y 170.7..268.9dp  지름 98.2
///     그라디언트      좌상 (255,111,124) → 우하 (241,175,153)
///     편집 배지      우하, 지름 약 24dp, 흰 테두리 2dp, #FFD4C4
///   상호명          y 285.4dp  16dp/w700
///   대표자 줄        y 311.1dp  12dp  #76726F
///   '계정/서비스 관리' y 345.0dp  15.5dp/w700
///   카드1           y 385.4..594.6dp (h 209.2) → 4줄, 한 줄 52.3dp
///   '고객 지원 및 안내' y 620.3dp
///   카드2           y 660.7..815.8dp (h 155.1) → 3줄, 한 줄 51.7dp
///   카드            흰 바탕 r18, 그림자 알파 6%, 좌우 23.9dp
///   구분선          #EAEAEA, 카드 안쪽 좌우 21dp
///   화살표          #999999
/// ```
///
/// ## 시안에 없지만 남겨 둔 것 (지우면 안 되는 이유)
///
/// * **사업자 정보 누락 알림** — 필수 항목이 비면 정산서를 못 만든다.
///   값이 다 차 있으면 **아예 안 보이므로** 시안 상태와 같다.
/// * **마케팅 정보 수신 동의 토글** — 개인정보보호법상 선택 동의는
///   언제든 철회할 수 있어야 한다. 시안 영역 아래에 둔다.
/// * **회원 탈퇴** — 앱 마켓 심사 필수 항목이다. 맨 아래에 둔다.
///
/// 시안이 한 줄로 합친 `이용약관 및 개인정보 처리방침` 은 누르면 둘 중
/// 무엇을 볼지 고르는 시트가 뜬다. 두 문서 모두 접근 경로가 있어야 한다.
class ProfileDsScreen extends StatefulWidget {
  const ProfileDsScreen({super.key});

  @override
  State<ProfileDsScreen> createState() => _ProfileDsScreenState();
}

class _ProfileDsScreenState extends State<ProfileDsScreen> {
  @override
  Widget build(BuildContext context) {
    // 🔴 게스트는 **아예 다른 본문**을 그린다 (#195 — ④단계).
    //
    //    회원 본문(_memberBody) 은 한 글자도 건드리지 않았다. 같은 함수
    //    안에서 `if (게스트)` 를 수십 군데 끼워 넣으면, 조건 하나만
    //    어긋나도 가입하신 분들 화면이 같이 바뀐다. 갈래를 입구에서
    //    딱 한 번 나누면 회원 쪽은 지나갈 길이 없다.
    if (GuestService.instance.isGuest) {
      return ListenableBuilder(
        listenable: GuestService.instance,
        builder: (context, _) => _guestBody(context),
      );
    }
    return _memberBody(context);
  }

  /// 가입하신 분의 프로필. **예전 그대로다.**
  Widget _memberBody(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final u = auth.currentUser;

    // 🔴 값이 없을 때 시안의 예시 상호명/대표자/사업자번호를 그대로
    //    쓰면 안 된다. 사장님이 자기가 입력한
    //    정보라고 믿게 되고, 정산서를 뽑을 때 "사업자 정보가 없다" 는
    //    말을 들으면 앱이 고장난 것처럼 보인다.
    final shopName = (u?.businessName.isNotEmpty ?? false)
        ? u!.businessName
        : '상호명을 입력해 주세요';
    final ownerBits = <String>[
      if (u != null && u.ownerName.isNotEmpty) '${u.ownerName} 대표님',
      if (u != null && u.businessNumber.isNotEmpty) '사업자 ${u.businessNumber}',
    ];
    final ownerLine =
        ownerBits.isEmpty ? '사업자 정보를 입력하면 여기에 보여요' : ownerBits.join(' · ');

    // 정산서(세금계산서 발행 요청서)에 반드시 들어가야 하는 항목.
    // 하나라도 비면 도매상이 세금계산서를 발행할 수 없어서 문서가 무효다.
    final missing = <String>[
      if (u == null || u.businessName.isEmpty) '상호명',
      if (u == null || u.businessNumber.isEmpty) '사업자등록번호',
      if (u == null || u.ownerName.isEmpty) '대표자',
      if (u == null || u.businessAddress.isEmpty) '사업장 소재지',
      if (u == null || u.phoneNumber.isEmpty) '전화번호',
    ];

    return ColoredBox(
      color: FnProfile.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(FnProfile.pad, 0, FnProfile.pad, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 상단: 배지 + 아바타 + 상호명 + 대표자 줄 ──
            const SizedBox(height: 27),
            _ProfileHeader(
              shopName: shopName,
              ownerLine: ownerLine,
              onEdit: () => BizReviewDsScreen.openEdit(context),
              // 🔴 `isPro` 를 보면 안 된다.
              // `SubscriptionService.unlockEverything = true` 라서 `isPro` 는
              // 항상 true 다(결제 전 전면 개방). `!isPro` 로 걸면 이 배지는
              // 영원히 안 보인다 — 시안에는 있는 배지다.
              // **실제로 돈을 낸** 사람에게만 감춰야 하므로 `purchasedPro`.
              showPlanBadge: !SubscriptionService.instance.purchasedPro,
            ),

            // ── 사업자 정보가 비었을 때만 뜨는 알림 ──
            //    (다 차 있으면 이 자리에 아무것도 없다 = 시안과 동일)
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 20),
              _MissingInfoNotice(missing: missing),
            ],

            // ── 계정/서비스 관리 ──
            const SizedBox(height: 24),
            _Section(
              title: '계정/서비스 관리',
              items: [
                ('사업자 정보 수정', () => BizReviewDsScreen.openEdit(context)),
                // 🔴 웹에서는 '구독 관리' 를 목록에서 **빼 버린다.**
                //    (사장님 요청 #120 — 웹앱에서 구독료 화면을 감춘다)
                //
                //    ⚠️ 지우지 말 것: [PaywallDsScreen] 화면 파일은 그대로
                //       살아 있다. 앱(APK)에서는 계속 보인다. 판단은
                //       `SubscriptionService.showPaywallEntry` 한 곳에만 있다.
                if (SubscriptionService.showPaywallEntry)
                  (
                    '구독 관리',
                    () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PaywallDsScreen()),
                        ),
                  ),
                (
                  '알림 설정',
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationSettingsDsScreen(),
                        ),
                      ),
                ),
                // 웹(PWA) 에서만 의미가 있다. 이미 바탕화면에서 실행 중이면
                // 할 일이 없으므로 줄 자체를 그리지 않는다. (#182)
                if (pwaState().shouldGuide)
                  ('바탕화면에 설치하기', () => AddToHomeSheet.open(context)),
                ('로그아웃', () => _signOut(context)),
              ],
            ),

            // ── 고객 지원 및 안내 ──
            const SizedBox(height: 26),
            _Section(
              title: '고객 지원 및 안내',
              items: [
                (
                  '공지사항',
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NoticeListDsScreen()),
                      ),
                ),
                (
                  // 🔴 글쓰기로 바로 가지 않고 목록으로 간다. 보낸 문의와
                  //    답변을 여기서 확인해야 하기 때문이다.
                  //    관리자 계정이면 같은 화면이 '전체 문의' 가 된다.
                  '제안 및 피드백',
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InquiryListDsScreen()),
                      ),
                ),
                ('이용약관 및 개인정보 처리방침', () => _openLegal(context)),
              ],
            ),

            // ── 여기부터는 시안에 없지만 법/심사상 꼭 있어야 하는 것들 ──
            const SizedBox(height: 26),
            const _MarketingConsentCard(),
            const SizedBox(height: 18),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DeleteAccountDsScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '회원 탈퇴',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      color: Color(0xFFA6A19D),
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

  /// 체험 중인 분의 프로필. (#195)
  ///
  /// 기존 화면 구조(배너 · 아바타 · 이름 · 섹션 카드)를 그대로 쓰고
  /// 내용만 바꾼다. 다른 모양을 새로 만들면 가입한 뒤 화면이 확 달라져
  /// 낯설어진다.
  ///
  /// 🔴 잠근 줄을 **지우지 않고** 🔒 '가입 후' 로 남겨 둔다. 지워 버리면
  ///    가입하면 뭐가 생기는지 보이지 않는다.
  Widget _guestBody(BuildContext context) {
    final g = GuestService.instance;

    void lockedTap() => unawaited(showFnSignUpSheet(
          context,
          feature: '가입하시면 이 기능을 쓰실 수 있어요',
        ));

    return ColoredBox(
      color: FnProfile.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(FnProfile.pad, 0, FnProfile.pad, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 27),
            _ProfileHeader(
              shopName: '체험 중인 대표님',
              ownerLine: '가입하면 상호명·사업자 정보를 등록할 수 있어요',
              // 🔴 아바타 편집 배지도 잠긴다. 누르면 사업자 정보 입력
              //    화면이 열리는데, 게스트는 저장할 곳이 없다.
              onEdit: lockedTap,
              showPlanBadge: true,
              badgeText: '영수증 ${GuestService.scanMax}장 무료 체험 중',
            ),

            // ── 체험 진행 + 가입 ──
            const SizedBox(height: 22),
            _GuestTrialCard(used: g.scans, max: GuestService.scanMax),

            // ── 계정/서비스 관리 ──
            const SizedBox(height: 24),
            _Section(
              title: '계정/서비스 관리',
              items: [
                ('사업자 정보 수정', lockedTap),
                if (SubscriptionService.showPaywallEntry)
                  ('구독 관리', lockedTap),
                ('알림 설정', lockedTap),
                // 바탕화면 설치는 계정이 없어도 된다 — 열어 둔다.
                if (pwaState().shouldGuide)
                  ('바탕화면에 설치하기', () => AddToHomeSheet.open(context)),
                // 🔴 로그아웃은 넣지 않는다. 체험 중에 누르면 찍어 둔
                //    영수증으로 돌아올 길이 없어진다.
              ],
              // 🔒 '가입 후' 꼬리표를 붙일 줄.
              lockedLabels: const {'사업자 정보 수정', '구독 관리', '알림 설정'},
            ),

            // ── 고객 지원 및 안내 ──
            const SizedBox(height: 26),
            _Section(
              title: '고객 지원 및 안내',
              items: [
                (
                  '공지사항',
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NoticeListDsScreen()),
                      ),
                ),
                // 🔴 문의는 잠근다. 게스트는 답변을 받을 곳이 없다.
                ('제안 및 피드백', lockedTap),
                ('이용약관 및 개인정보 처리방침', () => _openLegal(context)),
              ],
              lockedLabels: const {'제안 및 피드백'},
            ),

            // 🔴 마케팅 수신 동의와 회원 탈퇴는 **계정이 있어야** 뜻이 있다.
            //    게스트에게 '회원 탈퇴' 를 보여 주면 누르는 순간 체험 계정을
            //    지우려 든다. 가입하면 둘 다 제자리에 나타난다.
          ],
        ),
      ),
    );
  }

  /// 시안은 약관과 처리방침을 한 줄로 합쳐 놨다. 두 문서 모두 열 수
  /// 있어야 하므로 고르는 시트를 띄운다.
  static Future<void> _openLegal(BuildContext context) async {
    final kind = await showFnOptionSheet<LegalDocKind>(
      context,
      title: '이용약관 및 개인정보 처리방침',
      options: const [
        FnSheetOption(value: LegalDocKind.terms, label: '서비스 이용약관'),
        FnSheetOption(value: LegalDocKind.privacy, label: '개인정보 처리방침'),
        FnSheetOption(value: LegalDocKind.marketing, label: '마케팅 정보 수신 동의'),
      ],
    );
    if (kind == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocDsScreen(kind: kind)),
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

}

/// 시안 상단 — 배지 + 아바타 + 상호명 + 대표자 줄.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.shopName,
    required this.ownerLine,
    required this.onEdit,
    required this.showPlanBadge,
    this.badgeText = _defaultBadge,
  });

  /// 🔴 기본값이 지금 쓰던 문구다. 회원 쪽은 이 값을 넘기지 않으므로
  ///    한 픽셀도 달라지지 않는다.
  static const String _defaultBadge = '대표님, 한달 무료 플랜을 이용해보세요!';

  /// 상호명. 없으면 안내 문구가 들어온다.
  final String shopName;

  /// `대표자 · 사업자 번호` 한 줄. 없으면 안내 문구.
  final String ownerLine;

  final VoidCallback onEdit;

  /// 무료 플랜 안내 배지를 보일지. 이미 결제한 분께는 보이지 않는다.
  final bool showPlanBadge;

  /// 배지 문구. 체험 중이면 남은 체험을 알려 준다.
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPlanBadge) ...[
          Center(
            child: Container(
              height: FnProfile.planBadgeH,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FnProfile.coral,
                borderRadius:
                    BorderRadius.circular(FnProfile.planBadgeH / 2),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: FnProfile.planBadgeFont,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // 시안 배지 바닥 153.2 → 아바타 윗변 170.7 = 17.5dp
          const SizedBox(height: 17),
        ],
        // ── 아바타 (대각 코랄 그라디언트 + 편집 배지) ──
        SizedBox(
          width: FnProfile.avatar,
          height: FnProfile.avatar,
          child: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [FnProfile.avatarFrom, FnProfile.avatarTo],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 7,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEdit,
                  child: Container(
                    width: FnProfile.editBadge,
                    height: FnProfile.editBadge,
                    decoration: BoxDecoration(
                      color: FnProfile.editBadgeBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 시안 아바타 바닥 268.9 → 상호명 285.4 = 16.5dp
        const SizedBox(height: 16),
        Text(
          shopName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnProfile.shopFont,
            fontWeight: FontWeight.w700,
            color: FnProfile.ink,
          ),
        ),
        // 시안 상호명 바닥 300.1 → 대표자 줄 311.1 = 11dp
        const SizedBox(height: 10),
        Text(
          ownerLine,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnProfile.ownerFont,
            color: FnProfile.sub,
          ),
        ),
      ],
    );
  }
}

/// 시안 섹션 — 제목 + 흰 카드 안의 줄 목록.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    this.lockedLabels = const <String>{},
  });

  final String title;
  final List<(String, VoidCallback)> items;

  /// 🔒 '가입 후' 꼬리표를 붙일 줄의 이름. (#195)
  ///
  /// 🔴 비어 있으면 아무 일도 하지 않는다 — 회원 화면은 그대로다.
  final Set<String> lockedLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // 시안 섹션 제목 좌 24.8dp = 카드 좌 23.9 + 약 1
          padding: const EdgeInsets.only(left: 1, bottom: 14),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: FnProfile.sectionFont,
              fontWeight: FontWeight.w700,
              color: FnProfile.ink,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: FnProfile.card,
            borderRadius: BorderRadius.circular(FnProfile.cardRadius),
            boxShadow: FnProfile.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: FnProfile.rowPadH),
                    child: Divider(
                        height: 1, thickness: 1, color: FnProfile.hair),
                  ),
                _Row(
                  label: items[i].$1,
                  onTap: items[i].$2,
                  locked: lockedLabels.contains(items[i].$1),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 카드 안의 한 줄. 시안 높이 52.3dp.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final VoidCallback onTap;

  /// 🔒 '가입 후' 꼬리표를 붙인다. 🔴 false 면 예전 모양 그대로다.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: FnProfile.rowH,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: FnProfile.rowPadH),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: FnProfile.rowFont,
                    fontWeight: FontWeight.w600,
                    color: FnProfile.ink,
                  ),
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 8),
                const _LockedTag(),
              ],
              const SizedBox(width: 8),
              // 시안 화살표: 가는 선, 높이 11dp, #999999
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: FnProfile.chevron),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🔒 '가입 후' 꼬리표. (#195)
///
/// 줄을 지우지 않고 꼬리표만 붙인다. 지우면 가입하면 뭐가 생기는지
/// 보이지 않는다.
class _LockedTag extends StatelessWidget {
  const _LockedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '🔒 가입 후',
        style: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: FnProfile.coral,
        ),
      ),
    );
  }
}

/// 체험 진행 + 가입 카드. 게스트에게만 보인다. (#195)
///
/// 🔴 가입 버튼 둘과 로그인 링크가 **모두 같은 곳**으로 간다. 체험 계정을
///    그대로 들고 가입하는 계정 연결은 ⑤단계 일이다. 지금 버튼마다 다른
///    길을 뚫어 두면 그때 전부 다시 뜯어야 한다.
class _GuestTrialCard extends StatelessWidget {
  const _GuestTrialCard({required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final capped = used.clamp(0, max);
    return Container(
      padding: const EdgeInsets.fromLTRB(FnProfile.rowPadH, 18, 18, 18),
      decoration: BoxDecoration(
        color: FnProfile.card,
        borderRadius: BorderRadius.circular(FnProfile.cardRadius),
        boxShadow: FnProfile.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '영수증 $capped/$max장 사용',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: FnProfile.rowFont,
              fontWeight: FontWeight.w700,
              color: FnProfile.ink,
            ),
          ),
          const SizedBox(height: 10),
          FnProgressBar(
            value: max == 0 ? 0 : capped / max * 100,
            height: 8,
            color: FnProfile.coral,
          ),
          const SizedBox(height: 18),
          // 🔴 카카오는 커스텀 토큰이라 uid 가 바뀐다. 붙이면 체험 영수증이
          //    사라진 것처럼 보이므로, 옮기는 서버 함수가 생기기 전까지는
          //    지금처럼 로그인 화면으로만 보낸다. (#195 ⑤)
          FnPrimaryButton(
            label: '카카오로 3초 가입',
            onTap: () => fnOpenSignIn(context),
          ),
          const SizedBox(height: 10),
          // 구글은 체험 계정에 **붙인다** — uid 가 그대로라 영수증이 남는다.
          FnOutlineButton(
            label: '구글로 가입',
            onTap: () =>
                unawaited(fnLinkGuestAccount(context, GuestLinkMethod.google)),
          ),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => fnOpenSignIn(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '이미 가입하셨나요? 로그인',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: FnProfile.sub,
                    decoration: TextDecoration.underline,
                    decorationColor: FnProfile.sub,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사업자 정보가 비었을 때만 뜨는 알림.
///
/// 시안에는 없다. 그러나 이게 없으면 정산서를 만들려다 막히고 나서야
/// 사실을 알게 된다. 값이 다 차 있으면 이 위젯 자체가 그려지지 않으므로
/// 평소 화면은 시안과 똑같다.
class _MissingInfoNotice extends StatelessWidget {
  const _MissingInfoNotice({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(FnProfile.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: FnProfile.coral),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${missing.join(' · ')} 이(가) 비어 있어요',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: FnProfile.coral,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '정산서를 내보내려면 사업자 정보가 필요해요.\n'
                  '아래 [사업자 정보 수정] 에서 입력해 주세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    height: 1.45,
                    color: FnProfile.sub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 마케팅 정보 수신 동의.
///
/// 개인정보보호법상 선택 동의는 **언제든 철회할 수 있어야** 하므로
/// 가입 후에도 여기서 켜고 끌 수 있게 둔다. 시안에는 없지만 지우면
/// 안 된다.
class _MarketingConsentCard extends StatelessWidget {
  const _MarketingConsentCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final on = auth.currentUser?.consents.marketingAgreed ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(FnProfile.rowPadH, 14, 18, 14),
      decoration: BoxDecoration(
        color: FnProfile.card,
        borderRadius: BorderRadius.circular(FnProfile.cardRadius),
        boxShadow: FnProfile.cardShadow,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '마케팅 정보 수신',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: FnProfile.rowFont,
                    fontWeight: FontWeight.w600,
                    color: FnProfile.ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '신규 기능·이벤트 안내 (선택)',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: FnProfile.nsDescFont,
                    color: FnProfile.sub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 알림 설정 화면과 같은 토글을 쓴다. 모양이 갈라지지 않는다.
          FnToggle(
            on: on,
            onTap: () => context.read<AuthProvider>().setMarketingConsent(!on),
          ),
        ],
      ),
    );
  }
}
