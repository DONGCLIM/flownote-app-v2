import 'package:flutter/foundation.dart';

import '../models/receipt_model.dart';

/// 월별 인사이트의 **셈만** 맡는다. 화면을 모른다. (#180)
///
/// 🔴 계산을 여기 한 곳에 모은 이유: 같은 비율을 화면에서 또 구하면
///    배지의 `+12.0%` 와 설명 문장의 `12.0%` 가 어긋난다. 한 번 구해
///    여러 곳이 같이 쓴다.
///
/// ## 기준 (사장님 확정 #180)
///
/// ```
///   기준 달   = 지난달 (이미 마감된 달)
///   비교 기간 = 기준 달 직전 3개월
///   비교 평균 = 비교 기간 3개월 합계 ÷ 3
///   🔴 비교 3개월 중 영수증이 **한 장도 없는 달**이 있으면 리포트를 만들지
///      않는다. 두 달치를 3 으로 나누면 평균이 낮게 나와서, 멀쩡히 산 달을
///      "많이 썼다" 고 잘못 말하게 된다.
/// ```
///
/// ## 표시할 때만 다듬는다
///
/// 계산은 **원래 값**으로 하고, 보여줄 때만 [InsightFmt] 로 다듬는다.
/// 반올림한 값으로 또 계산하면 숫자가 조금씩 어긋난다.
enum InsightKind {
  /// 품목 단가가 올랐다.
  unitPrice,

  /// 그 달 매입이 많았다.
  spending,
}

@immutable
class InsightCard {
  const InsightCard({
    required this.kind,
    required this.title,
    required this.ratio,
    required this.body,
    this.fromTo,
    this.saving = 0,
  });

  final InsightKind kind;
  final String title;

  /// 오른 비율. 0.12 = 12%. **원래 값**이다.
  final double ratio;

  final String body;

  /// `7,140원 → 8,000원`. 지출 카드에는 없다.
  final String? fromTo;

  /// 절감 여지. **원래 값**이다. 지출 카드는 0.
  final double saving;

  String get badge => kind == InsightKind.unitPrice ? '단가' : '지출';

  /// `+12.0%`
  String get deltaText => '+${InsightFmt.pct(ratio)}';
}

@immutable
class MonthlyInsightReport {
  const MonthlyInsightReport({
    required this.month,
    required this.receiptCount,
    required this.monthTotal,
    required this.cards,
  });

  /// 기준 달(지난달)의 1일.
  final DateTime month;

  /// 기준 달 영수증 매수.
  final int receiptCount;

  /// 기준 달 매입액.
  final double monthTotal;

  final List<InsightCard> cards;

  /// 절감 여지 합계. 원래 값.
  double get totalSaving =>
      cards.fold<double>(0, (acc, e) => acc + e.saving);

  int countOf(InsightKind k) => cards.where((e) => e.kind == k).length;

  bool get isEmpty => cards.isEmpty;
}

/// 숫자를 글자로 바꾼다. **여기서만** 반올림·내림을 한다.
class InsightFmt {
  InsightFmt._();

  /// 소수 첫째 자리까지. `0.120448` → `12.0%`
  static String pct(double ratio) {
    final v = (ratio * 1000).round() / 10;   // 백분율의 소수 첫째 자리
    return '${v.toStringAsFixed(1)}%';
  }

  /// 1,000원 단위 **내림**. 절감 여지와 합계에 쓴다.
  ///
  /// 🔴 올림이 아니라 내림이다. 아낄 수 있는 돈을 실제보다 크게 말하면
  ///    사장님이 기대한 만큼 안 아껴진다.
  static double floorThousand(double v) {
    if (v <= 0) return 0;
    return (v / 1000).floor() * 1000;
  }

  /// 세 자리 쉼표.
  static String comma(double v) {
    final n = v.round();
    final neg = n < 0;
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return neg ? '-$b' : b.toString();
  }

  /// 단가·매입액 — 원 단위 그대로.
  static String won(double v) => '${comma(v)}원';

  /// 절감 여지·합계 — 1,000원 단위 내림.
  static String wonFloor(double v) => won(floorThousand(v));
}

/// 품목 한 가지를 모아 센 값.
class _Agg {
  double amount = 0;
  double qty = 0;

  /// 산 **횟수**(영수증 수). 같은 영수증에 두 줄이어도 한 번이다.
  int times = 0;

  /// 가중 평균 단가 = 총 금액 ÷ 총 수량.
  double get avg => qty <= 0 ? 0 : amount / qty;
}

class MonthlyInsight {
  MonthlyInsight._();

  /// 단가가 이만큼 올라야 카드로 만든다.
  static const double riseThreshold = 0.10;

  /// 매입이 이만큼 많아야 지출 카드를 만든다.
  static const double spendThreshold = 0.15;

  /// 단가 카드 최대 개수.
  static const int maxPriceCards = 3;

  /// 비교 기간에 이 횟수 이상 산 품목만 본다.
  static const int minTimes = 2;

  /// 기준 달 = 지난달.
  static DateTime baseMonth({DateTime? now}) {
    final n = now ?? DateTime.now();
    // DateTime(2026, 0) 은 Dart 가 2025년 12월로 알아서 바꿔 준다.
    return DateTime(n.year, n.month - 1);
  }

  static bool _inMonth(DateTime d, DateTime m) =>
      d.year == m.year && d.month == m.month;

  /// 단위가 다르면 다른 품목으로 본다.
  ///
  /// 🔴 `장미 1단(8,000원)` 과 `장미 1송이(800원)` 를 섞으면 평균이
  ///    엉뚱해져서, 단을 산 달이 늘 "급등" 으로 잡힌다.
  static String _key(FlowerItem it) =>
      '${it.name.trim()}|${it.unit.trim()}';

  /// 오인식으로 보이는 단가인가. 비교 평균의 3배 이상이거나 1/3 이하.
  static bool _outlier(double price, double base) {
    if (base <= 0) return false;
    return price >= base * 3 || price <= base / 3;
  }

  /// 영수증을 모아 센다. [skip] 이 참이면 그 줄을 뺀다.
  static Map<String, _Agg> _collect(
    List<ReceiptModel> rs, {
    bool Function(String key, FlowerItem it)? skip,
  }) {
    final out = <String, _Agg>{};
    for (final r in rs) {
      // 같은 영수증 안에서 같은 품목이 두 줄이어도 **한 번 산 것**이다.
      final seen = <String>{};
      for (final it in r.items) {
        if (it.name.trim().isEmpty) continue;
        if (it.quantity <= 0 || it.unitPrice <= 0) continue;
        final k = _key(it);
        if (skip != null && skip(k, it)) continue;
        final a = out.putIfAbsent(k, _Agg.new);
        a.amount += it.unitPrice * it.quantity;
        a.qty += it.quantity;
        if (seen.add(k)) a.times++;
      }
    }
    return out;
  }

  /// 리포트를 만든다. 만들 수 없으면 null.
  ///
  /// [receipts] 는 사장님이 확인해 **저장한** 영수증이다. 저장 전 임시
  /// 인식 결과는 애초에 여기까지 오지 않는다.
  static MonthlyInsightReport? build(
    List<ReceiptModel> receipts, {
    DateTime? now,
  }) {
    final base = baseMonth(now: now);
    final cmpMonths = [
      for (var i = 1; i <= 3; i++) DateTime(base.year, base.month - i),
    ];

    final baseRs =
        receipts.where((r) => _inMonth(r.date, base)).toList();
    if (baseRs.isEmpty) return null;

    // 🔴 비교 3개월 중 빈 달이 있으면 만들지 않는다.
    for (final m in cmpMonths) {
      if (!receipts.any((r) => _inMonth(r.date, m))) return null;
    }
    final cmpRs = receipts
        .where((r) => cmpMonths.any((m) => _inMonth(r.date, m)))
        .toList();

    // ── 1) 비교 평균을 먼저 거칠게 구한다 ────────────────────────
    final rough = _collect(cmpRs);
    final roughAvg = {
      for (final e in rough.entries) e.key: e.value.avg,
    };

    // ── 2) 그 평균으로 오인식을 걸러 다시 센다 ───────────────────
    bool skip(String k, FlowerItem it) =>
        _outlier(it.unitPrice, roughAvg[k] ?? 0);

    final cmpAgg = _collect(cmpRs, skip: skip);
    final baseAgg = _collect(baseRs, skip: skip);

    final cards = <InsightCard>[];

    // ── 단가 카드 ────────────────────────────────────────────────
    final rises = <InsightCard>[];
    for (final e in baseAgg.entries) {
      final cmp = cmpAgg[e.key];
      if (cmp == null || cmp.times < minTimes) continue;

      final cmpPrice = cmp.avg;
      final nowPrice = e.value.avg;
      if (cmpPrice <= 0 || nowPrice <= cmpPrice) continue;

      final ratio = (nowPrice - cmpPrice) / cmpPrice;
      if (ratio < riseThreshold) continue;

      final qty = e.value.qty;
      final saving = (nowPrice - cmpPrice) * qty;
      final name = e.key.split('|').first;
      final unit = e.key.split('|').last;
      final qtyText = '${InsightFmt.comma(qty)}${unit.isEmpty ? '' : unit}';

      rises.add(InsightCard(
        kind: InsightKind.unitPrice,
        title: '$name 단가 급등',
        ratio: ratio,
        fromTo: '${InsightFmt.won(cmpPrice)} → ${InsightFmt.won(nowPrice)}',
        saving: saving,
        // 🔴 설명에도 **같은 비율**을 쓴다. 따로 구하면 배지와 어긋난다.
        body: '직전 3개월 평균보다 ${InsightFmt.pct(ratio)} 높은 가격으로 '
            '$qtyText을 매입했어요. 시즌 영향일 수 있어요.',
      ));
    }
    // 아낄 수 있는 돈이 큰 것부터.
    rises.sort((a, b) => b.saving.compareTo(a.saving));
    cards.addAll(rises.take(maxPriceCards));

    // ── 지출 카드 ────────────────────────────────────────────────
    final monthTotal =
        baseRs.fold<double>(0, (acc, r) => acc + r.totalAmount);
    final cmpTotal =
        cmpRs.fold<double>(0, (acc, r) => acc + r.totalAmount);
    final cmpAvgTotal = cmpTotal / 3;

    if (cmpAvgTotal > 0) {
      final ratio = (monthTotal - cmpAvgTotal) / cmpAvgTotal;
      if (ratio >= spendThreshold) {
        cards.add(InsightCard(
          kind: InsightKind.spending,
          title: '이번 달 지출 증가',
          ratio: ratio,
          fromTo: '${InsightFmt.won(cmpAvgTotal)} → '
              '${InsightFmt.won(monthTotal)}',
          // 지출 카드에는 절감 여지를 매기지 않는다. (사장님 지시)
          saving: 0,
          body: '직전 3개월 평균보다 ${InsightFmt.pct(ratio)} 많이 '
              '매입했어요. 시즌 영향일 수 있어요.',
        ));
      }
    }

    return MonthlyInsightReport(
      month: base,
      receiptCount: baseRs.length,
      monthTotal: monthTotal,
      cards: cards,
    );
  }
}
