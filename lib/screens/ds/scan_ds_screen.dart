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
/// ```
/// Shell(navTitle:'스캔', tabs, activeTab:'scan')
///   div padding:20 column gap:26
///     Card (bordered 아님, shadow) textAlign:center padding:'32px 16px'
///       div 56x56 r28 background blue-95, margin '0 auto 14px'  → Icon Camera 26
///       div wds-heading2 mb14 fontWeight600     '오늘 촬영한 영수증 0장'
///       div 14/400 label-alternative mb18       '이번 달 무료 스캔 N/M장 사용'
///       Button large  width100%                 '촬영하기'
///       Button large outlined width100% mt8     '갤러리에서 선택'
///     Card bordered  background blue-99, inset 1px blue-90
///       header: [20x20 r10 blue-50 흰'!' 12/800] gap8 mb12 + '촬영 전 스캔 팁' 18
///       3행: [✓ blue-50 15/800] [제목 15/600] / [설명 13.5 lh1.5 label-alternative]
///            padding '9px 0', 첫 행 제외 borderTop 1px line-normal-neutral
/// ```
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
        FnCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: FnColors.rose95, // blue-95
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 26,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '오늘 촬영한 영수증 $todayCount장',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: FnColors.labelNormal,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                sub.purchasedPro
                    ? 'PRO · 스캔 무제한'
                    : sub.isPro
                        ? '스캔 무제한 · 이번 달 $used장 스캔'
                        : '이번 달 무료 스캔 $used/$cap장 사용',
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
          color: FnColors.rose99, // blue-99
          borderColor: FnColors.rose90, // blue-90
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: FnColors.primaryNormal,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '!',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
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
                      fontWeight: FontWeight.w700,
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
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Text(
                          '✓',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: FnColors.primaryNormal,
                          ),
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
