import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../models/receipt_model.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';
import '../../services/vendor_tax_service.dart';

/// 면세 / 과세 비중 화면
class TaxRatioScreen extends StatefulWidget {
  const TaxRatioScreen({super.key});

  @override
  State<TaxRatioScreen> createState() => _TaxRatioScreenState();
}

class _TaxRatioScreenState extends State<TaxRatioScreen> {
  final _won = NumberFormat('#,###');
  int _rangeIdx = 1; // 0: 이번달, 1: 3개월, 2: 6개월, 3: 전체
  int? _activeSlice;

  static const _ranges = ['이번 달', '3개월', '6개월', '전체'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReceiptProvider>();
    final all = provider.allReceipts;
    final filtered = _filter(all);

    final bd = InsightService.taxBreakdown(filtered);
    final total = bd.exempt + bd.taxable;

    final donut = <FnChartDatum>[
      FnChartDatum(label: '면세', value: bd.exempt, color: FnColors.taxExempt),
      FnChartDatum(label: '과세', value: bd.taxable, color: FnColors.taxable),
    ];

    return FnScaffold(
      title: '면세 / 과세 비중',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _rangeSelector(),
          const SizedBox(height: FnSpace.x16),

          // ── 도넛 ──
          FnCard(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: total == 0
                ? const FnEmptyState(
                    message: '해당 기간에 매입 내역이 없습니다',
                    icon: Icons.pie_chart_outline_rounded,
                  )
                : Column(
                    children: [
                      FnDonutChart(
                        data: donut,
                        size: 168,
                        thickness: 28,
                        activeIndex: _activeSlice,
                        onSliceTap: (i) => setState(
                            () => _activeSlice = _activeSlice == i ? null : i),
                        center: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _activeSlice == null
                                  ? '총 매입'
                                  : donut[_activeSlice!].label,
                              style: FnType.label2.copyWith(
                                  color: FnColors.labelAlternative),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _activeSlice == null
                                  ? '${_won.format(total)}원'
                                  : '${(donut[_activeSlice!].value / total * 100).toStringAsFixed(1)}%',
                              style: FnType.heading2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: FnSpace.x20),
                      FnChartLegend(
                        data: donut,
                        activeIndex: _activeSlice,
                        showPercent: true,
                        onTap: (i) => setState(
                            () => _activeSlice = _activeSlice == i ? null : i),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: FnSpace.x12),

          // ── 요약 수치 ──
          FnCard(
            child: Column(
              children: [
                _amountRow('면세 매입 (생화)', bd.exempt, FnColors.taxExempt,
                    total == 0 ? 0 : bd.exempt / total),
                FnDivider(height: 20),
                _amountRow('과세 매입 (부자재)', bd.taxable, FnColors.taxable,
                    total == 0 ? 0 : bd.taxable / total),
                FnDivider(height: 20),
                FnKeyValueRow(
                  label: '공급가액 합계',
                  value: '${_won.format(bd.exempt + (bd.taxable - bd.vat))}원',
                ),
                const SizedBox(height: 8),
                FnKeyValueRow(
                  label: '부가세 (환급 대상)',
                  value: '${_won.format(bd.vat)}원',
                  valueColor: FnColors.primaryNormal,
                  emphasize: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          if (bd.vat > 0)
            FnInfoBanner(
              tone: FnBannerTone.positive,
              icon: Icons.savings_outlined,
              title: '부가세 ${_won.format(bd.vat)}원 환급 가능',
              body: '과세 매입처에서 받은 세금계산서를 챙기면 이 금액만큼 매입세액 공제를 받을 수 있어요.',
            ),
          const SizedBox(height: FnSpace.x20),

          const FnSectionHeader(title: '매입처별 과세 구분'),
          const SizedBox(height: FnSpace.x8),
          ..._vendorCards(filtered),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '월별 면세 / 과세 추이'),
          const SizedBox(height: FnSpace.x8),
          _monthlyStack(all),
        ],
      ),
    );
  }

  // ── UI parts ─────────────────────────────────────────

  Widget _rangeSelector() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _ranges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FnFilterChip(
          label: _ranges[i],
          selected: _rangeIdx == i,
          onTap: () => setState(() {
            _rangeIdx = i;
            _activeSlice = null;
          }),
        ),
      ),
    );
  }

  Widget _amountRow(String label, double value, Color color, double ratio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: FnType.body2),
            const Spacer(),
            Text('${_won.format(value)}원', style: FnType.headline2),
          ],
        ),
        const SizedBox(height: 8),
        FnProgressBar(value: ratio, color: color, height: 6),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${(ratio * 100).toStringAsFixed(1)}%',
              style: FnType.caption1
                  .copyWith(color: FnColors.labelAlternative)),
        ),
      ],
    );
  }

  List<Widget> _vendorCards(List<ReceiptModel> receipts) {
    final vendors = InsightService.vendorSummaries(receipts);
    if (vendors.isEmpty) {
      return [
        const FnCard(
          child: FnEmptyState(
            message: '매입처 데이터가 없습니다',
            icon: Icons.storefront_outlined,
          ),
        )
      ];
    }
    return vendors.map((v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FnCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: v.taxType == TaxType.exempt
                      ? FnColors.leaf95
                      : FnColors.rose95,
                  borderRadius: FnRadius.br12,
                ),
                child: Icon(
                  v.taxType == TaxType.exempt
                      ? Icons.local_florist_outlined
                      : Icons.inventory_2_outlined,
                  size: 19,
                  color: v.taxType == TaxType.exempt
                      ? FnColors.taxExempt
                      : FnColors.taxable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: FnType.headline2),
                    const SizedBox(height: 2),
                    Text('${v.count}건 · ${_won.format(v.total)}원',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await VendorTaxService.instance.toggle(v.name);
                  if (mounted) setState(() {});
                },
                child: v.taxType == TaxType.exempt
                    ? const FnBadge.taxExempt()
                    : const FnBadge.taxable(),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _monthlyStack(List<ReceiptModel> receipts) {
    final months = InsightService.recentMonths(receipts, 6);
    if (months.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '표시할 데이터가 없습니다',
            icon: Icons.bar_chart_rounded),
      );
    }
    final maxV =
        months.map((m) => m.total).reduce((a, b) => a > b ? a : b);
    return FnCard(
      child: Column(
        children: months.map((m) {
          final w = maxV == 0 ? 0.0 : m.total / maxV;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(m.label,
                          style: FnType.caption1
                              .copyWith(color: FnColors.labelAlternative)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 10,
                          child: Row(
                            children: [
                              Expanded(
                                flex: (m.exempt * 1000).round().clamp(0, 1 << 30),
                                child: Container(color: FnColors.taxExempt),
                              ),
                              Expanded(
                                flex:
                                    (m.taxable * 1000).round().clamp(0, 1 << 30),
                                child: Container(color: FnColors.taxable),
                              ),
                              if (m.total < maxV)
                                Expanded(
                                  flex: ((maxV - m.total) * 1000)
                                      .round()
                                      .clamp(0, 1 << 30),
                                  child: Container(color: FnColors.fillNormal),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 70,
                      child: Text(
                        _won.format(m.total),
                        textAlign: TextAlign.right,
                        style: FnType.caption1,
                      ),
                    ),
                  ],
                ),
                if (w > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, top: 4),
                    child: Text(
                      '면세 ${(m.exemptRatio * 100).toStringAsFixed(0)}% · 과세 ${(m.taxableRatio * 100).toStringAsFixed(0)}%',
                      style: FnType.caption2
                          .copyWith(color: FnColors.labelAssistive),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── helpers ──────────────────────────────────────────

  List<ReceiptModel> _filter(List<ReceiptModel> all) {
    final now = DateTime.now();
    switch (_rangeIdx) {
      case 0:
        return all
            .where((r) => r.date.year == now.year && r.date.month == now.month)
            .toList();
      case 1:
        final from = DateTime(now.year, now.month - 2, 1);
        return all.where((r) => !r.date.isBefore(from)).toList();
      case 2:
        final from = DateTime(now.year, now.month - 5, 1);
        return all.where((r) => !r.date.isBefore(from)).toList();
      default:
        return all;
    }
  }
}
