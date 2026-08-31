import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/fn_tokens.dart';
import '../design/fn_badge.dart';
import '../design/fn_button.dart';
import '../design/fn_card.dart';
import '../design/fn_list.dart';
import '../design/fn_scaffold.dart';
import '../services/subscription_service.dart';

/// 구독 안내 (Paywall)
class PaywallScreen extends StatefulWidget {
  final String? reason;
  const PaywallScreen({super.key, this.reason});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  static final _won = NumberFormat('#,###');
  bool _yearly = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final sub = SubscriptionService.instance;
    final price =
        _yearly ? PlanPolicy.yearlyPrice : PlanPolicy.monthlyPrice;
    final perMonth = _yearly ? PlanPolicy.yearlyPrice / 12 : price.toDouble();

    return FnScaffold(
      title: 'FlowNote PRO',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (widget.reason != null) ...[
            FnInfoBanner(
              tone: FnBannerTone.cautionary,
              icon: Icons.lock_outline_rounded,
              title: '업그레이드가 필요합니다',
              body: widget.reason!,
            ),
            const SizedBox(height: FnSpace.x16),
          ],

          // ── 히어로 ──
          FnHighlightCard(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      size: 30, color: FnColors.primaryNormal),
                ),
                const SizedBox(height: FnSpace.x16),
                Text('매입 관리, 이제 자동으로', style: FnType.title3),
                const SizedBox(height: 6),
                Text(
                  sub.purchasedPro
                      ? 'PRO 이용 중입니다'
                      : '무료 체험 ${sub.trialDaysLeft}일 남음',
                  style: FnType.body2
                      .copyWith(color: FnColors.labelAlternative),
                ),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x20),

          // ── 요금제 선택 ──
          _planTile(
            selected: _yearly,
            title: '연간 결제',
            price: '${_won.format(PlanPolicy.yearlyPrice)}원 / 년',
            sub: '월 ${_won.format(PlanPolicy.yearlyPrice / 12)}원 · 2개월 무료',
            badge: '2개월 무료',
            onTap: () => setState(() => _yearly = true),
          ),
          const SizedBox(height: 8),
          _planTile(
            selected: !_yearly,
            title: '월간 결제',
            price: '${_won.format(PlanPolicy.monthlyPrice)}원 / 월',
            sub: '언제든 해지 가능',
            onTap: () => setState(() => _yearly = false),
          ),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: 'PRO 혜택'),
          const SizedBox(height: FnSpace.x8),
          FnCard(
            child: Column(
              children: [
                for (int i = 0; i < PlanPolicy.proFeatures.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  FnCheckItem(text: PlanPolicy.proFeatures[i]),
                ]
              ],
            ),
          ),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: 'FREE vs PRO'),
          const SizedBox(height: FnSpace.x8),
          FnCard(
            child: Column(
              children: [
                _compareHeader(),
                const FnDivider(height: 16),
                _compareRow('월 스캔',
                    '${PlanPolicy.freeMonthlyScans}장', '무제한'),
                const SizedBox(height: 12),
                _compareRow('연속 촬영',
                    '${PlanPolicy.freeBurstLimit}장', '${PlanPolicy.proBurstLimit}장'),
                const SizedBox(height: 12),
                _compareRow(
                    '정산서 발송', '${PlanPolicy.freeExports}회', '무제한'),
                const SizedBox(height: 12),
                _compareRow('월간 리포트', '—', '자동 생성'),
                const SizedBox(height: 12),
                _compareRow('시세 트래커', '—', '제공'),
              ],
            ),
          ),

          const SizedBox(height: FnSpace.x12),
          Text(
            '· 구독은 언제든 해지할 수 있으며, 해지 시 다음 결제일까지 이용 가능합니다.\n'
            '· 표시 금액은 부가세 포함 기준입니다.',
            style: FnType.caption2.copyWith(color: FnColors.labelAssistive),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: FnColors.lineNeutral)),
        ),
        child: SafeArea(
          top: false,
          child: sub.purchasedPro
              ? FnButton.cta(
                  label: 'PRO 이용 중',
                  onPressed: null,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_won.format(perMonth)}원 / 월 상당',
                      style: FnType.caption1
                          .copyWith(color: FnColors.labelAlternative),
                    ),
                    const SizedBox(height: 8),
                    FnButton.cta(
                      label: 'PRO 시작하기',
                      loading: _busy,
                      onPressed: _busy ? null : _upgrade,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _planTile({
    required bool selected,
    required String title,
    required String price,
    required String sub,
    String? badge,
    required VoidCallback onTap,
  }) {
    return FnCard(
      onTap: onTap,
      bordered: selected,
      borderColor: FnColors.primaryNormal,
      color: selected ? FnColors.rose99 : Colors.white,
      child: Row(
        children: [
          FnRadio<bool>(
            value: selected,
            groupValue: true,
            onChanged: (_) => onTap(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: FnType.heading2),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      FnBadge(
                        label: badge,
                        size: FnBadgeSize.xsmall,
                        color: FnBadgeColor.accent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(sub,
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAlternative)),
              ],
            ),
          ),
          Text(price, style: FnType.headline1),
        ],
      ),
    );
  }

  Widget _compareHeader() => Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(
            flex: 2,
            child: Text('FREE',
                textAlign: TextAlign.center,
                style: FnType.caption1
                    .copyWith(color: FnColors.labelAlternative)),
          ),
          Expanded(
            flex: 2,
            child: Text('PRO',
                textAlign: TextAlign.center,
                style: FnType.caption1.copyWith(
                    color: FnColors.primaryNormal,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      );

  Widget _compareRow(String label, String free, String pro) => Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: FnType.body2)),
          Expanded(
            flex: 2,
            child: Text(free,
                textAlign: TextAlign.center,
                style: FnType.caption1
                    .copyWith(color: FnColors.labelAssistive)),
          ),
          Expanded(
            flex: 2,
            child: Text(pro,
                textAlign: TextAlign.center,
                style: FnType.label1Normal
                    .copyWith(color: FnColors.primaryNormal)),
          ),
        ],
      );

  Future<void> _upgrade() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await SubscriptionService.instance.upgradeToPro();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PRO 구독이 시작되었습니다')),
    );
    Navigator.of(context).pop(true);
  }
}
