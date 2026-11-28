import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_input.dart';
import '../../design/fn_scaffold.dart';
import '../../models/receipt_model.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';
import 'unit_price_compare_screen.dart';

/// 시세 트래커 — 품목별 단가 추이
class PriceTrackerScreen extends StatefulWidget {
  const PriceTrackerScreen({super.key});

  @override
  State<PriceTrackerScreen> createState() => _PriceTrackerScreenState();
}

class _PriceTrackerScreenState extends State<PriceTrackerScreen> {
  final _won = NumberFormat('#,###');
  final _searchCtrl = TextEditingController();
  String _query = '';
  int _sortIdx = 0; // 0: 구매많은순, 1: 상승순, 2: 하락순

  static const _sorts = ['많이 구매', '가격 상승', '가격 하락'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    var items = InsightService.allItemSummaries(receipts, limit: 40);

    if (_query.isNotEmpty) {
      items = items
          .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
          .toList();
    }
    switch (_sortIdx) {
      case 1:
        items.sort((a, b) => b.changePercent.compareTo(a.changePercent));
        break;
      case 2:
        items.sort((a, b) => a.changePercent.compareTo(b.changePercent));
        break;
    }

    return FnScaffold(
      title: '시세 트래커',
      body: Column(
        children: [
          FnSearchBar(
            hint: '품목 검색 (예: 장미)',
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            onClear: () => setState(() => _query = ''),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          ),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _sorts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => FnFilterChip(
                label: _sorts[i],
                selected: _sortIdx == i,
                onTap: () => setState(() => _sortIdx = i),
              ),
            ),
          ),
          const SizedBox(height: FnSpace.x12),
          Expanded(
            child: items.isEmpty
                ? const FnEmptyState(
                    message: '표시할 품목이 없습니다',
                    subMessage: '영수증을 스캔하면 자동으로 시세가 쌓입니다',
                    icon: Icons.trending_up_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _itemCard(items[i], receipts),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(ItemPriceSummary s, List<ReceiptModel> receipts) {
    final chart = s.series
        .map((p) => FnChartDatum(label: p.label, value: p.avgUnitPrice))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FnCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UnitPriceCompareScreen(itemName: s.name),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(s.name,
                            style: FnType.heading2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      if (s.isBargain)
                        const FnBadge(
                          label: '저렴',
                          size: FnBadgeSize.xsmall,
                          color: FnBadgeColor.positive,
                        ),
                    ],
                  ),
                ),
                FnDeltaBadge(percent: s.changePercent),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${_won.format(s.current)}원', style: FnType.title3),
                const SizedBox(width: 6),
                Text('/ 단가',
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAssistive)),
                const Spacer(),
                Text(
                  '누적 ${_won.format(s.totalSpend)}원',
                  style: FnType.caption1
                      .copyWith(color: FnColors.labelAlternative),
                ),
              ],
            ),
            const SizedBox(height: FnSpace.x12),
            if (chart.length >= 2)
              FnLineChart(
                data: chart,
                height: 84,
                color: s.isUp ? FnColors.statusNegative : FnColors.taxExempt,
              )
            else
              Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FnColors.fillNormal,
                  borderRadius: FnRadius.br10,
                ),
                child: Text('추이를 보려면 2개월 이상 데이터가 필요합니다',
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAssistive)),
              ),
            const SizedBox(height: FnSpace.x12),
            Row(
              children: [
                _miniStat('최저', s.min),
                _vLine(),
                _miniStat('평균', s.average),
                _vLine(),
                _miniStat('최고', s.max),
                _vLine(),
                Expanded(
                  child: Column(
                    children: [
                      Text('구매량',
                          style: FnType.caption2
                              .copyWith(color: FnColors.labelAssistive)),
                      const SizedBox(height: 2),
                      Text(_won.format(s.totalQty),
                          style: FnType.label1Normal),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, double v) => Expanded(
        child: Column(
          children: [
            Text(label,
                style:
                    FnType.caption2.copyWith(color: FnColors.labelAssistive)),
            const SizedBox(height: 2),
            Text(_won.format(v), style: FnType.label1Normal),
          ],
        ),
      );

  Widget _vLine() => Container(
        width: 1,
        height: 22,
        color: FnColors.lineNeutral,
      );
}
