import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../design/fn_tokens.dart';
import '../design/fn_button.dart';
import '../design/fn_card.dart';
import '../design/fn_badge.dart';
import '../design/fn_chart.dart';
import '../providers/auth_provider.dart';
import '../providers/receipt_provider.dart';
import '../services/subscription_service.dart';
import '../services/notification_service.dart';
import 'scan/scan_flow.dart';
import 'paywall_screen.dart';
import 'insight/insight_hub.dart';

final _won = NumberFormat('#,###');

/// 스캔 탭 — 촬영 진입점 + 이번 달 스캔 현황.
///
/// 실제 촬영 → 인식 → 검토 파이프라인은 [ScanFlow] 가 담당하고,
/// 이 화면은 진입 UI 와 사용량 안내만 맡는다.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => ScanScreenState();
}

class ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final NotificationService _notif = NotificationService();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notif.requestPermission();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// MainScreen 에서 스캔 탭을 다시 누르면 호출된다.
  Future<void> showCameraOptions() => _start();

  Future<void> _start() async {
    await ScanFlow.start(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sub = SubscriptionService.instance;
    final user = context.watch<AuthProvider>().currentUser;
    final receipts = context.watch<ReceiptProvider>().allReceipts;

    final now = DateTime.now();
    final thisMonth = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final monthTotal = thisMonth.fold(0.0, (s, r) => s + r.totalAmount);

    return Scaffold(
      backgroundColor: FnColors.backgroundApp,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnSpace.x20, FnSpace.x16, FnSpace.x20, FnSpace.x32),
          children: [
            // 헤더
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('영수증 스캔', style: FnType.title2),
                      const SizedBox(height: FnSpace.x4),
                      Text(
                        '사진 한 장이면 품목·단가까지 정리돼요',
                        style: FnType.body2
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ),
                ),
                // 🔴 AI 설정 톱니 버튼 제거 (사장님 요청).
                //    화면 파일과 저장된 키/프롬프트/모델은 그대로 살아 있다.
              ],
            ),
            const SizedBox(height: FnSpace.x24),

            // 메인 CTA
            _ScanCta(pulse: _pulse, onTap: _start),
            const SizedBox(height: FnSpace.x16),

            // 보조 액션
            Row(
              children: [
                Expanded(
                  child: FnButton(
                    label: '앨범에서 고르기',
                    variant: FnButtonVariant.outlined,
                    size: FnButtonSize.large,
                    expand: true,
                    leadingIcon: Icons.photo_library_rounded,
                    onPressed: _start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FnSpace.x24),

            // 사용량
            _UsageCard(
              sub: sub,
              legacyRemaining: user?.remainingScans,
              onUpgrade: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
            ),
            const SizedBox(height: FnSpace.x16),

            // 이번 달 현황
            FnCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${now.month}월 스캔 현황', style: FnType.heading2),
                      const Spacer(),
                      FnBadge(
                        label: '${thisMonth.length}건',
                        color: FnBadgeColor.accent,
                        size: FnBadgeSize.xsmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: FnSpace.x16),
                  Row(
                    children: [
                      Expanded(
                        child: _Metric(
                          label: '매입 합계',
                          value: '${_won.format(monthTotal.round())}원',
                          accent: true,
                        ),
                      ),
                      Container(
                          width: 1,
                          height: 34,
                          color: FnColors.lineAlternative),
                      Expanded(
                        child: _Metric(
                          label: '건당 평균',
                          value: thisMonth.isEmpty
                              ? '-'
                              : '${_won.format((monthTotal / thisMonth.length).round())}원',
                        ),
                      ),
                    ],
                  ),
                  if (thisMonth.isNotEmpty) ...[
                    const SizedBox(height: FnSpace.x16),
                    FnProgressBar(
                      value: (thisMonth.length / 20).clamp(0.0, 1.0),
                      color: FnColors.primaryNormal,
                    ),
                    const SizedBox(height: FnSpace.x8),
                    Text(
                      '이번 달 ${thisMonth.length}장 기록했어요',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FnSpace.x24),

            // 잘 찍는 법
            Text('잘 찍는 법', style: FnType.heading2),
            const SizedBox(height: FnSpace.x10),
            const _Tip(
              icon: Icons.wb_sunny_rounded,
              title: '밝은 곳에서 찍기',
              body: '그림자가 지지 않게 조명 아래에서 촬영하면 인식률이 올라가요.',
            ),
            const _Tip(
              icon: Icons.crop_free_rounded,
              title: '영수증 전체가 들어오게',
              body: '위아래가 잘리면 합계를 못 읽어요. 여백을 조금 남겨주세요.',
            ),
            const _Tip(
              icon: Icons.burst_mode_rounded,
              title: '여러 장은 연속 촬영으로',
              body: '한 번에 찍고 나중에 한꺼번에 검토하면 훨씬 빨라요.',
            ),
            const SizedBox(height: FnSpace.x24),

            // 분석 바로가기
            const FeatureQuickBar(),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── 부품

class _ScanCta extends StatelessWidget {
  const _ScanCta({required this.pulse, required this.onTap});

  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: FnRadius.br20,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [FnColors.rose50, FnColors.rose40],
          ),
          boxShadow: [
            BoxShadow(
              color: FnColors.primaryNormal.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: -24,
              bottom: -40,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (context, child) => Transform.scale(
                      scale: 0.96 + pulse.value * 0.08,
                      child: child,
                    ),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded,
                          size: 34, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: FnSpace.x16),
                  const Text(
                    '영수증 찍기',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: FnSpace.x4),
                  Text(
                    '탭해서 바로 시작',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.sub,
    required this.onUpgrade,
    this.legacyRemaining,
  });

  final SubscriptionService sub;
  final VoidCallback onUpgrade;
  final int? legacyRemaining;

  @override
  Widget build(BuildContext context) {
    if (sub.isPro) {
      return FnCard(
        color: FnColors.leaf95,
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                size: 22, color: FnColors.statusPositiveStrong),
            const SizedBox(width: FnSpace.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 결제하지 않았는데 "PRO 이용 중" 이라고 하면 거짓말이 된다.
                  // 지금은 전체 기능이 열려 있는 상태라고 정직하게 알린다.
                  Text(sub.purchasedPro ? 'PRO 이용 중' : '모든 기능 이용 중',
                      style: FnType.heading2),
                  const SizedBox(height: 2),
                  Text('스캔 무제한 · 한 번에 ${sub.burstLimit}장까지',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelNeutral)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final left = sub.scansLeft;
    final used = PlanPolicy.freeMonthlyScans - left;
    final ratio = (used / PlanPolicy.freeMonthlyScans).clamp(0.0, 1.0);
    final low = left <= 10;

    return FnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('이번 달 무료 스캔', style: FnType.heading2),
              const Spacer(),
              Text(
                '$left회 남음',
                style: FnType.label1.copyWith(
                  fontWeight: FontWeight.w700,
                  color: low
                      ? FnColors.statusNegative
                      : FnColors.primaryNormal,
                ),
              ),
            ],
          ),
          const SizedBox(height: FnSpace.x12),
          FnProgressBar(
            value: ratio,
            color: low ? FnColors.statusNegative : FnColors.primaryNormal,
          ),
          const SizedBox(height: FnSpace.x8),
          Text(
            '$used / ${PlanPolicy.freeMonthlyScans}회 사용',
            style: FnType.caption1.copyWith(color: FnColors.labelAlternative),
          ),
          if (low) ...[
            const SizedBox(height: FnSpace.x14),
            FnButton(
              label: 'PRO로 제한 없이 쓰기',
              size: FnButtonSize.medium,
              expand: true,
              leadingIcon: Icons.bolt_rounded,
              onPressed: onUpgrade,
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          child: Text(value,
              style: FnType.heading1.copyWith(
                color:
                    accent ? FnColors.primaryNormal : FnColors.labelNormal,
              )),
        ),
        const SizedBox(height: FnSpace.x4),
        Text(label,
            style:
                FnType.caption1.copyWith(color: FnColors.labelAlternative)),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FnSpace.x8),
      child: FnCard(
        bordered: true,
        radius: FnRadius.r14,
        padding: const EdgeInsets.all(FnSpace.x14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: FnColors.rose95,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: FnColors.primaryNormal),
            ),
            const SizedBox(width: FnSpace.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: FnType.label1
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
