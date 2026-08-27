import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_shell.dart';
import '../../design/fn_card.dart';
import '../../design/fn_button.dart';
import 'package:provider/provider.dart';

import '../../providers/receipt_provider.dart';
import '../../services/subscription_service.dart';
import '../scan/scan_flow.dart';

/// 시안 `AppH1Mvp / screen === 'main'` 1:1 포팅
///
/// ```js
/// Shell(navTitle:'스캔', tabs, activeTab:'scan')
///   div padding:20 column gap:26
///     Card { textAlign:'center', padding:'30px 16px', overflow:'hidden',
///            background:'linear-gradient(170deg, #FFF8F6 0%, #FDEEF0 100%)' }
///       div 168x112 margin '0 auto 16px'            → 겹친 영수증 일러스트
///         · radial-gradient glow (rgba(238,118,134,.18) → 0 at 70%)
///         · 영수증 3장 [rot, dx, opacity]
///             [[-9,-34,.9], [7,30,.9], [-1,0,1]]
///           각 66x90 r7 #fff, shadow '0 6px 16px rgba(180,90,105,.16)',
///           padding '10px 9px', gap 5
///             · 제목 줄 h5 w62% r3 #F6C9D0
///             · 본문 4줄 h3 r2 rgba(23,23,23,.10) w[86,68,78,54]%
///         · 카메라 FAB 40x40 r20 #EE7686 (right:10, bottom:0)
///           shadow '0 6px 16px rgba(238,118,134,.4)', 아이콘 21
///       div wds-heading2 mb14 fontWeight600     '오늘 촬영한 영수증 0장'
///       div 14/400 label-alternative mb18       '이번 달 무료 스캔 N/M장 사용'
///       Button large  width100%                 '촬영하기'
///       Button large outlined width100% mt8     '갤러리에서 선택'
///     Card bordered { background:'#FFF9F9', boxShadow:'inset 0 0 0 1px #FBE3E6' }
///       header: [22x22 r11 #EE7686 흰'!' 13/800] gap8 mb12 + '촬영 전 스캔 팁' 18
///       3행: [18x18 r9 #FDECEC 원 + #EE7686 체크 12] gap10
///            [제목 15/600] / [설명 13.5 lh1.5 label-alternative]
///            padding '9px 0', 첫 행 제외 borderTop 1px line-normal-neutral
/// ```
///
/// 🔴 디자인만 시안에 맞춘다. 동작(`_start` / `_pickFromGallery` /
///    `todayCount` / 스캔 한도 / 구독 분기)은 그대로다.
class ScanDsScreen extends StatefulWidget {
  const ScanDsScreen({super.key});

  @override
  State<ScanDsScreen> createState() => ScanDsScreenState();
}

class ScanDsScreenState extends State<ScanDsScreen> {
  /// MainScreen이 스캔 탭 재탭 시 호출
  Future<void> showCameraOptions() => _start();

  /// '촬영하기' → 시안 `CaptureSheet` (단일 촬영 / 연속 촬영)
  Future<void> _start() async {
    await ScanFlow.start(context);
    if (mounted) setState(() {});
  }

  /// '갤러리에서 선택' → 시트 없이 곧바로 앨범 열기
  Future<void> _pickFromGallery() async {
    await ScanFlow.startFromGallery(context);
    if (mounted) setState(() {});
  }

  static const _tips = [
    ('밝은 환경에서', '밝은 곳에서 찍을수록 인식이 잘 돼요'),
    ('영수증 전체가 보이게', '영수증 전체가 화면 안에 들어오게 촬영하세요'),
    ('인식 후 수정 가능', '잘못 인식된 부분은 편집 화면에서 바로 고칠 수 있어요'),
  ];

  @override
  Widget build(BuildContext context) {
    // SubscriptionService 는 provider 트리에 없어서 watch 가 안 된다.
    // 스캔 횟수가 늘면 카드가 즉시 갱신되도록 직접 구독한다.
    return ListenableBuilder(
      listenable: SubscriptionService.instance,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final sub = SubscriptionService.instance;
    final used = sub.scansThisMonth;
    const cap = PlanPolicy.freeMonthlyScans;
    final reached = !sub.canScan;
    final now = DateTime.now();
    // '오늘 촬영한' 이므로 영수증에 적힌 날짜(date)가 아니라
    // 실제로 찍어서 저장한 시각(createdAt)으로 세야 한다.
    // (과거 날짜 영수증을 오늘 찍는 경우가 흔하다)
    final todayCount = context
        .watch<ReceiptProvider>()
        .allReceipts
        .where((r) =>
            r.createdAt.year == now.year &&
            r.createdAt.month == now.month &&
            r.createdAt.day == now.day)
        .length;

    return FnColumn(
      gap: 26,
      padding: const EdgeInsets.all(20),
      children: [
        // ── 촬영 카드 ───────────────────────────────────────────────────
        //
        // 🔴 `FnCard` 는 단색만 받는다. 시안은 그라데이션이므로
        //    Container 로 직접 그린다. (radius 20 / shadow-normal 은 동일)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: FnShadow.normal,
            // linear-gradient(170deg, #FFF8F6 0%, #FDEEF0 100%)
            //   CSS 170deg = 위에서 아래로 살짝 왼쪽으로 기운 방향
            gradient: const LinearGradient(
              begin: Alignment(-0.174, -1),
              end: Alignment(0.174, 1),
              colors: [Color(0xFFFFF8F6), Color(0xFFFDEEF0)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ScanHeroArt(),
              const SizedBox(height: 16),
              Text(
                '오늘 촬영한 영수증 $todayCount장',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 14),
              // 🔴 시안 원본은 플랜 구분 없이 이 한 줄이다.
              //
              // ```js
              // div { fontSize:14, fontWeight:400, color:'var(--label-alternative)' }
              //   `이번 달 무료 스캔 ${monthlyCount}/${MVP_MONTHLY_CAP}장 사용`
              // ```
              //
              // 예전에는 `sub.purchasedPro` / `sub.isPro` 로 'PRO · 스캔 무제한'
              // 같은 문구를 갈라 보여줬다. 그런데 지금은
              // `SubscriptionService.unlockEverything == true` 라서 `isPro` 가
              // 항상 참이고, 결과적으로 화면에는 늘 '스캔 무제한' 이 떴다.
              // 사장님이 준 디자인에는 그런 문구가 없고, "프로 어쩌고는 다
              // 빼기로 했다" 는 지시도 있었다. 그래서 시안 문구 하나로 통일한다.
              //
              // 남은 횟수 계산(`used` / `cap`)과 한도 도달 판단(`reached`)은
              // 건드리지 않는다 — 기능은 그대로다.
              Text(
                '이번 달 무료 스캔 $used/$cap장 사용',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: FnColors.labelAlternative,
                ),
              ),
              const SizedBox(height: 18),
              FnButton(
                label: reached ? '이번 달 스캔 한도 도달' : '촬영하기',
                size: FnButtonSize.large,
                expand: true,
                onPressed: reached ? null : _start,
              ),
              const SizedBox(height: 8),
              FnButton(
                label: '갤러리에서 선택',
                size: FnButtonSize.large,
                variant: FnButtonVariant.outlined,
                expand: true,
                onPressed: reached ? null : _pickFromGallery,
              ),
            ],
          ),
        ),

        // ── 스캔 팁 카드 ────────────────────────────────────────────────
        FnCard(
          bordered: true,
          color: const Color(0xFFFFF9F9),
          borderColor: const Color(0xFFFBE3E6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: _rose,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '!',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '촬영 전 스캔 팁',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: FnColors.labelNormal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(_tips.length, (i) {
                final t = _tips[i];
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(
                            top: BorderSide(
                                color: FnColors.lineNeutral, width: 1),
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 시안: 18x18 r9 #FDECEC 원 + #EE7686 체크 12
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFDECEC),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: _rose,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t.$1,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: FnColors.labelNormal,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              t.$2,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13.5,
                                height: 1.5,
                                color: FnColors.labelAlternative,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

/// 시안 로즈 `#EE7686` (= 템플릿이 덮어쓴 `--blue-50`)
const Color _rose = Color(0xFFEE7686);

/// 스캔 카드 히어로 일러스트 — 겹쳐 놓인 영수증 3장 + 카메라 FAB.
///
/// 시안 원본:
/// ```js
/// div { position:'relative', width:168, height:112, margin:'0 auto 16px' }
///   div { inset:0, borderRadius:16,
///         background:'radial-gradient(circle at 50% 46%,
///                     rgba(238,118,134,.18), rgba(238,118,134,0) 70%)' }
///   [[-9,-34,.9],[7,30,.9],[-1,0,1]].map(([rot,dx,op], i) => …)
///   div { right:10, bottom:0, width:40, height:40, borderRadius:20,
///         background:'#EE7686', boxShadow:'0 6px 16px rgba(238,118,134,.4)' }
/// ```
class _ScanHeroArt extends StatelessWidget {
  const _ScanHeroArt();

  /// [회전(deg), 좌우 오프셋(px), 투명도]
  static const _cards = <(double, double, double)>[
    (-9, -34, .9),
    (7, 30, .9),
    (-1, 0, 1),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // radial glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const RadialGradient(
                  center: Alignment(0, -0.08), // circle at 50% 46%
                  radius: 0.7,
                  colors: [Color(0x2EEE7686), Color(0x00EE7686)],
                ),
              ),
            ),
          ),
          // 영수증 3장 — 시안 z-index 대로 마지막(가운데) 장이 맨 위
          for (final (rot, dx, op) in _cards)
            Positioned(
              left: 168 / 2 - 33 + dx,
              top: 6,
              child: Opacity(
                opacity: op,
                child: Transform.rotate(
                  angle: rot * math.pi / 180,
                  child: const _ReceiptSheet(),
                ),
              ),
            ),
          // 카메라 FAB
          Positioned(
            right: 10,
            bottom: 0,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _rose,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66EE7686), // rgba(238,118,134,.4)
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.photo_camera_rounded,
                  size: 21, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 일러스트 안 영수증 한 장 (66x90 r7)
class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet();

  /// 본문 줄 너비(%) — 시안 [86, 68, 78, 54]
  static const _lines = <double>[.86, .68, .78, .54];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29B45A69), // rgba(180,90,105,.16)
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 줄
          FractionallySizedBox(
            widthFactor: .62,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFF6C9D0),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          for (final w in _lines) ...[
            const SizedBox(height: 5),
            FractionallySizedBox(
              widthFactor: w,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0x1A171717), // rgba(23,23,23,.10)
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
