import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';
import 'unit_price_compare_screen.dart';

/// 스마트 사입 가이드 — 지금 사기 좋은 / 미루면 좋은 품목 추천
class PurchaseGuideScreen extends StatelessWidget {
  const PurchaseGuideScreen({super.key});

  static final _won = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final guide = InsightService.purchaseGuide(receipts);
    final now = DateTime.now();

    final totalSaving = guide.buy.fold<double>(
      0,
      (s, e) => s + ((e.average - e.current) * (e.totalQty / 6)).clamp(0, 1e9),
    );

    return FnScaffold(
      title: '스마트 사입 가이드',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── 헤더 ──
          FnHighlightCard(
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 23, color: FnColors.primaryNormal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${now.month}월 사입 추천', style: FnType.heading1),
                      const SizedBox(height: 3),
                      Text(
                        totalSaving > 1000
                            ? '이번 달 약 ${_won.format(totalSaving)}원 절감 기회'
                            : '내 매입 기록으로 분석한 결과입니다',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x20),

          if (guide.buy.isEmpty && guide.wait.isEmpty)
            const FnEmptyState(
              message: '아직 분석할 데이터가 부족합니다',
              subMessage: '2개월 이상 매입 기록이 쌓이면 추천을 시작합니다',
              icon: Icons.auto_awesome_outlined,
            ),

          // ── 지금 사세요 ──
          if (guide.buy.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: FnColors.leaf95,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.thumb_up_alt_rounded,
                      size: 14, color: FnColors.taxExempt),
                ),
                const SizedBox(width: 8),
                Text('지금 사기 좋아요', style: FnType.heading1),
                const SizedBox(width: 6),
                FnBadge(
                  label: '${guide.buy.length}',
                  size: FnBadgeSize.xsmall,
                  color: FnBadgeColor.positive,
                ),
              ],
            ),
            const SizedBox(height: FnSpace.x10),
            ...guide.buy.map((s) => _card(context, s, true)),
            const SizedBox(height: FnSpace.x20),
          ],

          // ── 조금 기다리세요 ──
          if (guide.wait.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: FnColors.rose95,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule_rounded,
                      size: 14, color: FnColors.statusNegative),
                ),
                const SizedBox(width: 8),
                Text('가격이 올랐어요', style: FnType.heading1),
                const SizedBox(width: 6),
                FnBadge(
                  label: '${guide.wait.length}',
                  size: FnBadgeSize.xsmall,
                  color: FnBadgeColor.negative,
                ),
              ],
            ),
            const SizedBox(height: FnSpace.x10),
            ...guide.wait.map((s) => _card(context, s, false)),
          ],

          const SizedBox(height: FnSpace.x20),
          const FnInfoBanner(
            tone: FnBannerTone.neutral,
            icon: Icons.info_outline_rounded,
            title: '추천 기준',
            body: '최근 월평균 단가와 직전 달을 비교하고, 전체 평균 대비 5% 이상 저렴하면 매수 추천으로 분류합니다.',
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ItemPriceSummary s, bool isBuy) {
    final accent = isBuy ? FnColors.taxExempt : FnColors.statusNegative;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                Container(
                  width: 4,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: FnType.heading2),
                      const SizedBox(height: 2),
                      Text(
                        isBuy
                            ? '평균 ${_won.format(s.average)}원 대비 저렴'
                            : '평균 ${_won.format(s.average)}원 대비 비쌈',
                        style: FnType.caption1
                            .copyWith(color: FnColors.labelAlternative),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${_won.format(s.current)}원',
                        style: FnType.headline1),
                    const SizedBox(height: 3),
                    FnDeltaBadge(percent: s.changePercent),
                  ],
                ),
              ],
            ),
            const SizedBox(height: FnSpace.x12),
            FnLineChart(
              data: s.series
                  .map((p) =>
                      FnChartDatum(label: p.label, value: p.avgUnitPrice))
                  .toList(),
              height: 62,
              color: accent,
              showLabels: false,
            ),
            const SizedBox(height: FnSpace.x10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isBuy ? FnColors.leaf95 : FnColors.rose95,
                borderRadius: FnRadius.br10,
              ),
              child: Row(
                children: [
                  Icon(
                    isBuy
                        ? Icons.lightbulb_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isBuy
                          ? '지금 매입하면 개당 ${_won.format((s.average - s.current).abs())}원 절약'
                          : '전월 대비 ${s.changePercent.abs().toStringAsFixed(0)}% 상승 · 대체 품목 검토 권장',
                      style: FnType.caption1.copyWith(
                          color: isBuy ? FnColors.leaf30 : FnColors.rose30),
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
