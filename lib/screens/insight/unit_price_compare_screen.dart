import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_input.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';
import '../../services/vendor_tax_service.dart';

/// 매입처별 단가 비교
class UnitPriceCompareScreen extends StatefulWidget {
  final String? itemName;
  const UnitPriceCompareScreen({super.key, this.itemName});

  @override
  State<UnitPriceCompareScreen> createState() => _UnitPriceCompareScreenState();
}

class _UnitPriceCompareScreenState extends State<UnitPriceCompareScreen> {
  final _won = NumberFormat('#,###');
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.itemName;
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final names = InsightService.topItemNames(receipts, 30);
    _selected ??= names.isNotEmpty ? names.first : null;

    final compares = _selected == null
        ? <VendorItemPrice>[]
        : InsightService.comparePrices(receipts, _selected!);
    final saving =
        _selected == null ? 0.0 : InsightService.potentialSaving(receipts, _selected!);

    return FnScaffold(
      title: '단가 비교',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (names.isEmpty)
            const FnEmptyState(
              message: '비교할 품목이 없습니다',
              icon: Icons.compare_arrows_rounded,
            )
          else ...[
            FnDropdown<String>(
              label: '품목 선택',
              value: _selected,
              items: names,
              itemLabel: (s) => s,
              onChanged: (v) => setState(() => _selected = v),
            ),
            const SizedBox(height: FnSpace.x16),

            if (compares.isEmpty)
              const FnCard(
                child: FnEmptyState(
                  message: '이 품목의 매입 기록이 없습니다',
                  icon: Icons.search_off_rounded,
                ),
              )
            else ...[
              // ── 최저가 하이라이트 ──
              FnHighlightCard(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.emoji_events_rounded,
                          size: 22, color: FnColors.primaryNormal),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('최저 단가 매입처',
                              style: FnType.caption1
                                  .copyWith(color: FnColors.labelAlternative)),
                          const SizedBox(height: 2),
                          Text(compares.first.vendor, style: FnType.title3),
                        ],
                      ),
                    ),
                    Text('${_won.format(compares.first.avgUnitPrice)}원',
                        style: FnType.heading1
                            .copyWith(color: FnColors.primaryNormal)),
                  ],
                ),
              ),
              const SizedBox(height: FnSpace.x12),

              if (saving > 1000)
                FnInfoBanner(
                  tone: FnBannerTone.positive,
                  icon: Icons.trending_down_rounded,
                  title: '연 ${_won.format(saving)}원 절감 가능',
                  body:
                      '동일 수량을 ${compares.first.vendor}에서 매입하면 그동안의 차액만큼 아낄 수 있었어요.',
                ),
              const SizedBox(height: FnSpace.x16),

              // ── 막대 비교 ──
              FnCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('매입처별 평균 단가', style: FnType.headline1),
                    const SizedBox(height: FnSpace.x16),
                    FnBarChart(
                      data: compares
                          .map((c) => FnChartDatum(
                                label: _short(c.vendor),
                                value: c.avgUnitPrice,
                                color: c == compares.first
                                    ? FnColors.taxExempt
                                    : FnColors.primaryNormal,
                              ))
                          .toList(),
                      height: 128,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FnSpace.x12),

              // ── 상세 리스트 ──
              FnCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (int i = 0; i < compares.length; i++) ...[
                      if (i > 0) FnDivider(indent: 14, endIndent: 14),
                      _row(compares[i], i, compares.first.avgUnitPrice),
                    ]
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(VendorItemPrice v, int rank, double best) {
    final diff = v.avgUnitPrice - best;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 0 ? FnColors.leaf95 : FnColors.fillNormal,
              shape: BoxShape.circle,
            ),
            child: Text('${rank + 1}',
                style: FnType.caption1.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      rank == 0 ? FnColors.leaf30 : FnColors.labelAlternative,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(v.vendor,
                          style: FnType.headline2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    v.taxType == TaxType.exempt
                        ? const FnBadge.taxExempt(size: FnBadgeSize.xsmall)
                        : const FnBadge.taxable(size: FnBadgeSize.xsmall),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${v.samples}회 매입 · ${_won.format(v.totalQty)}개',
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAlternative)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_won.format(v.avgUnitPrice)}원',
                  style: FnType.headline2),
              const SizedBox(height: 2),
              Text(
                diff <= 0 ? '최저가' : '+${_won.format(diff)}원',
                style: FnType.caption2.copyWith(
                  color:
                      diff <= 0 ? FnColors.taxExempt : FnColors.statusNegative,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _short(String s) => s.length > 5 ? '${s.substring(0, 4)}…' : s;
}
