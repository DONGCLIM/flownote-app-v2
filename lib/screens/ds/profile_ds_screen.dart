import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_badge_ds.dart';
import '../../design/fn_button.dart';
import '../../providers/auth_provider.dart';
import '../../services/pwa_install.dart';
import '../gemini_key_screen.dart';
import 'add_to_home_sheet.dart';
import 'auth_ds_screens.dart';
import 'legal_doc_ds_screen.dart';
import 'onboarding_ds_screens.dart';
import 'paywall_ds_screen.dart';

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

    return FnColumn(
      gap: 14,
      children: [
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
                      Row(
                        children: [
                          const FnBadge('전자세금계산서 연동용',
                              color: FnBadgeColor.accent,
                              size: FnBadgeSize.small),
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
            (
              '구독 관리',
              () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PaywallDsScreen()),
                  ),
            ),
            // 영수증 OCR 은 Gemini API 키가 있어야 동작한다.
            // 리디자인 과정에서 진입 경로가 사라져 있었으므로 다시 노출한다.
            (
              'AI 인식(Gemini) API 키 설정',
              () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GeminiKeyScreen()),
                  ),
            ),
            ('알림 설정', () => _todo(context, '알림 설정')),
            // 웹(PWA) 에서만 의미가 있다. 설치된 앱이거나 이미 홈 화면에서
            // 실행 중이면 `shouldGuide` 가 false 라 아예 안 보여준다.
            if (pwaState().shouldGuide)
              (
                '홈 화면에 추가하기',
                () => AddToHomeSheet.open(context),
              ),
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

        // ── 로그아웃 ────────────────────────────────────────────────────
        Center(
          child: FnTextButton(
            label: '로그아웃',
            color: FnColors.labelAlternative,
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (!context.mounted) return;
              // 🔴 절대로 SplashDsScreen 을 직접 push 하지 않는다.
              //
              // `pushAndRemoveUntil(..., (r) => false)` 로 스플래시를 띄우면
              // 루트에 있던 `_AppEntry` 가 스택에서 **완전히 제거**된다.
              // `_AppEntry` 는 `auth.isLoggedIn` 을 watch 해서
              // MainDsScreen 으로 바꿔주는 **유일한** 주체이므로,
              // 이후 로그인에 성공해도 화면을 바꿔줄 위젯이 없어서
              // "로그인은 되는데 다음으로 안 넘어감" 이 된다.
              //
              // → 루트까지만 pop 하면 `_AppEntry` 가 살아난 채로
              //    isLoggedIn == false 를 보고 스스로 스플래시를 그린다.
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ),
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
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
        ),
        ...List.generate(items.length, (i) {
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
