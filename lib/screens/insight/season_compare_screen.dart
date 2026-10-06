import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';

/// 시즌 매입 비교 — 같은 달을 연도별로 비교
class SeasonCompareScreen extends StatefulWidget {
  const SeasonCompareScreen({super.key});

  @override
  State<SeasonCompareScreen> createState() => _SeasonCompareScreenState();
}

class _SeasonCompareScreenState extends State<SeasonCompareScreen> {
  final _won = NumberFormat('#,###');
  late int _month;

  static const _seasonNote = {
    1: '신년 · 졸업 시즌 준비',
    2: '졸업 · 발렌타인 성수기',
    3: '입학 · 졸업 시즌 마무리',
    4: '봄 웨딩 시즌 시작',
    5: '어버이날 · 스승의날 최대 성수기',
    6: '초여름 웨딩 시즌',
    7: '비수기 · 여름 관리 주의',
    8: '비수기 · 냉방비 증가',
    9: '가을 웨딩 시즌 시작',
    10: '가을 웨딩 · 행사 성수기',
    11: '수능 · 연말 준비',
    12: '연말 · 크리스마스 성수기',
  };

  @override
  void initState() {
    super.initState();
    _month = DateTime.now().month;
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final stats = InsightService.sameMonthAcrossYears(receipts, _month);
    final allMonths = InsightService.monthlyStats(receipts);

    return FnScaffold(
      title: '시즌 매입 비교',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── 월 선택 ──
          FnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('비교할 월', style: FnType.headline1),
                const SizedBox(height: FnSpace.x12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    return FnFilterChip(
                      label: '$m월',
                      selected: _month == m,
                      onTap: () => setState(() => _month = m),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          FnInfoBanner(
            tone: FnBannerTone.neutral,
            icon: Icons.event_note_rounded,
            title: '$_month월 시즌 특성',
            body: _seasonNote[_month] ?? '',
          ),
          const SizedBox(height: FnSpace.x20),

          if (stats.isEmpty)
            const FnEmptyState(
              message: '해당 월의 매입 기록이 없습니다',
              icon: Icons.compare_arrows_rounded,
            )
          else ...[
            const FnSectionHeader(title: '연도별 매입액'),
            const SizedBox(height: FnSpace.x8),
            FnCard(
              child: FnBarChart(
                data: stats
                    .map((s) => FnChartDatum(
                          label: '${s.year % 100}년',
                          value: s.total,
                        ))
                    .toList(),
                height: 136,
              ),
            ),
            const SizedBox(height: FnSpace.x12),

            ..._yoyCards(stats),

            const SizedBox(height: FnSpace.x20),
            const FnSectionHeader(title: '연중 매입 패턴'),
            const SizedBox(height: FnSpace.x8),
            _yearPattern(allMonths),
          ],
        ],
      ),
    );
  }

  List<Widget> _yoyCards(List<MonthStat> stats) {
    final out = <Widget>[];
    for (int i = 0; i < stats.length; i++) {
      final s = stats[i];
      final prev = i > 0 ? stats[i - 1] : null;
      final delta = (prev == null || prev.total == 0)
          ? null
          : (s.total - prev.total) / prev.total * 100;

      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${s.year}년 $_month월', style: FnType.heading2),
                  const SizedBox(width: 8),
                  if (i == stats.length - 1)
                    const FnBadge(
                      label: '최근',
                      size: FnBadgeSize.xsmall,
                      color: FnBadgeColor.accent,
                    ),
                  const Spacer(),
                  if (delta != null) FnDeltaBadge(percent: delta),
                ],
              ),
              const SizedBox(height: 8),
              Text('${_won.format(s.total)}원', style: FnType.title3),
              const FnDivider(height: 18),
              Row(
                children: [
                  _cell('매입 건수', '${s.count}건'),
                  _vline(),
                  _cell('건당 평균', '${_won.format(s.avgPerReceipt)}원'),
                  _vline(),
                  _cell('면세 비중',
                      '${(s.exemptRatio * 100).round()}%'),
                ],
              ),
              if (delta != null) ...[
                const SizedBox(height: FnSpace.x12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: delta > 0 ? FnColors.rose95 : FnColors.leaf95,
                    borderRadius: FnRadius.br10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        delta > 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 15,
                        color: delta > 0
                            ? FnColors.statusNegative
                            : FnColors.taxExempt,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          delta > 0
                              ? '전년 대비 ${_won.format(s.total - prev!.total)}원 증가'
                              : '전년 대비 ${_won.format(prev!.total - s.total)}원 절감',
                          style: FnType.caption1.copyWith(
                            color: delta > 0
                                ? FnColors.rose30
                                : FnColors.leaf30,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ));
    }
    return out;
  }

  Widget _cell(String label, String value) => Expanded(
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
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: FnColors.lineNeutral,
      );

  Widget _yearPattern(List<MonthStat> all) {
    // 월별 평균 (여러 해가 있으면 평균)
    final byMonth = <int, List<double>>{};
    for (final s in all) {
      byMonth.putIfAbsent(s.month, () => []).add(s.total);
    }
    if (byMonth.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '데이터 없음', icon: Icons.calendar_month_rounded),
      );
    }
    final data = List.generate(12, (i) {
      final m = i + 1;
      final list = byMonth[m];
      final avg = list == null || list.isEmpty
          ? 0.0
          : list.reduce((a, b) => a + b) / list.length;
      return FnChartDatum(
        label: '$m',
        value: avg,
        color: m == _month ? FnColors.primaryNormal : FnColors.rose70,
      );
    });

    final peak = data.reduce((a, b) => a.value > b.value ? a : b);

    return FnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FnBarChart(data: data, height: 124),
          const SizedBox(height: FnSpace.x12),
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 15, color: FnColors.primaryNormal),
              const SizedBox(width: 6),
              Text('성수기: ${peak.label}월',
                  style: FnType.caption1
                      .copyWith(color: FnColors.labelAlternative)),
              const Spacer(),
              Text('월평균 ${_won.format(peak.value)}원',
                  style: FnType.caption1
                      .copyWith(color: FnColors.labelAlternative)),
            ],
          ),
        ],
      ),
    );
  }
}
