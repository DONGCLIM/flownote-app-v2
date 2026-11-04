import 'package:flutter/foundation.dart';

import '../models/receipt_model.dart';

/// 원가 계산기의 **셈만** 맡는다. 화면을 모른다.
///
/// 🔴 화면과 떼어 놓은 이유: 숫자가 맞는지 확인하려고 화면을 띄울 필요가
///    없다. 여기만 테스트하면 된다. 화면은 결과를 받아 그리기만 한다.
///
/// ## 계산 차례 (사장님 확정, #178)
///
/// ```
///   꽃 합계   = Σ(수량 × 단가)        ← 꽃 카드만
///   부자재    = Σ(수량 × 단가)        ← 부자재 카드만
///   로스      = 꽃 합계 × 로스율       ← 🔴 꽃에만 매긴다
///   총 원가   = 꽃 + 부자재 + 로스 + 작업비
///   판매가    = 총 원가 × 배수 → 1,000원 단위 **올림**
///   마진율    = (판매가 − 총 원가) ÷ 판매가
///   대당 이익 = 판매가 − 총 원가
/// ```
///
/// 🔴 판매가는 **올림**이다. 반올림이 아니다. 내려서 팔면 마진이 깎인다.
@immutable
class CostLine {
  const CostLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.unit = '',
    this.fromReceipt = false,
  });

  final String name;

  /// 수량. 비워 두면 0 으로 센다.
  final double qty;

  /// 한 단위 값.
  final double unitPrice;

  /// 영수증에 적힌 단위 그대로 (`단`, `속`, `개` …).
  final String unit;

  /// 영수증에서 단가를 끌어온 줄인가. 안내 문구를 가르는 데 쓴다.
  final bool fromReceipt;

  double get amount => qty * unitPrice;

  CostLine copyWith({
    String? name,
    double? qty,
    double? unitPrice,
    String? unit,
    bool? fromReceipt,
  }) =>
      CostLine(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        unit: unit ?? this.unit,
        fromReceipt: fromReceipt ?? this.fromReceipt,
      );
}

/// 셈 결과. 화면은 이걸 그대로 그린다.
@immutable
class CostResult {
  const CostResult({
    required this.flower,
    required this.supplies,
    required this.loss,
    required this.labor,
    required this.totalCost,
    required this.price,
    required this.marginRate,
    required this.marginAmount,
  });

  final double flower;
  final double supplies;
  final double loss;
  final double labor;
  final double totalCost;
  final double price;

  /// 0~1 사이. 화면에서 100 을 곱해 보여준다.
  final double marginRate;
  final double marginAmount;
}

class CostCalc {
  CostCalc._();

  /// 고를 수 있는 판매 배수. (사장님 확정 #178)
  static const List<double> multipliers = [2, 2.5, 3, 3.5, 4];

  static String multiplierLabel(double m) =>
      m == m.roundToDouble() ? '×${m.toInt()}' : '×$m';

  /// 판매가를 1,000원 단위로 **올린다**.
  static double roundUpPrice(double raw) {
    if (raw <= 0) return 0;
    return (raw / 1000).ceil() * 1000;
  }

  /// 본 계산.
  ///
  /// [lossRate] 는 백분율 그대로 받는다(8 = 8%). 화면 입력칸이 `8%` 라서
  /// 0.08 로 바꿔 넘기게 하면 누가 한 번은 빼먹는다.
  static CostResult run({
    required List<CostLine> flowers,
    required List<CostLine> supplies,
    required double lossRate,
    required double labor,
    required double multiplier,
  }) {
    double sum(List<CostLine> l) =>
        l.fold<double>(0, (acc, e) => acc + e.amount);

    final flower = sum(flowers);
    final sup = sum(supplies);
    // 🔴 로스는 꽃에만. 포장지가 시들지는 않는다.
    final loss = flower * (lossRate / 100);
    final total = flower + sup + loss + labor;
    final price = roundUpPrice(total * multiplier);

    // 원가가 0 이면 마진을 말할 수 없다. 0 으로 둔다(0 나누기 막기).
    final profit = price - total;
    final rate = price <= 0 ? 0.0 : profit / price;

    return CostResult(
      flower: flower,
      supplies: sup,
      loss: loss,
      labor: labor,
      totalCost: total,
      price: price,
      marginRate: rate,
      marginAmount: profit,
    );
  }

  /// 세 자리 쉼표 + `원`.
  static String won(double v) => '${comma(v)}원';

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

  /// 소수점 없는 퍼센트. 0.6 → `60%`
  static String pct(double rate) => '${(rate * 100).round()}%';
}

/// 영수증에서 뽑아낸 **품목별 최근 단가**.
///
/// 🔴 `FlowerItem` 에는 날짜가 없다. 날짜는 바깥 `ReceiptModel.date` 에
///    있다. 그래서 영수증을 날짜 내림차순으로 훑으면서 **처음 만난 것**을
///    가장 최근 값으로 삼는다. 품목 안을 아무리 들여다봐도 날짜는 안 나온다.
@immutable
class PriceBookEntry {
  const PriceBookEntry({
    required this.name,
    required this.unitPrice,
    required this.unit,
    required this.date,
  });

  final String name;
  final double unitPrice;
  final String unit;
  final DateTime date;

  /// `8,000원 · 1단 기준`
  String get label =>
      '${CostCalc.won(unitPrice)}${unit.isEmpty ? '' : ' · 1$unit 기준'}';
}

class PriceBook {
  const PriceBook(this.entries);

  /// 품목 이름 → 최근 단가. 이름은 공백을 턴 원문 그대로 쓴다.
  final Map<String, PriceBookEntry> entries;

  static const PriceBook empty = PriceBook(<String, PriceBookEntry>{});

  bool get isEmpty => entries.isEmpty;

  /// 영수증 목록에서 만든다. 순서를 믿지 않고 날짜로 직접 고른다.
  factory PriceBook.fromReceipts(List<ReceiptModel> receipts) {
    final map = <String, PriceBookEntry>{};
    for (final r in receipts) {
      for (final it in r.items) {
        final name = it.name.trim();
        if (name.isEmpty) continue;
        if (it.unitPrice <= 0) continue;
        final old = map[name];
        // 더 최근 것만 남긴다.
        if (old != null && !r.date.isAfter(old.date)) continue;
        map[name] = PriceBookEntry(
          name: name,
          unitPrice: it.unitPrice,
          unit: it.unit.trim(),
          date: r.date,
        );
      }
    }
    return PriceBook(map);
  }

  PriceBookEntry? lookup(String name) => entries[name.trim()];

  /// 자동완성 후보. 적은 글자가 들어간 이름을 최근 순으로.
  List<PriceBookEntry> suggest(String typed, {int limit = 6}) {
    final q = typed.trim();
    if (q.isEmpty) return const [];
    final hit = entries.values
        .where((e) => e.name.contains(q))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return hit.length <= limit ? hit : hit.sublist(0, limit);
  }
}
