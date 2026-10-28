import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_profile_tokens.dart';
import '../../design/fn_sheet.dart';
import '../../providers/auth_provider.dart';
import '../../services/pwa_install.dart';
import '../../services/subscription_service.dart';
import 'add_to_home_sheet.dart';
import 'auth_ds_screens.dart';
import 'inquiry_ds_screen.dart';
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
                // 웹(PWA) 에서만 의미가 있다. 이미 설치돼 있으면 안 보인다.
                if (pwaState().shouldGuide)
                  ('홈 화면에 추가하기', () => AddToHomeSheet.open(context)),
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
                  '제안 및 피드백',
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InquiryDsScreen()),
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
  });

  /// 상호명. 없으면 안내 문구가 들어온다.
  final String shopName;

  /// `대표자 · 사업자 번호` 한 줄. 없으면 안내 문구.
  final String ownerLine;

  final VoidCallback onEdit;

  /// 무료 플랜 안내 배지를 보일지. 이미 결제한 분께는 보이지 않는다.
  final bool showPlanBadge;

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
              child: const Text(
                '대표님, 한달 무료 플랜을 이용해보세요!',
                style: TextStyle(
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
  const _Section({required this.title, required this.items});

  final String title;
  final List<(String, VoidCallback)> items;

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
                _Row(label: items[i].$1, onTap: items[i].$2),
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
  const _Row({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

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
