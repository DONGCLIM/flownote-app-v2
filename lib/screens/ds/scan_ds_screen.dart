import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_home_tokens.dart';
import '../../providers/receipt_provider.dart';
import '../../services/subscription_service.dart';
import '../scan/scan_flow.dart';

/// 스캔 화면 — #136 시안(PNG) 기준으로 톤앤톤/컬러를 다시 맞춘 버전.
///
/// 시안을 그림으로 붙이지 않고 전부 위젯으로 다시 그렸다. 동작은 예전과
/// 똑같다.
///
/// ## 시안 실측 (473x1024, 환산비 0.8245 -> 390x844dp)
/// 로그인 시안과 같은 규격이고 색도 같았다.
/// | 항목            | 실측                                  |
/// |-----------------|---------------------------------------|
/// | 페이지 배경      | #FEF9F5 (37.8%)                       |
/// | 흰 카드          | #FFFFFF (24.7%)                       |
/// | 코랄 버튼        | #FF6D78 단색 (그라디언트 아님)          |
/// | 보조 버튼        | #FEFDFB                               |
/// | 팁 카드          | 좌우 여백 23.9dp · r 14.2dp            |
/// | 버튼 높이        | 52.8 / 54.4dp — 둘 다 알약(r = h/2)   |
/// | 팁 번호 색       | #C76769                               |
///
/// 🔴 동작(`_start` / `_pickFromGallery` / `todayCount` / 스캔 한도 /
///    구독 분기 / `showCameraOptions`)은 하나도 바꾸지 않았다.
class ScanDsScreen extends StatefulWidget {
  const ScanDsScreen({super.key});

  @override
  State<ScanDsScreen> createState() => ScanDsScreenState();
}

class ScanDsScreenState extends State<ScanDsScreen> {
  /// MainScreen이 스캔 탭 재탭 시 호출
  Future<void> showCameraOptions() => _start();

  /// '영수증 촬영하기' → 시안 `CaptureSheet` (단일 촬영 / 연속 촬영)
  Future<void> _start() async {
    await ScanFlow.start(context);
    if (mounted) setState(() {});
  }

  /// '앨범에서 가져오기' → 시트 없이 곧바로 앨범 열기
  Future<void> _pickFromGallery() async {
    await ScanFlow.startFromGallery(context);
    if (mounted) setState(() {});
  }

  /// 시안 팁 3개. 번호(01/02/03)는 그릴 때 붙인다.
  static const _tips = [
    ('밝은 환경에서', '밝은 곳에서 찍을수록 인식이 잘 돼요'),
    ('영수증 전체가 보이게', '영수증 전체가 화면 안에 들어오게 촬영하세요'),
    ('인식 후 수정 가능', '잘못 인식된 부분은 다음 화면에서 수정할 수 있어요'),
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

    // 🔴 `Container(color:)` 만으로는 배경이 화면 끝까지 안 칠해진다.
    //    `FnColumn` 은 `SingleChildScrollView` 라서 높이가 내용만큼이고,
    //    내용이 화면보다 짧으면 그 아래가 Scaffold 기본색으로 남는다.
    //    실측: 390x844 에서 678.5dp 아래 165dp 가 #FEF7FF 로 떴다.
    //    `SizedBox.expand` 로 먼저 화면을 꽉 채운 뒤 색을 칠한다.
    return ColoredBox(
      color: FnHome.bgWarm,
      child: SizedBox.expand(
        child: FnColumn(
        gap: 0,
        padding: const EdgeInsets.fromLTRB(
          FnHome.scanPad,
          8,
          FnHome.scanPad,
          24,
        ),
        children: [
          // ── 히어로 일러스트 ─────────────────────────────────────────
          const Center(child: _ScanHeroArt()),
          const SizedBox(height: 26),

          // ── 오늘 촬영한 영수증 N장 ──────────────────────────────────
          Text(
            '오늘 촬영한 영수증 $todayCount장',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: FnHome.title,
            ),
          ),
          const SizedBox(height: 7),

          // 🔴 시안 원본은 플랜 구분 없이 이 한 줄이다.
          //    예전에는 `sub.isPro` 로 'PRO · 스캔 무제한' 을 갈라 보여줬는데,
          //    `unlockEverything == true` 라서 늘 '무제한' 만 떴다.
          //    남은 횟수 계산(used/cap)과 한도 판단(reached)은 그대로 쓴다.
          Text(
            '이번 달 무료 스캔 $used/$cap장 사용',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: FnHome.tipDesc,
            ),
          ),
          const SizedBox(height: 24),

          // ── 촬영 전 스캔 팁 ─────────────────────────────────────────
          _tipCard(),
          const SizedBox(height: 22),

          // ── 영수증 촬영하기 (코랄) ──────────────────────────────────
          _PillButton(
            label: reached ? '이번 달 스캔 한도 도달' : '영수증 촬영하기',
            icon: Icons.photo_camera_rounded,
            filled: true,
            onTap: reached ? null : _start,
          ),
          const SizedBox(height: 12),

          // ── 앨범에서 가져오기 (보조) ────────────────────────────────
          _PillButton(
            label: '앨범에서 가져오기',
                height: FnHome.buttonH2,
            icon: Icons.photo_library_rounded,
            filled: false,
            onTap: reached ? null : _pickFromGallery,
          ),
        ],
        ),
      ),
    );
  }

  /// 시안의 '촬영 전 스캔 팁' 흰 카드.
  /// 머리글에 스캔 프레임 아이콘 + 아래로 번호 매긴 팁 3개.
  Widget _tipCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: FnHome.card,
        borderRadius: BorderRadius.circular(FnHome.tipRadius),
        border: Border.all(color: FnHome.cardLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.center_focus_strong_rounded,
                  size: 19, color: FnHome.coralFlat),
              SizedBox(width: 8),
              Text(
                '촬영 전 스캔 팁',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: FnHome.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(_tips.length, (i) {
            final t = _tips[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 시안은 체크 아이콘이 아니라 01 / 02 / 03 번호다.
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '0${i + 1}',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: FnHome.tipIndex,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.$1,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: FnHome.title,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          t.$2,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12.5,
                            height: 1.4,
                            color: FnHome.tipDesc,
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
    );
  }
}

/// 시안의 알약 버튼. 코랄 채움(촬영) / 흰 바탕(앨범) 두 가지.
///
/// 시안 높이가 52.8 / 54.4dp 였고 모서리는 정확히 높이의 절반이었다.
/// `onTap` 이 null 이면 한도 도달 상태로, 흐리게 그리고 누름도 막는다.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.filled,
    this.onTap,
    this.height = FnHome.buttonH,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  /// 알약 높이. 시안 실측은 촬영 52.8dp / 앨범 56.9dp 로 서로 다르다.
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final bg = filled ? FnHome.coralFlat : FnHome.surfaceSoft;
    final fg = filled ? Colors.white : FnHome.tipDesc;
    final r = height / 2;

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(r),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(r),
              border: filled ? null : Border.all(color: FnHome.cardLine),
              boxShadow: filled && !disabled
                  ? const [
                      BoxShadow(
                        color: Color(0x33FF6D78),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 스캔 화면 히어로 일러스트 — 겹쳐 놓인 영수증 3장 + 뒤쪽 분홍 글로우.
///
/// 시안 실측:
///   전체 bbox 206.1 x 162.4 dp, 가로 중앙(화면 폭의 49.8%)
///   가운데 장이 가장 크고 똑바로, 좌/우 장은 기울어져 뒤에 깔린다
///   영수증 안쪽 줄 색 #F6C2C6
///   뒤쪽 글로우는 배경(#FEF9F5)보다 살짝 분홍 (#FFF5F3 ~ #FFF8F5)
class _ScanHeroArt extends StatelessWidget {
  const _ScanHeroArt();

  /// 시안 실측 폭/높이 (dp)
  static const double w = 206;
  static const double h = 162;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 뒤쪽 분홍 글로우 — 시안에서 배경보다 살짝 붉게 번져 있었다.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.05),
                  radius: 0.78,
                  colors: [
                    FnHome.coralFlat.withValues(alpha: 0.13),
                    FnHome.coralFlat.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // 왼쪽 장 (뒤) — 시안에서 왼쪽으로 기울어 깔려 있다
          Positioned(
            left: 0,
            top: 20,
            child: Transform.rotate(
              angle: -13 * math.pi / 180,
              child: const _ReceiptSheet(width: 74, height: 104, lines: 4),
            ),
          ),
          // 오른쪽 장 (뒤)
          Positioned(
            right: 0,
            top: 16,
            child: Transform.rotate(
              angle: 12 * math.pi / 180,
              child: const _ReceiptSheet(width: 74, height: 104, lines: 4),
            ),
          ),
          // 가운데 장 (맨 앞, 가장 큼)
          Positioned(
            top: 0,
            child: Transform.rotate(
              angle: -1.5 * math.pi / 180,
              child: const _ReceiptSheet(width: 86, height: 122, lines: 5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 일러스트 안 영수증 한 장.
/// 머리글 줄은 분홍(#F6C2C6), 본문 줄은 아주 옅은 회색.
class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({
    required this.width,
    required this.height,
    required this.lines,
  });

  final double width;
  final double height;
  final int lines;

  /// 본문 줄 너비 비율 — 시안 [86, 68, 78, 54]% 패턴을 이어 쓴다.
  static const _ratios = <double>[.86, .68, .78, .54, .72];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.14,
        vertical: height * 0.13,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22B45A69),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 머리글 줄 (분홍)
          FractionallySizedBox(
            widthFactor: .64,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFF6C2C6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          for (var i = 0; i < lines; i++) ...[
            SizedBox(height: height * 0.075),
            FractionallySizedBox(
              widthFactor: _ratios[i % _ratios.length],
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0x14171717),
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
