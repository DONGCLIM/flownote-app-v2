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
import 'unit_price_compare_screen.dart';

/// 월별 인사이트 — 한 달 매입을 리포트 형태로 요약
class MonthlyInsightScreen extends StatefulWidget {
  const MonthlyInsightScreen({super.key});

  @override
  State<MonthlyInsightScreen> createState() => _MonthlyInsightScreenState();
}

class _MonthlyInsightScreenState extends State<MonthlyInsightScreen> {
  final _won = NumberFormat('#,###');
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final available = InsightService.monthlyStats(receipts);

    final monthReceipts = receipts
        .where((r) =>
            r.date.year == _month.year && r.date.month == _month.month)
        .toList();

    final stat = InsightService.statFor(receipts, _month.year, _month.month);
    final prev = InsightService.statFor(
        receipts,
        _month.month == 1 ? _month.year - 1 : _month.year,
        _month.month == 1 ? 12 : _month.month - 1);

    final delta = (prev == null || prev.total == 0 || stat == null)
        ? 0.0
        : (stat.total - prev.total) / prev.total * 100;

    return FnScaffold(
      title: '월별 인사이트',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _monthPicker(available),
          const SizedBox(height: FnSpace.x16),

          if (stat == null)
            const FnEmptyState(
              message: '이 달의 매입 내역이 없습니다',
              subMessage: '다른 달을 선택하거나 영수증을 스캔해 보세요',
              icon: Icons.event_busy_rounded,
            )
          else ...[
            // ── 헤드라인 ──
            FnHighlightCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${_month.month}월 총 매입액',
                          style: FnType.body2
                              .copyWith(color: FnColors.labelAlternative)),
                      const Spacer(),
                      if (prev != null) FnDeltaBadge(percent: delta),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${_won.format(stat.total)}원', style: FnType.display2),
                  const SizedBox(height: FnSpace.x16),
                  Row(
                    children: [
                      _headStat('매입 건수', '${stat.count}건'),
                      _vline(),
                      _headStat('건당 평균',
                          '${_won.format(stat.avgPerReceipt)}원'),
                      _vline(),
                      _headStat('부가세', '${_won.format(stat.vat)}원'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: FnSpace.x12),

            // ── 자동 코멘트 ──
            ..._comments(stat, prev, monthReceipts, receipts),

            const SizedBox(height: FnSpace.x20),
            const FnSectionHeader(title: '면세 / 과세'),
            const SizedBox(height: FnSpace.x8),
            FnCard(
              child: Row(
                children: [
                  FnDonutChart(
                    data: [
                      FnChartDatum(
                          label: '면세',
                          value: stat.exempt,
                          color: FnColors.taxExempt),
                      FnChartDatum(
                          label: '과세',
                          value: stat.taxable,
                          color: FnColors.taxable),
                    ],
                    size: 104,
                    thickness: 20,
                  ),
                  const SizedBox(width: FnSpace.x20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dotRow('면세 (생화)', stat.exempt, FnColors.taxExempt,
                            stat.exemptRatio),
                        const SizedBox(height: 12),
                        _dotRow('과세 (부자재)', stat.taxable, FnColors.taxable,
                            stat.taxableRatio),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: FnSpace.x20),
            const FnSectionHeader(title: '매입처 TOP'),
            const SizedBox(height: FnSpace.x8),
            _vendorList(monthReceipts),

            const SizedBox(height: FnSpace.x20),
            const FnSectionHeader(title: '많이 산 품목'),
            const SizedBox(height: FnSpace.x8),
            _itemList(monthReceipts),

            const SizedBox(height: FnSpace.x20),
            const FnSectionHeader(title: '최근 6개월 흐름'),
            const SizedBox(height: FnSpace.x8),
            _trend(receipts, stat),
          ],
        ],
      ),
    );
  }

  // ── parts ───────────────────────────────────────────

  Widget _monthPicker(List<MonthStat> available) {
    if (available.isEmpty) return const SizedBox.shrink();
    final labels = available.reversed.toList();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = labels[i];
          final sel = m.year == _month.year && m.month == _month.month;
          return FnFilterChip(
            label: '${m.year % 100}.${m.month.toString().padLeft(2, '0')}',
            selected: sel,
            onTap: () => setState(() => _month = DateTime(m.year, m.month)),
          );
        },
      ),
    );
  }

  Widget _headStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: FnType.caption2
                    .copyWith(color: FnColors.labelAssistive)),
            const SizedBox(height: 3),
            FittedBox(child: Text(value, style: FnType.headline2)),
          ],
        ),
      );

  Widget _vline() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: FnColors.lineNeutral,
      );

  Widget _dotRow(String label, double v, Color c, double ratio) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: FnType.caption1
                      .copyWith(color: FnColors.labelAlternative)),
              const Spacer(),
              Text('${(ratio * 100).round()}%',
                  style: FnType.caption1.copyWith(
                      color: c, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 3),
          Text('${_won.format(v)}원', style: FnType.headline2),
        ],
      );

  List<Widget> _comments(MonthStat stat, MonthStat? prev,
      List<ReceiptModel> monthReceipts, List<ReceiptModel> all) {
    final out = <Widget>[];

    if (prev != null && prev.total > 0) {
      final d = stat.total - prev.total;
      final pct = (d / prev.total * 100);
      if (pct.abs() >= 8) {
        out.add(FnInfoBanner(
          tone: d > 0 ? FnBannerTone.cautionary : FnBannerTone.positive,
          icon: d > 0
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          title: d > 0
              ? '전월 대비 ${pct.abs().toStringAsFixed(0)}% 증가'
              : '전월 대비 ${pct.abs().toStringAsFixed(0)}% 절감',
          body: d > 0
              ? '${_won.format(d.abs())}원 더 썼습니다. 단가가 오른 품목을 확인해 보세요.'
              : '${_won.format(d.abs())}원 아꼈습니다. 좋은 흐름이에요.',
        ));
        out.add(const SizedBox(height: 8));
      }
    }

    if (stat.vat > 0) {
      out.add(FnInfoBanner(
        tone: FnBannerTone.neutral,
        icon: Icons.receipt_long_outlined,
        title: '매입세액 ${_won.format(stat.vat)}원',
        body: '과세 매입처 세금계산서를 챙기면 부가세 신고 시 공제받을 수 있습니다.',
      ));
      out.add(const SizedBox(height: 8));
    }

    // 절감 기회
    final names = InsightService.topItemNames(monthReceipts, 5);
    for (final n in names) {
      final saving = InsightService.potentialSaving(all, n);
      if (saving > 20000) {
        final cheapest = InsightService.comparePrices(all, n).first;
        out.add(FnInfoBanner(
          tone: FnBannerTone.positive,
          icon: Icons.lightbulb_outline_rounded,
          title: '$n · ${_won.format(saving)}원 절감 여지',
          body: '${cheapest.vendor}가 평균 ${_won.format(cheapest.avgUnitPrice)}원으로 가장 저렴합니다.',
        ));
        out.add(const SizedBox(height: 8));
        break;
      }
    }

    return out;
  }

  Widget _vendorList(List<ReceiptModel> monthReceipts) {
    final vendors = InsightService.vendorSummaries(monthReceipts);
    if (vendors.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '매입처 데이터 없음', icon: Icons.storefront_outlined),
      );
    }
    final total = vendors.fold<double>(0, (s, v) => s + v.total);
    return FnCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < vendors.length; i++) ...[
            if (i > 0) const FnDivider(indent: 14, endIndent: 14),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? FnColors.primaryNormal
                          : FnColors.fillNormal,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: FnType.caption2.copyWith(
                          fontWeight: FontWeight.w700,
                          color: i == 0
                              ? Colors.white
                              : FnColors.labelAlternative,
                        )),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(vendors[i].name,
                              style: FnType.headline2,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        vendors[i].taxType == TaxType.exempt
                            ? const FnBadge.taxExempt(
                                size: FnBadgeSize.xsmall)
                            : const FnBadge.taxable(size: FnBadgeSize.xsmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_won.format(vendors[i].total)}원',
                          style: FnType.headline2),
                      Text(
                          '${vendors[i].count}건 · ${total == 0 ? 0 : (vendors[i].total / total * 100).round()}%',
                          style: FnType.caption2
                              .copyWith(color: FnColors.labelAssistive)),
                    ],
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _itemList(List<ReceiptModel> monthReceipts) {
    final qty = <String, int>{};
    final spend = <String, double>{};
    for (final r in monthReceipts) {
      for (final it in r.items) {
        qty[it.name] = (qty[it.name] ?? 0) + it.quantity;
        spend[it.name] = (spend[it.name] ?? 0) + it.totalPrice;
      }
    }
    if (qty.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '품목 데이터 없음', icon: Icons.local_florist_outlined),
      );
    }
    final sorted = spend.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();

    return FnCard(
      child: Column(
        children: [
          FnBarChart(
            data: top
                .map((e) => FnChartDatum(
                    label: e.key.length > 4
                        ? '${e.key.substring(0, 3)}…'
                        : e.key,
                    value: e.value))
                .toList(),
            height: 116,
          ),
          const FnDivider(height: 20),
          ...top.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          UnitPriceCompareScreen(itemName: e.key),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: FnType.body2)),
                      Text('${_won.format(qty[e.key])}개',
                          style: FnType.caption1
                              .copyWith(color: FnColors.labelAlternative)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 82,
                        child: Text('${_won.format(e.value)}원',
                            textAlign: TextAlign.right,
                            style: FnType.headline2),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: FnColors.labelAssistive),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _trend(List<ReceiptModel> receipts, MonthStat current) {
    final months = InsightService.recentMonths(receipts, 6);
    if (months.length < 2) {
      return const FnCard(
        child: FnEmptyState(
            message: '2개월 이상 데이터가 필요합니다',
            icon: Icons.show_chart_rounded),
      );
    }
    final idx = months.indexWhere((m) => m.key == current.key);
    return FnCard(
      child: FnBarChart(
        data: months
            .map((m) => FnChartDatum(label: m.label, value: m.total))
            .toList(),
        height: 130,
        activeIndex: idx >= 0 ? idx : null,
        onBarTap: (i) => setState(
            () => _month = DateTime(months[i].year, months[i].month)),
      ),
    );
  }
}
