import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/receipt_provider.dart';
import '../theme/app_theme.dart';
import '../models/receipt_model.dart';
import 'insight/insight_hub.dart';

typedef TabSwitcher = void Function(int index);

class HomeScreen extends StatefulWidget {
  final TabSwitcher? onTabSwitch;
  const HomeScreen({super.key, this.onTabSwitch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _insightMonth;

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final months = rp.availableMonths;
    final now = DateTime.now();
    final selectedMonth = _insightMonth ?? DateTime(now.year, now.month);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(onTabSwitch: widget.onTabSwitch)),
            SliverToBoxAdapter(child: _ThisMonthCard(onTabSwitch: widget.onTabSwitch)),
            // 신규 기능 퀵 진입
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            const SliverToBoxAdapter(child: FeatureQuickBar()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            // ① 월별 지출 추이
            SliverToBoxAdapter(child: _MonthlyBarChart(onTabSwitch: widget.onTabSwitch)),
            // ② 업체별 구매 비중
            SliverToBoxAdapter(child: _VendorShareSection(onTabSwitch: widget.onTabSwitch)),
            // ③ 주요 품목 시세 트래커
            SliverToBoxAdapter(child: _PriceTrendSection(onTabSwitch: widget.onTabSwitch)),
            // ④ 전년 동월 비교
            SliverToBoxAdapter(child: _YoYCompareSection(onTabSwitch: widget.onTabSwitch)),
            // ⑤ 월별 인사이트 (한 장 요약)
            SliverToBoxAdapter(
              child: _InsightCard(
                months: months,
                selected: selectedMonth,
                onSelect: (m) => setState(() => _insightMonth = m),
                onTabSwitch: widget.onTabSwitch,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ── 헤더 ──────────────────────────────────────────────
class _Header extends StatelessWidget {
  final TabSwitcher? onTabSwitch;
  const _Header({this.onTabSwitch});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final now = DateTime.now();
    final monthFmt = DateFormat('yyyy년 M월', 'ko');
    final greeting = now.hour < 12 ? '좋은 아침이에요' : now.hour < 18 ? '안녕하세요' : '좋은 저녁이에요';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text('${user?.name ?? ''}님 🌸',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(monthFmt.format(now),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => onTabSwitch?.call(2),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: const Center(child: Icon(Icons.document_scanner_outlined, color: Colors.white, size: 22)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 이번 달 카드 ──────────────────────────────────────
class _ThisMonthCard extends StatelessWidget {
  final TabSwitcher? onTabSwitch;
  const _ThisMonthCard({this.onTabSwitch});

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final fmt = NumberFormat('#,###', 'ko');
    final now = DateTime.now();

    final thisTotal = rp.getMonthTotal(now.year, now.month);
    final prevTotal = rp.getMonthTotal(
        now.month == 1 ? now.year - 1 : now.year,
        now.month == 1 ? 12 : now.month - 1);
    final lastYearTotal = rp.getMonthTotal(now.year - 1, now.month);
    final thisCount = rp.getMonthCount(now.year, now.month);

    final momPct = prevTotal == 0 ? null : (thisTotal - prevTotal) / prevTotal * 100;
    final yoyPct = lastYearTotal == 0 ? null : (thisTotal - lastYearTotal) / lastYearTotal * 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => onTabSwitch?.call(1),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.secondary.withValues(alpha: 0.08)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('이번 달 총 지출', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const Spacer(),
              Text('내역 보기 →', style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.7))),
            ]),
            const SizedBox(height: 4),
            Text('₩${fmt.format(thisTotal)}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Row(children: [
              _PctBadge(label: '전월 대비', pct: momPct),
              const SizedBox(width: 8),
              _PctBadge(label: '작년 동월 대비', pct: yoyPct),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: Text('$thisCount건', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PctBadge extends StatelessWidget {
  final String label;
  final double? pct;
  const _PctBadge({required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    if (pct == null) return const SizedBox.shrink();
    final up = pct! >= 0;
    final color = up ? AppColors.error : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('$label ${up ? '▲' : '▼'}${pct!.abs().toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── ① 월별 지출 추이 ──────────────────────────────────
class _MonthlyBarChart extends StatefulWidget {
  final TabSwitcher? onTabSwitch;
  const _MonthlyBarChart({this.onTabSwitch});

  @override
  State<_MonthlyBarChart> createState() => _MonthlyBarChartState();
}

class _MonthlyBarChartState extends State<_MonthlyBarChart> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final months = rp.availableMonths;
    if (months.isEmpty) return const SizedBox.shrink();

    final totals = {for (final m in months) m: rp.getMonthTotal(m.year, m.month)};
    final maxVal = totals.values.reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    final displayMonths = _expanded ? months : months.reversed.take(4).toList().reversed.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              const Text('📊 월별 지출 추이',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Text(_expanded ? '접기' : '전체 보기',
                  style: TextStyle(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.7))),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.primary.withValues(alpha: 0.7), size: 18),
            ]),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final count = displayMonths.length;
            final spacing = 8.0;
            final totalSpacing = spacing * (count - 1);
            final barW = ((constraints.maxWidth - totalSpacing) / count).clamp(24.0, 80.0);

            return SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: displayMonths.map((m) {
                  final val = totals[m]!;
                  final ratio = maxVal == 0 ? 0.0 : val / maxVal;
                  final isCurrent = m.year == now.year && m.month == now.month;
                  final isSpring = m.month == 3 || m.month == 4;
                  final barColor = isCurrent
                      ? AppColors.primary
                      : isSpring
                          ? AppColors.primary.withValues(alpha: 0.65)
                          : AppColors.primary.withValues(alpha: 0.35);
                  final wan = (val / 10000).round();

                  return GestureDetector(
                    onTap: () => widget.onTabSwitch?.call(3),
                    child: SizedBox(
                      width: barW,
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(
                          wan >= 100 ? '${(wan / 100).toStringAsFixed(1)}백' : '만',
                          style: TextStyle(
                            fontSize: 9,
                            color: isCurrent ? AppColors.primary : AppColors.textHint,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: barW * 0.6,
                          height: (95 * ratio + 6).clamp(6.0, 95.0),
                          decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(5)),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${m.year.toString().substring(2)}.${m.month.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                            color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            );
          }),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Row(children: [
              _Legend(color: AppColors.primary, label: '이번 달'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.primary.withValues(alpha: 0.65), label: '봄 성수기'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.primary.withValues(alpha: 0.35), label: '기타'),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
      ]);
}

// ── ② 업체별 구매 비중 ────────────────────────────────
class _VendorShareSection extends StatelessWidget {
  final TabSwitcher? onTabSwitch;
  const _VendorShareSection({this.onTabSwitch});

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final share = rp.vendorShare;
    if (share.isEmpty) return const SizedBox.shrink();

    final total = share.values.reduce((a, b) => a + b);
    final sorted = share.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final colors = [AppColors.primary, AppColors.secondary, AppColors.accent, const Color(0xFFE8A87C), const Color(0xFF8DA9C4)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🏪 업체별 구매 비중',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => onTabSwitch?.call(1),
              child: Text('내역 보기 →', style: TextStyle(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.7))),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 88, height: 88,
              child: CustomPaint(painter: _DonutPainter(values: sorted.map((e) => e.value).toList(), colors: colors)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: sorted.take(5).toList().asMap().entries.map((entry) {
                  final idx = entry.key;
                  final e = entry.value;
                  final pct = e.value / total * 100;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(color: colors[idx % colors.length], borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(e.key.length > 9 ? '${e.key.substring(0, 9)}..' : e.key,
                            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                      ),
                      Text('${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.reduce((a, b) => a + b);
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width / 2 - 4;
    double start = -3.14159 / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 3.14159 * 2;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start, sweep, false,
        Paint()..color = colors[i % colors.length]..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.butt,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start, 0.01, false,
        Paint()..color = AppColors.surface..style = PaintingStyle.stroke..strokeWidth = 2,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => false;
}

// ── ③ 주요 품목 시세 트래커 ──────────────────────────
class _PriceTrendSection extends StatefulWidget {
  final TabSwitcher? onTabSwitch;
  const _PriceTrendSection({this.onTabSwitch});

  @override
  State<_PriceTrendSection> createState() => _PriceTrendSectionState();
}

class _PriceTrendSectionState extends State<_PriceTrendSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final costMap = rp.itemMonthlyCost;
    if (costMap.isEmpty) return const SizedBox.shrink();

    final topItemNames = rp.topItems(_expanded ? 6 : 3).map((e) => e.key).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              const Text('📈 주요 품목 시세 트래커',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Text(_expanded ? '접기' : '더보기',
                  style: TextStyle(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.7))),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.primary.withValues(alpha: 0.7), size: 18),
            ]),
          ),
          const SizedBox(height: 4),
          const Text('구매 빈도 상위 품목 · 월별 평균 단가',
              style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 12),
          ...topItemNames.map((name) {
            final monthly = costMap[name];
            if (monthly == null || monthly.isEmpty) return const SizedBox.shrink();
            final sortedKeys = monthly.keys.toList()..sort();
            final prices = sortedKeys.map((k) => monthly[k]!).toList();
            final latest = prices.last;
            final avg = prices.reduce((a, b) => a + b) / prices.length;
            final diffPct = (latest - avg) / avg * 100;
            return _PriceTrendRow(
              name: name,
              sortedKeys: sortedKeys,
              prices: prices,
              latest: latest,
              avg: avg,
              diffPct: diffPct,
              onTap: () => widget.onTabSwitch?.call(1),
            );
          }),
        ]),
      ),
    );
  }
}

class _PriceTrendRow extends StatelessWidget {
  final String name;
  final List<String> sortedKeys;
  final List<double> prices;
  final double latest, avg, diffPct;
  final VoidCallback? onTap;
  const _PriceTrendRow({
    required this.name, required this.sortedKeys, required this.prices,
    required this.latest, required this.avg, required this.diffPct, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###', 'ko');
    final isHigh = diffPct > 5;
    final isLow = diffPct < -5;
    final tagColor = isHigh ? AppColors.error : isLow ? AppColors.accent : AppColors.textHint;
    final tagLabel = isHigh ? '⚠ 상승' : isLow ? '✓ 저렴' : '보통';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isHigh ? AppColors.error.withValues(alpha: 0.25) : isLow ? AppColors.accent.withValues(alpha: 0.25) : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(tagLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: tagColor)),
            ),
          ]),
          const SizedBox(height: 8),
          // 꺾은선 + 월 레이블
          _MiniChart(prices: prices, labels: sortedKeys),
          const SizedBox(height: 6),
          Row(children: [
            Text('현재 ₩${fmt.format(latest.round())}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            Text('평균 ₩${fmt.format(avg.round())}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const Spacer(),
            Text('${diffPct >= 0 ? '+' : ''}${diffPct.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: isHigh ? AppColors.error : isLow ? AppColors.accent : AppColors.textSecondary)),
          ]),
        ]),
      ),
    );
  }
}

class _MiniChart extends StatelessWidget {
  final List<double> prices;
  final List<String> labels;
  const _MiniChart({required this.prices, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (prices.length < 2) return const SizedBox.shrink();
    // 레이블: 첫·마지막, 가운데
    final showIdx = <int>{0, prices.length - 1};
    if (prices.length >= 4) showIdx.add(prices.length ~/ 2);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 40,
        child: CustomPaint(painter: _LinePainter(prices: prices), child: const SizedBox.expand()),
      ),
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(prices.length, (i) {
          if (!showIdx.contains(i)) return const Spacer();
          final raw = labels[i];
          final parts = raw.split('-');
          final lbl = parts.length == 2 ? "${parts[0].substring(2)}.${parts[1]}" : raw;
          return Text(lbl, style: const TextStyle(fontSize: 9, color: AppColors.textHint));
        }),
      ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<double> prices;
  _LinePainter({required this.prices});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = prices.reduce((a, b) => a < b ? a : b);
    final maxV = prices.reduce((a, b) => a > b ? a : b);
    final range = maxV - minV == 0 ? 1.0 : maxV - minV;

    final pts = List.generate(prices.length, (i) => Offset(
      i / (prices.length - 1) * size.width,
      size.height - (prices[i] - minV) / range * (size.height - 8) - 4,
    ));

    final area = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) area.lineTo(p.dx, p.dy);
    area..lineTo(pts.last.dx, size.height)..close();
    canvas.drawPath(area, Paint()..color = AppColors.primary.withValues(alpha: 0.08)..style = PaintingStyle.fill);

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) line.lineTo(pts[i].dx, pts[i].dy);
    canvas.drawPath(line, Paint()..color = AppColors.primary..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    canvas.drawCircle(pts.last, 3.5, Paint()..color = AppColors.primary..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.prices != prices;
}

// ── ④ 전년 동월 비교 ──────────────────────────────────
class _YoYCompareSection extends StatelessWidget {
  final TabSwitcher? onTabSwitch;
  const _YoYCompareSection({this.onTabSwitch});

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    final now = DateTime.now();
    final fmt = NumberFormat('#,###', 'ko');

    final thisTotal = rp.getMonthTotal(now.year, now.month);
    final lastTotal = rp.getMonthTotal(now.year - 1, now.month);
    if (lastTotal == 0) return const SizedBox.shrink();

    final thisCount = rp.getMonthCount(now.year, now.month);
    final lastCount = rp.getMonthCount(now.year - 1, now.month);

    double avgPrice(List<ReceiptModel> rs) {
      final ps = <double>[];
      for (final r in rs) for (final it in r.items) ps.add(it.unitPrice);
      return ps.isEmpty ? 0 : ps.reduce((a, b) => a + b) / ps.length;
    }

    final thisAvg = avgPrice(rp.allReceipts.where((r) => r.date.year == now.year && r.date.month == now.month).toList());
    final lastAvg = avgPrice(rp.allReceipts.where((r) => r.date.year == now.year - 1 && r.date.month == now.month).toList());
    final monthName = DateFormat('M월', 'ko').format(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GestureDetector(
        onTap: () => onTabSwitch?.call(1),
        child: Container(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Text('📅 작년 $monthName vs 올해 $monthName',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                Text('내역 보기 →', style: TextStyle(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.7))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1.5), 2: FlexColumnWidth(1.5), 3: FlexColumnWidth(1.1)},
                children: [
                  _hdr(),
                  _row('총 지출', '₩${fmt.format(lastTotal)}', '₩${fmt.format(thisTotal)}', thisTotal, lastTotal),
                  _row('구매 건수', '$lastCount건', '$thisCount건', thisCount.toDouble(), lastCount.toDouble()),
                  _row('평균 단가', '₩${fmt.format(lastAvg.round())}', '₩${fmt.format(thisAvg.round())}', thisAvg, lastAvg),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  TableRow _hdr() => TableRow(
    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
    children: ['항목', '작년', '올해', '변화'].map((t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
    )).toList(),
  );

  TableRow _row(String label, String lv, String tv, double tn, double ln) {
    final pct = ln == 0 ? 0.0 : (tn - ln) / ln * 100;
    final up = pct >= 0;
    final c = up ? AppColors.error : AppColors.accent;
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary))),
        Padding(padding: const EdgeInsets.all(8), child: Text(lv, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
        Padding(padding: const EdgeInsets.all(8), child: Text(tv, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
        Padding(padding: const EdgeInsets.all(8), child: Text('${up ? '▲' : '▼'}${pct.abs().toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c))),
      ],
    );
  }
}

// ── ⑤ 월별 인사이트 (한 장 요약 카드) ───────────────
class _InsightCard extends StatelessWidget {
  final List<DateTime> months;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final TabSwitcher? onTabSwitch;

  const _InsightCard({
    required this.months,
    required this.selected,
    required this.onSelect,
    this.onTabSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReceiptProvider>();
    if (months.isEmpty) return const SizedBox.shrink();

    final summary = _buildSummary(rp, selected);
    final monthLabel = '${selected.year}년 ${selected.month}월';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 헤더 + 월 선택 화살표
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(children: [
              const Text('💡 월별 인사이트',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              // 이전 월
              _MonthArrowBtn(
                icon: Icons.chevron_left,
                onTap: () {
                  final idx = months.indexWhere((m) => m.year == selected.year && m.month == selected.month);
                  if (idx > 0) onSelect(months[idx - 1]);
                },
                enabled: months.indexWhere((m) => m.year == selected.year && m.month == selected.month) > 0,
              ),
              // 현재 월 표시
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(monthLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              // 다음 월
              _MonthArrowBtn(
                icon: Icons.chevron_right,
                onTap: () {
                  final idx = months.indexWhere((m) => m.year == selected.year && m.month == selected.month);
                  if (idx >= 0 && idx < months.length - 1) onSelect(months[idx + 1]);
                },
                enabled: months.indexWhere((m) => m.year == selected.year && m.month == selected.month) < months.length - 1,
              ),
            ]),
          ),
          // 데이터 없을 때
          if (summary == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('해당 월 데이터가 없어요', style: TextStyle(fontSize: 13, color: AppColors.textHint))),
            )
          else ...[
            // ── 지출 요약 행 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                _SummaryBox(
                  label: '총 지출',
                  value: '₩${NumberFormat('#,###', 'ko').format(summary.total.round())}',
                  sub: summary.momPct == null
                      ? null
                      : '전월 대비 ${summary.momPct! >= 0 ? '+' : ''}${summary.momPct!.toStringAsFixed(1)}%',
                  subColor: summary.momPct == null
                      ? null
                      : summary.momPct! >= 0 ? AppColors.error : AppColors.accent,
                ),
                const SizedBox(width: 10),
                _SummaryBox(
                  label: '구매 건수',
                  value: '${summary.count}건',
                  sub: '${months.length}개월 중 ${ _rank(rp, months, summary.total)}위',
                ),
              ]),
            ),
            // ── 핵심 알림 칩 (상승/절약/집중) ──
            if (summary.chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: summary.chips.map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.color.withValues(alpha: 0.3)),
                    ),
                    child: Text(c.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.color)),
                  )).toList(),
                ),
              ),
            // ── 핵심 문장 ──
            if (summary.headline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(summary.headline,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.6)),
                ),
              ),
            // ── TOP 3 지출 품목 ──
            if (summary.topItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('이달 지출 상위 품목',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  ...summary.topItems.asMap().entries.map((e) {
                    final rank = e.key + 1;
                    final item = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(children: [
                        Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            color: rank == 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3 + 0.2 * (3 - rank)),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Center(child: Text('$rank', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.name, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                        Text('₩${NumberFormat('#,###', 'ko').format(item.amount.round())}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ]),
                    );
                  }),
                ]),
              ),
            // ── 주거래처 ──
            if (summary.topVendor != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  const Text('주거래처', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 8),
                  Text(summary.topVendor!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(width: 6),
                  Text('(${summary.topVendorPct!.toStringAsFixed(0)}%)',
                      style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.7))),
                ]),
              ),
            const SizedBox(height: 14),
          ],
        ]),
      ),
    );
  }

  int _rank(ReceiptProvider rp, List<DateTime> months, double total) {
    final sorted = months.map((m) => rp.getMonthTotal(m.year, m.month)).toList()..sort((a, b) => b.compareTo(a));
    final idx = sorted.indexWhere((v) => v <= total);
    return idx == -1 ? months.length : idx + 1;
  }

  _MonthSummary? _buildSummary(ReceiptProvider rp, DateTime month) {
    final total = rp.getMonthTotal(month.year, month.month);
    if (total == 0) return null;

    final count = rp.getMonthCount(month.year, month.month);

    // 전월 대비
    final prevTotal = rp.getMonthTotal(
        month.month == 1 ? month.year - 1 : month.year,
        month.month == 1 ? 12 : month.month - 1);
    final momPct = prevTotal == 0 ? null : (total - prevTotal) / prevTotal * 100;

    // 이달 영수증
    final receipts = rp.allReceipts
        .where((r) => r.date.year == month.year && r.date.month == month.month)
        .toList();

    // 품목별 지출 합산 TOP3
    final itemAmt = <String, double>{};
    for (final r in receipts) {
      for (final it in r.items) {
        itemAmt[it.name] = (itemAmt[it.name] ?? 0) + it.totalPrice;
      }
    }
    final topItems = (itemAmt.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => _ItemAmt(e.key, e.value))
        .toList();

    // 주거래처
    final vendorAmt = <String, double>{};
    for (final r in receipts) vendorAmt[r.storeName] = (vendorAmt[r.storeName] ?? 0) + r.totalAmount;
    String? topVendor;
    double? topVendorPct;
    if (vendorAmt.isNotEmpty) {
      final top = (vendorAmt.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
      topVendor = top.key;
      topVendorPct = top.value / total * 100;
    }

    // 핵심 알림 칩
    final chips = <_Chip>[];
    final costMap = rp.itemMonthlyCost;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    // 가격 상승 품목 (최대 2개)
    final risingItems = <String>[];
    final cheapItems = <String>[];
    for (final entry in costMap.entries) {
      final monthly = entry.value;
      if (!monthly.containsKey(monthKey) || monthly.length < 2) continue;
      final prices = monthly.values.toList();
      final avg = prices.reduce((a, b) => a + b) / prices.length;
      final current = monthly[monthKey]!;
      final diff = (current - avg) / avg * 100;
      if (diff > 7) risingItems.add(entry.key);
      if (diff < -6) cheapItems.add(entry.key);
    }

    if (risingItems.isNotEmpty) {
      final names = risingItems.take(2).join(', ');
      chips.add(_Chip('⚠ $names 가격상승', AppColors.error));
    }
    if (cheapItems.isNotEmpty) {
      final names = cheapItems.take(2).join(', ');
      chips.add(_Chip('✓ $names 저렴하게 구매', AppColors.accent));
    }
    if (topVendorPct != null && topVendorPct > 45) {
      chips.add(_Chip('– ${topVendor ?? ''} 집중 구매', AppColors.warning));
    }

    // 핵심 문장 (1~2줄 요약)
    final sentences = <String>[];
    if (momPct != null) {
      final dir = momPct >= 0 ? '전월보다 ${momPct.abs().toStringAsFixed(0)}% 늘었어요' : '전월보다 ${momPct.abs().toStringAsFixed(0)}% 줄었어요';
      sentences.add('이번 달 총 지출이 $dir.');
    }
    if (risingItems.isNotEmpty) {
      sentences.add('${risingItems.take(2).join(', ')} 단가가 평균보다 높아요. 대체 품목을 검토해보세요.');
    } else if (cheapItems.isNotEmpty) {
      sentences.add('${cheapItems.take(2).join(', ')}을(를) 평균보다 저렴하게 구매 중이에요. 이번 달 잘 하셨어요!');
    }
    if (topVendorPct != null && topVendorPct > 45) {
      sentences.add('구매의 ${topVendorPct.toStringAsFixed(0)}%가 한 업체에 집중되어 있어요.');
    }

    return _MonthSummary(
      total: total,
      count: count,
      momPct: momPct,
      topItems: topItems,
      topVendor: topVendor,
      topVendorPct: topVendorPct,
      chips: chips,
      headline: sentences.join(' '),
    );
  }
}

class _MonthArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _MonthArrowBtn({required this.icon, required this.onTap, required this.enabled});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: enabled ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: enabled ? AppColors.primary : AppColors.textHint.withValues(alpha: 0.3)),
    ),
  );
}

class _SummaryBox extends StatelessWidget {
  final String label, value;
  final String? sub;
  final Color? subColor;
  const _SummaryBox({required this.label, required this.value, this.sub, this.subColor});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: TextStyle(fontSize: 10, color: subColor ?? AppColors.textSecondary)),
        ],
      ]),
    ),
  );
}

class _MonthSummary {
  final double total;
  final int count;
  final double? momPct;
  final List<_ItemAmt> topItems;
  final String? topVendor;
  final double? topVendorPct;
  final List<_Chip> chips;
  final String headline;
  const _MonthSummary({
    required this.total, required this.count, required this.momPct,
    required this.topItems, required this.topVendor, required this.topVendorPct,
    required this.chips, required this.headline,
  });
}

class _ItemAmt {
  final String name;
  final double amount;
  const _ItemAmt(this.name, this.amount);
}

class _Chip {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
}
