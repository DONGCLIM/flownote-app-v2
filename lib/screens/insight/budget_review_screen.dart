import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_badge.dart';
import '../../design/fn_button.dart';
import '../../design/fn_card.dart';
import '../../design/fn_chart.dart';
import '../../design/fn_input.dart';
import '../../design/fn_list.dart';
import '../../design/fn_scaffold.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';

/// 예산 검토 — 이번 달 매입 예산 대비 집행 현황
class BudgetReviewScreen extends StatefulWidget {
  const BudgetReviewScreen({super.key});

  @override
  State<BudgetReviewScreen> createState() => _BudgetReviewScreenState();
}

class _BudgetReviewScreenState extends State<BudgetReviewScreen> {
  static const _kBudget = 'fn_monthly_budget';

  final _won = NumberFormat('#,###');
  double _budget = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _budget = p.getDouble(_kBudget) ?? 0;
      _loaded = true;
    });
  }

  Future<void> _saveBudget(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kBudget, v);
    if (mounted) setState(() => _budget = v);
  }

  @override
  Widget build(BuildContext context) {
    final receipts = context.watch<ReceiptProvider>().allReceipts;
    final now = DateTime.now();

    final thisMonth = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .toList();
    final spent = thisMonth.fold<double>(0, (s, r) => s + r.totalAmount);
    final projected = InsightService.projectedMonthEnd(receipts);
    final avg3 = InsightService.averageMonthlySpend(receipts, months: 3);

    // 예산 미설정 시 최근 3개월 평균을 추천값으로
    final budget = _budget > 0 ? _budget : avg3;
    final ratio = budget == 0 ? 0.0 : (spent / budget);
    final remain = budget - spent;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day;
    final dailyAllowance = daysLeft > 0 && remain > 0 ? remain / daysLeft : 0.0;

    final status = _status(ratio, projected, budget);

    if (!_loaded) {
      return const FnScaffold(
        title: '예산 검토',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FnScaffold(
      title: '예산 검토',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // ── 게이지 ──
          FnCard(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
            child: Column(
              children: [
                Text('${now.month}월 매입 예산',
                    style: FnType.body2
                        .copyWith(color: FnColors.labelAlternative)),
                const SizedBox(height: FnSpace.x16),
                SizedBox(
                  height: 132,
                  child: CustomPaint(
                    painter: _GaugePainter(
                      ratio: ratio.clamp(0.0, 1.3),
                      color: status.color,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(ratio * 100).round()}%',
                              style: FnType.display2
                                  .copyWith(color: status.color)),
                          const SizedBox(height: 2),
                          Text('집행률',
                              style: FnType.caption1
                                  .copyWith(color: FnColors.labelAssistive)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FnSpace.x16),
                FnBadge(
                  label: status.label,
                  color: status.badge,
                  size: FnBadgeSize.medium,
                  icon: status.icon,
                ),
                const SizedBox(height: FnSpace.x20),
                Row(
                  children: [
                    _stat('사용', spent, FnColors.labelNormal),
                    Container(
                        width: 1, height: 34, color: FnColors.lineNeutral),
                    _stat('남음', remain < 0 ? 0 : remain,
                        remain < 0 ? FnColors.statusNegative : FnColors.taxExempt),
                    Container(
                        width: 1, height: 34, color: FnColors.lineNeutral),
                    _stat('예산', budget, FnColors.labelAlternative),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          // ── 예산 설정 ──
          FnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('월 예산 설정', style: FnType.headline1),
                    const Spacer(),
                    if (_budget == 0)
                      const FnBadge(
                        label: '추천값 적용중',
                        size: FnBadgeSize.xsmall,
                        color: FnBadgeColor.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: FnSpace.x12),
                Row(
                  children: [
                    Expanded(
                      child: Text('${_won.format(budget)}원',
                          style: FnType.title2),
                    ),
                    FnButton(
                      label: '변경',
                      size: FnButtonSize.small,
                      variant: FnButtonVariant.outlined,
                      onPressed: () => _editBudget(budget),
                    ),
                  ],
                ),
                const SizedBox(height: FnSpace.x8),
                Text('최근 3개월 평균 ${_won.format(avg3)}원',
                    style: FnType.caption1
                        .copyWith(color: FnColors.labelAlternative)),
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          // ── 월말 예측 ──
          FnCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('월말 예상', style: FnType.headline1),
                const SizedBox(height: FnSpace.x16),
                FnKeyValueRow(
                  label: '현재 페이스 기준 예상 매입액',
                  value: '${_won.format(projected)}원',
                  emphasize: true,
                  valueColor:
                      projected > budget ? FnColors.statusNegative : FnColors.taxExempt,
                ),
                const SizedBox(height: FnSpace.x12),
                FnProgressBar(
                  value: budget == 0 ? 0 : (projected / budget).clamp(0, 1),
                  color: projected > budget
                      ? FnColors.statusNegative
                      : FnColors.taxExempt,
                  height: 8,
                ),
                const SizedBox(height: FnSpace.x12),
                if (projected > budget)
                  Text(
                    '이대로면 예산을 ${_won.format(projected - budget)}원 초과합니다.',
                    style: FnType.caption1
                        .copyWith(color: FnColors.statusNegative),
                  )
                else
                  Text(
                    '예산 내에서 ${_won.format(budget - projected)}원 여유가 예상됩니다.',
                    style:
                        FnType.caption1.copyWith(color: FnColors.taxExempt),
                  ),
                if (daysLeft > 0 && remain > 0) ...[
                  FnDivider(height: 20),
                  FnKeyValueRow(
                    label: '남은 $daysLeft일 · 하루 권장 매입액',
                    value: '${_won.format(dailyAllowance)}원',
                    emphasize: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FnSpace.x12),

          if (status.tip != null)
            FnInfoBanner(
              tone: status.tone,
              icon: status.icon,
              title: status.label,
              body: status.tip!,
            ),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '최근 6개월 매입 추이'),
          const SizedBox(height: FnSpace.x8),
          _trendCard(receipts, budget),

          const SizedBox(height: FnSpace.x20),
          const FnSectionHeader(title: '이번 달 매입처별 비중'),
          const SizedBox(height: FnSpace.x8),
          _vendorCard(thisMonth),
        ],
      ),
    );
  }

  // ── parts ───────────────────────────────────────────

  Widget _stat(String label, double v, Color c) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: FnType.caption1
                    .copyWith(color: FnColors.labelAssistive)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text('${_won.format(v)}원',
                  style: FnType.headline1.copyWith(color: c)),
            ),
          ],
        ),
      );

  Widget _trendCard(List receipts, double budget) {
    final months = InsightService.recentMonths(receipts.cast(), 6);
    if (months.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '데이터가 없습니다', icon: Icons.show_chart_rounded),
      );
    }
    return FnCard(
      child: Column(
        children: [
          FnBarChart(
            data: months
                .map((m) => FnChartDatum(
                      label: m.label,
                      value: m.total,
                      color: budget > 0 && m.total > budget
                          ? FnColors.statusNegative
                          : FnColors.primaryNormal,
                    ))
                .toList(),
            height: 130,
          ),
          if (budget > 0) ...[
            const SizedBox(height: FnSpace.x12),
            Row(
              children: [
                Container(width: 14, height: 2, color: FnColors.statusNegative),
                const SizedBox(width: 6),
                Text('예산 초과 월',
                    style: FnType.caption2
                        .copyWith(color: FnColors.labelAlternative)),
                const Spacer(),
                Text(
                  '초과 ${months.where((m) => m.total > budget).length}회 / ${months.length}개월',
                  style: FnType.caption2
                      .copyWith(color: FnColors.labelAlternative),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _vendorCard(List monthReceipts) {
    final vendors = InsightService.vendorSummaries(monthReceipts.cast());
    if (vendors.isEmpty) {
      return const FnCard(
        child: FnEmptyState(
            message: '이번 달 매입 내역이 없습니다',
            icon: Icons.storefront_outlined),
      );
    }
    final total = vendors.fold<double>(0, (s, v) => s + v.total);
    return FnCard(
      child: Column(
        children: [
          for (int i = 0; i < vendors.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(vendors[i].name, style: FnType.body2)),
                    Text('${_won.format(vendors[i].total)}원',
                        style: FnType.headline2),
                  ],
                ),
                const SizedBox(height: 6),
                FnProgressBar(
                  value: total == 0 ? 0 : vendors[i].total / total,
                  color: i == 0
                      ? FnColors.primaryNormal
                      : FnColors.primaryNormal.withValues(alpha: 0.45),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // ── actions ─────────────────────────────────────────

  Future<void> _editBudget(double current) async {
    final ctrl = TextEditingController(
        text: current > 0 ? _won.format(current) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('월 예산 설정'),
        content: FnAmountField(
          controller: ctrl,
          hint: '0',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () {
              final v = double.tryParse(
                      ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                  0;
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null) await _saveBudget(result);
  }

  _BudgetStatus _status(double ratio, double projected, double budget) {
    if (budget == 0) {
      return const _BudgetStatus(
        label: '예산 미설정',
        color: FnColors.labelAlternative,
        badge: FnBadgeColor.neutral,
        tone: FnBannerTone.neutral,
        icon: Icons.help_outline_rounded,
        tip: '월 예산을 설정하면 집행률과 월말 예상 초과액을 알려드립니다.',
      );
    }
    if (ratio >= 1.0) {
      return const _BudgetStatus(
        label: '예산 초과',
        color: FnColors.statusNegative,
        badge: FnBadgeColor.negative,
        tone: FnBannerTone.accent,
        icon: Icons.warning_amber_rounded,
        tip: '이번 달 예산을 이미 초과했습니다. 남은 기간 매입을 조정해 보세요.',
      );
    }
    if (projected > budget) {
      return const _BudgetStatus(
        label: '초과 위험',
        color: FnColors.statusCautionary,
        badge: FnBadgeColor.cautionary,
        tone: FnBannerTone.cautionary,
        icon: Icons.trending_up_rounded,
        tip: '현재 페이스가 유지되면 월말에 예산을 넘습니다. 매입 주기를 늘리는 것을 권장합니다.',
      );
    }
    if (ratio < 0.5) {
      return const _BudgetStatus(
        label: '여유',
        color: FnColors.taxExempt,
        badge: FnBadgeColor.positive,
        tone: FnBannerTone.positive,
        icon: Icons.check_circle_outline_rounded,
        tip: '예산 대비 여유가 있습니다. 시세가 낮은 품목을 미리 확보하기 좋은 시점이에요.',
      );
    }
    return const _BudgetStatus(
      label: '정상 범위',
      color: FnColors.taxExempt,
      badge: FnBadgeColor.positive,
      tone: FnBannerTone.positive,
      icon: Icons.check_circle_outline_rounded,
      tip: null,
    );
  }
}

class _BudgetStatus {
  final String label;
  final Color color;
  final FnBadgeColor badge;
  final FnBannerTone tone;
  final IconData icon;
  final String? tip;

  const _BudgetStatus({
    required this.label,
    required this.color,
    required this.badge,
    required this.tone,
    required this.icon,
    this.tip,
  });
}

/// 반원 게이지
class _GaugePainter extends CustomPainter {
  final double ratio;
  final Color color;

  _GaugePainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      (size.height - stroke) * 2,
    );

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = FnColors.fillNormal;

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(rect, math.pi, math.pi, false, bg);
    canvas.drawArc(
        rect, math.pi, math.pi * ratio.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.ratio != ratio || old.color != color;
}
