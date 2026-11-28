import 'dart:math' as math;

import '../models/receipt_model.dart';
import 'flower_name_service.dart';
import 'vendor_tax_service.dart';

/// 월 단위 집계 결과
class MonthStat {
  final int year;
  final int month;
  final double total;
  final int count;
  final double exempt; // 면세 매입액
  final double taxable; // 과세 매입액(부가세 포함)
  final double vat; // 부가세 합계

  const MonthStat({
    required this.year,
    required this.month,
    required this.total,
    required this.count,
    required this.exempt,
    required this.taxable,
    required this.vat,
  });

  String get key => '$year-${month.toString().padLeft(2, '0')}';
  String get label => '$month월';
  String get fullLabel => '$year년 $month월';
  double get avgPerReceipt => count == 0 ? 0 : total / count;
  double get exemptRatio => total == 0 ? 0 : exempt / total;
  double get taxableRatio => total == 0 ? 0 : taxable / total;
}

/// 품목 단가 추이 한 점
class PricePoint {
  final String period; // 'YYYY-MM'
  final String label; // 'n월'
  final double avgUnitPrice;
  final int samples;

  const PricePoint({
    required this.period,
    required this.label,
    required this.avgUnitPrice,
    required this.samples,
  });
}

/// 품목 시세 요약
class ItemPriceSummary {
  final String name;
  final List<PricePoint> series;
  final double current;
  final double previous;
  final double min;
  final double max;
  final double average;
  final int totalQty;
  final double totalSpend;

  const ItemPriceSummary({
    required this.name,
    required this.series,
    required this.current,
    required this.previous,
    required this.min,
    required this.max,
    required this.average,
    required this.totalQty,
    required this.totalSpend,
  });

  /// 직전 대비 변동률 (%)
  double get changePercent =>
      previous == 0 ? 0 : ((current - previous) / previous) * 100;

  bool get isUp => changePercent > 0.5;
  bool get isDown => changePercent < -0.5;

  /// 현재가가 평균 대비 저렴한가
  bool get isBargain => average > 0 && current < average * 0.95;
}

/// 매입처별 단가 비교 결과
class VendorItemPrice {
  final String vendor;
  final double avgUnitPrice;
  final int samples;
  final int totalQty;
  final TaxType taxType;

  const VendorItemPrice({
    required this.vendor,
    required this.avgUnitPrice,
    required this.samples,
    required this.totalQty,
    required this.taxType,
  });
}

/// 매입처 요약
class VendorSummary {
  final String name;
  final double total;
  final int count;
  final TaxType taxType;
  final DateTime? lastPurchase;

  const VendorSummary({
    required this.name,
    required this.total,
    required this.count,
    required this.taxType,
    this.lastPurchase,
  });

  double get avg => count == 0 ? 0 : total / count;
}

/// 영수증 데이터 → 인사이트 계산 (순수 함수 모음)
class InsightService {
  InsightService._();

  static final _tax = VendorTaxService.instance;

  // ── 월별 집계 ──────────────────────────────────────────

  static List<MonthStat> monthlyStats(List<ReceiptModel> receipts) {
    final buckets = <String, List<ReceiptModel>>{};
    for (final r in receipts) {
      final k = '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      buckets.putIfAbsent(k, () => []).add(r);
    }
    final keys = buckets.keys.toList()..sort();
    return keys.map((k) {
      final parts = k.split('-');
      final list = buckets[k]!;
      double total = 0, exempt = 0, taxable = 0, vat = 0;
      for (final r in list) {
        total += r.totalAmount;
        final s = _tax.split(r.storeName, r.totalAmount);
        if (s.exempt) {
          exempt += r.totalAmount;
        } else {
          taxable += r.totalAmount;
          vat += s.vat;
        }
      }
      return MonthStat(
        year: int.parse(parts[0]),
        month: int.parse(parts[1]),
        total: total,
        count: list.length,
        exempt: exempt,
        taxable: taxable,
        vat: vat,
      );
    }).toList();
  }

  /// 최근 n개월 집계 (데이터 없는 달은 제외)
  static List<MonthStat> recentMonths(List<ReceiptModel> receipts, int n) {
    final all = monthlyStats(receipts);
    if (all.length <= n) return all;
    return all.sublist(all.length - n);
  }

  static MonthStat? statFor(List<ReceiptModel> receipts, int year, int month) {
    final all = monthlyStats(receipts);
    final key = '$year-${month.toString().padLeft(2, '0')}';
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  // ── 면세 / 과세 ────────────────────────────────────────

  static TaxSplit totalSplit(List<ReceiptModel> receipts) {
    var acc = TaxSplit.zero;
    for (final r in receipts) {
      acc = acc + _tax.split(r.storeName, r.totalAmount);
    }
    return acc;
  }

  /// 면세/과세 금액 (기간 필터 적용된 리스트를 넘길 것)
  static ({double exempt, double taxable, double vat}) taxBreakdown(
      List<ReceiptModel> receipts) {
    double exempt = 0, taxable = 0, vat = 0;
    for (final r in receipts) {
      final s = _tax.split(r.storeName, r.totalAmount);
      if (s.exempt) {
        exempt += r.totalAmount;
      } else {
        taxable += r.totalAmount;
        vat += s.vat;
      }
    }
    return (exempt: exempt, taxable: taxable, vat: vat);
  }

  // ── 품목 시세 ──────────────────────────────────────────

  /// 저장된 이름 → **집계용 상위 품목 키**.
  ///
  /// 저장값은 사장님이 적은 그대로 유지된다(`장미 쥬밀리아`). 통계에서만
  /// 상위 품목(`장미`)으로 묶어서 표본을 모은다. 우리가 모르는 이름은
  /// 원문이 그대로 키가 되므로 엉뚱한 품목에 합쳐지지 않는다.
  static String _key(String stored) =>
      FlowerNameService.instance.canonicalItem(stored);

  /// 저장 이름 [stored] 가 집계 키 [itemName] 에 속하는가.
  ///
  /// `itemName` 자체가 품종까지 포함한 이름(`장미 쥬밀리아`)일 수도 있어서
  /// 완전일치를 먼저 본다. 그 다음 상위 품목 키로 비교한다.
  static bool _sameItem(String stored, String itemName) {
    if (stored == itemName) return true;
    return _key(stored) == _key(itemName);
  }


  /// 품목별 월평균 단가 시계열
  ///
  /// [itemName] 은 **집계 키**다. `장미` 를 넘기면 `장미 쥬밀리아`,
  /// `장미 하젤` 처럼 품종까지 적힌 항목도 같이 잡힌다.
  /// (저장값은 손대지 않고 [_key] 로 상위 품목만 계산해서 비교한다 —
  ///  Build 19 처럼 저장 시점에 이름을 뭉개면 정보가 영구히 사라진다)
  static ItemPriceSummary? itemSummary(
      List<ReceiptModel> receipts, String itemName) {
    final byPeriod = <String, List<double>>{};
    int totalQty = 0;
    double totalSpend = 0;

    for (final r in receipts) {
      for (final it in r.items) {
        if (!_sameItem(it.name, itemName)) continue;
        final k = '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
        byPeriod.putIfAbsent(k, () => []).add(it.unitPrice);
        totalQty += it.quantity;
        totalSpend += it.totalPrice;
      }
    }
    if (byPeriod.isEmpty) return null;

    final keys = byPeriod.keys.toList()..sort();
    final series = keys.map((k) {
      final ps = byPeriod[k]!;
      final avg = ps.reduce((a, b) => a + b) / ps.length;
      return PricePoint(
        period: k,
        label: '${int.parse(k.split('-')[1])}월',
        avgUnitPrice: avg,
        samples: ps.length,
      );
    }).toList();

    final values = series.map((e) => e.avgUnitPrice).toList();
    return ItemPriceSummary(
      name: itemName,
      series: series,
      current: values.last,
      previous: values.length >= 2 ? values[values.length - 2] : values.last,
      min: values.reduce(math.min),
      max: values.reduce(math.max),
      average: values.reduce((a, b) => a + b) / values.length,
      totalQty: totalQty,
      totalSpend: totalSpend,
    );
  }

  /// 구매 빈도 상위 품목명
  static List<String> topItemNames(List<ReceiptModel> receipts, int n) {
    final count = <String, int>{};
    for (final r in receipts) {
      for (final it in r.items) {
        // 품종까지 적힌 이름(`장미 쥬밀리아`)은 상위 품목(`장미`)으로 묶는다.
        // 안 묶으면 장미 188품종이 각각 다른 품목으로 쌓여서 시세 추이가
        // 표본 1개짜리 조각들로 흩어진다.
        final k = _key(it.name);
        count[k] = (count[k] ?? 0) + it.quantity;
      }
    }
    final sorted = count.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).map((e) => e.key).toList();
  }

  /// 전 품목 시세 요약 (구매 빈도순)
  static List<ItemPriceSummary> allItemSummaries(List<ReceiptModel> receipts,
      {int limit = 20}) {
    final names = topItemNames(receipts, limit);
    final out = <ItemPriceSummary>[];
    for (final n in names) {
      final s = itemSummary(receipts, n);
      if (s != null) out.add(s);
    }
    return out;
  }

  // ── 매입처 ─────────────────────────────────────────────

  static List<VendorSummary> vendorSummaries(List<ReceiptModel> receipts) {
    final map = <String, List<ReceiptModel>>{};
    for (final r in receipts) {
      map.putIfAbsent(r.storeName, () => []).add(r);
    }
    final out = map.entries.map((e) {
      final total = e.value.fold<double>(0, (s, r) => s + r.totalAmount);
      DateTime? last;
      for (final r in e.value) {
        if (last == null || r.date.isAfter(last)) last = r.date;
      }
      return VendorSummary(
        name: e.key,
        total: total,
        count: e.value.length,
        taxType: _tax.typeOf(e.key),
        lastPurchase: last,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// 특정 품목의 매입처별 평균 단가 (저렴한 순)
  static List<VendorItemPrice> comparePrices(
      List<ReceiptModel> receipts, String itemName) {
    final byVendor = <String, List<double>>{};
    final qty = <String, int>{};
    for (final r in receipts) {
      for (final it in r.items) {
        if (!_sameItem(it.name, itemName)) continue;
        byVendor.putIfAbsent(r.storeName, () => []).add(it.unitPrice);
        qty[r.storeName] = (qty[r.storeName] ?? 0) + it.quantity;
      }
    }
    final out = byVendor.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return VendorItemPrice(
        vendor: e.key,
        avgUnitPrice: avg,
        samples: e.value.length,
        totalQty: qty[e.key] ?? 0,
        taxType: _tax.typeOf(e.key),
      );
    }).toList()
      ..sort((a, b) => a.avgUnitPrice.compareTo(b.avgUnitPrice));
    return out;
  }

  /// 최저가 매입처로 바꿨을 때의 절감 예상액
  static double potentialSaving(
      List<ReceiptModel> receipts, String itemName) {
    final list = comparePrices(receipts, itemName);
    if (list.length < 2) return 0;
    final cheapest = list.first.avgUnitPrice;
    double saving = 0;
    for (final v in list.skip(1)) {
      saving += (v.avgUnitPrice - cheapest) * v.totalQty;
    }
    return saving;
  }

  // ── 시즌 비교 ──────────────────────────────────────────

  /// 같은 달의 연도별 비교 (예: 작년 3월 vs 올해 3월)
  static List<MonthStat> sameMonthAcrossYears(
      List<ReceiptModel> receipts, int month) {
    return monthlyStats(receipts).where((s) => s.month == month).toList();
  }

  // ── 예산 ───────────────────────────────────────────────

  /// 최근 n개월 평균 매입액 (예산 추천 기준)
  static double averageMonthlySpend(List<ReceiptModel> receipts,
      {int months = 3}) {
    final recent = recentMonths(receipts, months);
    if (recent.isEmpty) return 0;
    return recent.fold<double>(0, (s, m) => s + m.total) / recent.length;
  }

  /// 이번 달 페이스로 갈 때 월말 예상 매입액
  static double projectedMonthEnd(List<ReceiptModel> receipts,
      {DateTime? now}) {
    final n = now ?? DateTime.now();
    final daysInMonth = DateTime(n.year, n.month + 1, 0).day;
    final spent = receipts
        .where((r) => r.date.year == n.year && r.date.month == n.month)
        .fold<double>(0, (s, r) => s + r.totalAmount);
    if (n.day == 0) return spent;
    return spent / n.day * daysInMonth;
  }

  // ── 스마트 사입 가이드 ─────────────────────────────────

  /// 지금 사기 좋은 품목 / 비싼 품목 추천
  static ({List<ItemPriceSummary> buy, List<ItemPriceSummary> wait})
      purchaseGuide(List<ReceiptModel> receipts) {
    final all = allItemSummaries(receipts, limit: 24)
        .where((s) => s.series.length >= 2)
        .toList();
    final buy = all.where((s) => s.isDown || s.isBargain).toList()
      ..sort((a, b) => a.changePercent.compareTo(b.changePercent));
    final wait = all.where((s) => s.isUp && !s.isBargain).toList()
      ..sort((a, b) => b.changePercent.compareTo(a.changePercent));
    return (buy: buy.take(6).toList(), wait: wait.take(6).toList());
  }
}
