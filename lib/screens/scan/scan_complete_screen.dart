import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../services/subscription_service.dart';
import 'scan_draft.dart';

final _won = NumberFormat('#,###');

/// 저장 완료 화면.
class ScanCompleteScreen extends StatefulWidget {
  const ScanCompleteScreen({super.key, required this.summary});

  final ScanSummary summary;

  @override
  State<ScanCompleteScreen> createState() => _ScanCompleteScreenState();
}

class _ScanCompleteScreenState extends State<ScanCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final sub = SubscriptionService.instance;

    return Scaffold(
      backgroundColor: FnColors.backgroundApp,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: FnColors.leaf95,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 48, color: FnColors.statusPositive),
              ),
            ),
            const SizedBox(height: FnSpace.x24),
            Text('${s.success}건 저장했어요', style: FnType.title2),
            const SizedBox(height: FnSpace.x8),
            Text(
              '캘린더와 내역에서 바로 확인할 수 있어요',
              style: FnType.body2.copyWith(color: FnColors.labelAlternative),
            ),
            const SizedBox(height: FnSpace.x32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FnSpace.x20),
              child: FnCard(
                child: Row(
                  children: [
                    _Stat(
                      label: '영수증',
                      value: '${s.success}건',
                      icon: Icons.receipt_long_rounded,
                    ),
                    const _VLine(),
                    _Stat(
                      label: '품목',
                      value: '${s.itemCount}개',
                      icon: Icons.local_florist_rounded,
                    ),
                    const _VLine(),
                    _Stat(
                      label: '합계',
                      value: '${_won.format(s.amount.round())}원',
                      icon: Icons.payments_rounded,
                      accent: true,
                    ),
                  ],
                ),
              ),
            ),
            if (s.failed > 0) ...[
              const SizedBox(height: FnSpace.x12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FnSpace.x20),
                child: Container(
                  padding: const EdgeInsets.all(FnSpace.x12),
                  decoration: BoxDecoration(
                    color: FnColors.statusCautionaryBg,
                    borderRadius: FnRadius.br12,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 18, color: FnColors.statusCautionary),
                      const SizedBox(width: FnSpace.x8),
                      Expanded(
                        child: Text(
                          '${s.failed}장은 인식하지 못해 저장하지 않았어요. 더 밝은 곳에서 다시 찍어보세요.',
                          style: FnType.caption1
                              .copyWith(color: FnColors.labelNeutral),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (sub.isFree) ...[
              const SizedBox(height: FnSpace.x12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FnSpace.x20),
                child: Text(
                  '이번 달 남은 무료 스캔 ${sub.scansLeft}건',
                  style: FnType.caption1
                      .copyWith(color: FnColors.labelAssistive),
                ),
              ),
            ],
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  FnSpace.x20, 0, FnSpace.x20, FnSpace.x20),
              child: Column(
                children: [
                  FnButton(
                    label: '내역 보러가기',
                    size: FnButtonSize.large,
                    expand: true,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                  const SizedBox(height: FnSpace.x8),
                  FnButton(
                    label: '계속 스캔하기',
                    variant: FnButtonVariant.text,
                    size: FnButtonSize.large,
                    expand: true,
                    onPressed: () => Navigator.pop(context),
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

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon,
              size: 18,
              color: accent
                  ? FnColors.primaryNormal
                  : FnColors.labelAlternative),
          const SizedBox(height: FnSpace.x6),
          FittedBox(
            child: Text(value,
                style: FnType.label1.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent
                      ? FnColors.primaryNormal
                      : FnColors.labelNormal,
                )),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: FnType.caption2
                  .copyWith(color: FnColors.labelAlternative)),
        ],
      ),
    );
  }
}

class _VLine extends StatelessWidget {
  const _VLine();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 36,
        color: FnColors.lineAlternative,
      );
}
