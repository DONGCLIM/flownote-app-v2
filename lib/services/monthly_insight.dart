import 'package:flutter/foundation.dart';

import '../models/receipt_model.dart';

/// 월별 인사이트의 **셈만** 맡는다. 화면을 모른다. (#180 · #181)
///
/// 🔴 계산을 여기 한 곳에 모은 이유: 같은 비율을 화면에서 또 구하면
///    배지의 `+12.0%` 와 설명 문장의 `12.0%` 가 어긋난다. 한 번 구해
///    여러 곳이 같이 쓴다.
///
/// ## 기준 달 (사장님 확정 #181)
///
/// ```
///   지난달에 영수증이 있으면            → 지난달 (마감된 달)
///   지난달이 비어 있으면                → 이번 달 (아직 진행 중)
///   지난달도 이번 달도 비어 있으면      → 리포트 없음(null)
/// ```
///
/// ## 비교 기간
///
/// ```
///   기준 달 이전 **최대 3개월 중 영수증이 있는 달**만 쓴다.
///   비교 평균 = 그 달들의 합계 ÷ 영수증이 있는 달 수
///   🔴 예전에는 "3개월 중 빈 달이 있으면 리포트를 안 만든다" 였다.
///      영수증을 막 모으기 시작한 사장님께 아무것도 못 보여 드려서
///      규칙을 바꿨다(#181). 빈 달은 나눗셈에서 아예 뺀다.
///   기준 달이 **진행 중인 이번 달**이면 비교하지 않는다. 달이 끝나지
///      않았는데 지난달과 견주면 늘 "덜 썼다" 가 되어 거짓말이 된다.
/// ```
///
/// ## 비교할 게 없으면 — 첫 달 리포트
///
/// 품목 비중과 많이 산 품목만 보여 준다. 오른 것이 없으니 절감 여지도 없다.
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

  /// 품목군 비중. (첫 달 리포트)
  mix,

  /// 많이 산 품목 TOP3. (첫 달 리포트)
  top,
}

/// 품목군 네 가지. 영수증에는 이 분류가 없어서 **품목 이름으로 짐작**한다.
///
/// 🔴 짐작이라 틀릴 수 있다. 사장님께 확인받을 일로 `docs/TODO_기능연결.md`
///    에 적어 두었다.
enum ItemGroup {
  cutFlower,
  supply,
  plant,
  etc;

  String get label => switch (this) {
        ItemGroup.cutFlower => '절화',
        ItemGroup.supply => '부자재',
        ItemGroup.plant => '화분·식물',
        ItemGroup.etc => '기타',
      };
}

@immutable
class InsightCard {
  const InsightCard({
    required this.kind,
    required this.title,
    required this.body,
    this.ratio = 0,
    this.headline,
    this.fromTo,
    this.saving = 0,
    this.lines = const [],
  });

  final InsightKind kind;
  final String title;

  /// 오른 비율. 0.12 = 12%. **원래 값**이다. 비중·품목 카드에는 없다.
  final double ratio;

  final String body;

  /// 왼쪽 큰 글자를 직접 정할 때. 비워 두면 `+12.0%`.
  final String? headline;

  /// 오른쪽 작은 글자. `7,140원 → 8,000원` · `지난 3개월 평균 252만원`.
  final String? fromTo;

  /// 절감 여지. **원래 값**이다. 없으면 0.
  final double saving;

  /// 여러 줄로 보여 줄 때. (많이 산 품목)
  final List<String> lines;

  String get badge => switch (kind) {
        InsightKind.unitPrice => '단가',
        InsightKind.spending => '지출',
        InsightKind.mix => '비중',
        InsightKind.top => '품목',
      };

  /// `+12.0%`
  String get deltaText => '+${InsightFmt.pct(ratio)}';

  /// 왼쪽 큰 글자.
  String get big => headline ?? deltaText;

  /// 오른 것을 알리는 카드인가. (글자를 붉게 쓴다)
  bool get isRise =>
      kind == InsightKind.unitPrice || kind == InsightKind.spending;
}

@immutable
class MonthlyInsightReport {
  const MonthlyInsightReport({
    required this.month,
    required this.receiptCount,
    required this.monthTotal,
    required this.cards,
    this.compareMonths = 0,
    this.inProgress = false,
    this.asOf,
  });

  /// 기준 달의 1일.
  final DateTime month;

  /// 기준 달 영수증 매수.
  final int receiptCount;

  /// 기준 달 매입액.
  final double monthTotal;

  final List<InsightCard> cards;

  /// 비교에 쓴 달 수. 0 이면 비교하지 않았다(첫 달 리포트).
  final int compareMonths;

  /// 기준 달이 아직 진행 중인 이번 달인가.
  final bool inProgress;

  /// 진행 중일 때의 '오늘'. `11월 1~24일 기준` 에 쓴다.
  final DateTime? asOf;

  /// 비교할 이전 달이 없다. 첫 달 리포트로 보여 준다.
  bool get isFirstMonth => compareMonths == 0;

  /// 코랄 카드 제목.
  String get headTitle => isFirstMonth
      ? '${month.month}월 리포트'
      : '${month.year}년 ${month.month}월 점검 결과';

  /// `11월 1~24일 기준`. 진행 중인 달일 때만.
  String? get periodNote {
    final d = asOf;
    if (!inProgress || d == null) return null;
    return '${month.month}월 1~${d.day}일 기준';
  }

  /// `지난달` · `지난 3개월 평균`
  String get compareLabel =>
      compareMonths == 1 ? '지난달' : '지난 $compareMonths개월 평균';

  /// 머리글 설명.
  String get compareNote => compareMonths == 1
      ? '지난달과 비교했어요'
      : '지난 $compareMonths개월 평균과 비교했어요';

  /// 첫 달 리포트의 아래쪽 안내.
  static const String firstMonthNote = '다음 달 영수증이 쌓이면 지난달과 비교해 드려요';

  /// 영수증이 하나도 없을 때의 안내.
  static const String noReceiptNote = '영수증을 찍으면 이번 달 리포트를 만들어 드려요';

  /// 절감 여지 합계. 원래 값.
  double get totalSaving => cards.fold<double>(0, (acc, e) => acc + e.saving);

  int countOf(InsightKind k) => cards.where((e) => e.kind == k).length;

  bool get isEmpty => cards.isEmpty;
}

/// 숫자를 글자로 바꾼다. **여기서만** 반올림·내림을 한다.
class InsightFmt {
  InsightFmt._();

  /// 소수 첫째 자리까지. `0.120448` → `12.0%`
  static String pct(double ratio) {
    final v = (ratio * 1000).round() / 10; // 백분율의 소수 첫째 자리
    return '${v.toStringAsFixed(1)}%';
  }

  /// 부호를 붙인다. `+17.0%` · `-3.0%` (#184 품목별 지출 분석)
  static String signedPct(double ratio) =>
      '${ratio >= 0 ? '+' : ''}${pct(ratio)}';

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

  /// `2,520,000` → `252만원`. 만원이 안 되면 원 단위로 적는다.
  static String manwon(double v) {
    if (v.abs() < 10000) return won(v);
    return '${comma(v / 10000)}만원';
  }
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

  /// 많이 산 품목은 몇 개까지.
  static const int topItems = 3;

  /// 비교 기간을 최대 몇 달까지 보나.
  static const int compareWindow = 3;

  /// 기준 달 — 지난달에 영수증이 있으면 지난달, 없으면 이번 달.
  ///
  /// 둘 다 비어 있으면 null. 그때는 리포트를 만들지 않는다.
  ///
  /// 🔴 지난달을 먼저 보는 이유: 이번 달은 아직 끝나지 않아서, 다 사지도
  ///    않은 달을 지난달과 견주면 늘 "덜 썼다" 가 된다.
  static DateTime? baseMonth(
    List<ReceiptModel> receipts, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final cur = DateTime(n.year, n.month);
    // DateTime(2026, 0) 은 Dart 가 2025년 12월로 알아서 바꿔 준다.
    final prev = DateTime(n.year, n.month - 1);
    if (receipts.any((r) => _inMonth(r.date, prev))) return prev;
    if (receipts.any((r) => _inMonth(r.date, cur))) return cur;
    return null;
  }

  static bool _inMonth(DateTime d, DateTime m) =>
      d.year == m.year && d.month == m.month;

  /// 단위가 다르면 다른 품목으로 본다.
  ///
  /// 🔴 `장미 1단(8,000원)` 과 `장미 1송이(800원)` 를 섞으면 평균이
  ///    엉뚱해져서, 단을 산 달이 늘 "급등" 으로 잡힌다.
  static String _key(FlowerItem it) => '${it.name.trim()}|${it.unit.trim()}';

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

  /// 품목 이름으로 품목군을 짐작한다.
  ///
  /// 🔴 영수증에는 품목군이 없다. 이름만 보고 나눈 값이라 틀릴 수 있다.
  ///    사장님께 확인받을 일로 `docs/TODO_기능연결.md` 에 적어 두었다.
  static ItemGroup groupOf(String rawName) {
    final n = rawName.replaceAll(' ', '');
    const supply = [
      '포장', '지함', '리본', '랩', '부직포', '망사', '끈', '테이프', '철사',
      '와이어', '핀', '오아시스', '플로랄폼', '플로럴폼', '폼', '바구니',
      '박스', '상자', '비닐', '봉투', '카드', '픽', '자재', '왁스', '셀로판',
    ];
    const plant = [
      '화분', '분재', '다육', '선인장', '관엽', '식물', '묘목', '포트',
      '난', '산세', '스투키', '테이블야자', '고무나무', '나무',
    ];
    const etc = ['배송', '운임', '택배', '수수료', '퀵', '기타', '할인'];
    for (final k in etc) {
      if (n.contains(k)) return ItemGroup.etc;
    }
    for (final k in plant) {
      if (n.contains(k)) return ItemGroup.plant;
    }
    for (final k in supply) {
      if (n.contains(k)) return ItemGroup.supply;
    }
    // 꽃 이름은 끝이 없다. 걸리지 않으면 절화로 본다.
    return ItemGroup.cutFlower;
  }

  /// 리포트를 만든다. 만들 수 없으면 null.
  ///
  /// [receipts] 는 사장님이 확인해 **저장한** 영수증이다. 저장 전 임시
  /// 인식 결과는 애초에 여기까지 오지 않는다.
  static MonthlyInsightReport? build(
    List<ReceiptModel> receipts, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final base = baseMonth(receipts, now: n);
    if (base == null) return null;

    final inProgress = base.year == n.year && base.month == n.month;
    final baseRs = receipts.where((r) => _inMonth(r.date, base)).toList();
    final monthTotal = baseRs.fold<double>(0, (acc, r) => acc + r.totalAmount);

    // ── 비교할 달을 고른다 ───────────────────────────────────────
    // 🔴 빈 달은 아예 뺀다. 두 달치를 3 으로 나누면 평균이 낮게 나와서
    //    멀쩡히 산 달을 "많이 썼다" 고 잘못 말하게 된다.
    final cmpMonths = <DateTime>[];
    if (!inProgress) {
      for (var i = 1; i <= compareWindow; i++) {
        final m = DateTime(base.year, base.month - i);
        if (receipts.any((r) => _inMonth(r.date, m))) cmpMonths.add(m);
      }
    }

    // 비교할 이전 달이 없거나, 아직 진행 중인 달이면 첫 달 리포트.
    if (cmpMonths.isEmpty) {
      return _firstMonthReport(
        month: base,
        baseRs: baseRs,
        monthTotal: monthTotal,
        inProgress: inProgress,
        now: n,
      );
    }

    return _compareReport(
      month: base,
      baseRs: baseRs,
      monthTotal: monthTotal,
      cmpMonths: cmpMonths,
      receipts: receipts,
    );
  }

  // ── 비교 리포트 ───────────────────────────────────────────────────
  static MonthlyInsightReport _compareReport({
    required DateTime month,
    required List<ReceiptModel> baseRs,
    required double monthTotal,
    required List<DateTime> cmpMonths,
    required List<ReceiptModel> receipts,
  }) {
    final months = cmpMonths.length;
    final label = months == 1 ? '지난달' : '지난 $months개월 평균';
    final cmpRs = receipts
        .where((r) => cmpMonths.any((m) => _inMonth(r.date, m)))
        .toList();

    // ── 1) 비교 평균을 먼저 거칠게 구한다 ────────────────────────
    final rough = _collect(cmpRs);
    final roughAvg = {for (final e in rough.entries) e.key: e.value.avg};

    // ── 2) 그 평균으로 오인식을 걸러 다시 센다 ───────────────────
    bool skip(String k, FlowerItem it) =>
        _outlier(it.unitPrice, roughAvg[k] ?? 0);

    final cmpAgg = _collect(cmpRs, skip: skip);
    final baseAgg = _collect(baseRs, skip: skip);

    // 비교 기간이 두 달 이상이면 "두 번 이상 산 것" 만 본다. 한 달뿐일
    // 때까지 두 번을 요구하면 막 시작한 사장님께는 늘 빈 화면이 된다.
    final minTimes = months >= 2 ? 2 : 1;

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
        body: '$label보다 ${InsightFmt.pct(ratio)} 높은 가격으로 '
            '$qtyText을 매입했어요. 시즌 영향일 수 있어요.',
      ));
    }
    // 아낄 수 있는 돈이 큰 것부터.
    rises.sort((a, b) => b.saving.compareTo(a.saving));
    cards.addAll(rises.take(maxPriceCards));

    // ── 지출 카드 ────────────────────────────────────────────────
    final cmpTotal = cmpRs.fold<double>(0, (acc, r) => acc + r.totalAmount);
    final cmpAvgTotal = cmpTotal / months;

    if (cmpAvgTotal > 0) {
      final ratio = (monthTotal - cmpAvgTotal) / cmpAvgTotal;
      if (ratio >= spendThreshold) {
        cards.add(InsightCard(
          kind: InsightKind.spending,
          title: '이번 달 지출 증가',
          ratio: ratio,
          fromTo: '$label ${InsightFmt.manwon(cmpAvgTotal)}',
          // 지출 카드에는 절감 여지를 매기지 않는다. (사장님 지시)
          saving: 0,
          body: '$label보다 ${InsightFmt.pct(ratio)} 많이 매입했어요. '
              '시즌 영향일 수 있어요.',
        ));
      }
    }

    return MonthlyInsightReport(
      month: month,
      receiptCount: baseRs.length,
      monthTotal: monthTotal,
      cards: cards,
      compareMonths: months,
    );
  }

  // ── 첫 달 리포트 ──────────────────────────────────────────────────
  /// 비교할 이전 달이 없을 때. 오른 것이 없으니 **절감 여지도 없다.**
  static MonthlyInsightReport _firstMonthReport({
    required DateTime month,
    required List<ReceiptModel> baseRs,
    required double monthTotal,
    required bool inProgress,
    required DateTime now,
  }) {
    final agg = _collect(baseRs);
    final cards = <InsightCard>[];

    // ── 품목 비중 ────────────────────────────────────────────────
    final byGroup = <ItemGroup, double>{};
    var itemsTotal = 0.0;
    for (final e in agg.entries) {
      final g = groupOf(e.key.split('|').first);
      byGroup[g] = (byGroup[g] ?? 0) + e.value.amount;
      itemsTotal += e.value.amount;
    }

    if (itemsTotal > 0) {
      double share(ItemGroup g) => (byGroup[g] ?? 0) / itemsTotal;
      final rest = [ItemGroup.plant, ItemGroup.etc]
          .map((g) => '${g.label} ${InsightFmt.pct(share(g))}')
          .join(' · ');
      cards.add(InsightCard(
        kind: InsightKind.mix,
        title: '이번 달 매입 구성',
        headline: '절화 ${InsightFmt.pct(share(ItemGroup.cutFlower))}',
        fromTo: '부자재 ${InsightFmt.pct(share(ItemGroup.supply))}',
        body: '$rest 였어요. 품목 이름으로 나눈 값이라 실제와 다를 수 있어요.',
      ));
    }

    // ── 많이 산 품목 ─────────────────────────────────────────────
    final sorted = agg.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    if (sorted.isNotEmpty) {
      final lines = <String>[];
      for (final e in sorted.take(topItems)) {
        final name = e.key.split('|').first;
        final unit = e.key.split('|').last;
        final qty = '${InsightFmt.comma(e.value.qty)}${unit.isEmpty ? '' : unit}';
        lines.add('$name $qty · 평균 ${InsightFmt.won(e.value.avg)}');
      }
      cards.add(InsightCard(
        kind: InsightKind.top,
        title: '많이 산 품목',
        lines: lines,
        body: '매입액이 큰 순서예요.',
      ));
    }

    return MonthlyInsightReport(
      month: month,
      receiptCount: baseRs.length,
      monthTotal: monthTotal,
      cards: cards,
      compareMonths: 0,
      inProgress: inProgress,
      asOf: inProgress ? now : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 품목별 지출 분석 (#184)
// ═══════════════════════════════════════════════════════════════════════

/// 품목군 한 조각. 도넛 한 칸과 그 아래 한 줄이 같은 값을 쓴다.
@immutable
class GroupSlice {
  const GroupSlice({
    required this.group,
    required this.amount,
    required this.share,
  });

  final ItemGroup group;
  final double amount;

  /// 0.68 = 68%. **원래 값**이다.
  final double share;

  /// 화면에 적는 이름. 절화만 `절화(꽃)` 로 적는다.
  String get label =>
      group == ItemGroup.cutFlower ? '절화(꽃)' : group.label;

  /// 면세·과세 표시.
  ///
  /// 🔴 이건 **품목 분류에서 짐작한 값**이다. 실제 과세 여부는 받은
  ///    계산서·세금계산서가 정한다. 화면 맨 아래에 그렇게 적어 둔다.
  String get taxLabel => switch (group) {
        ItemGroup.cutFlower => '면세',
        ItemGroup.supply => '과세',
        ItemGroup.plant => '면세/과세',
        ItemGroup.etc => '과세',
      };

  /// `면세 · 68.0%`
  String get sub => '$taxLabel · ${InsightFmt.pct(share)}';
}

/// 절화 품목 한 줄.
@immutable
class ItemSpendRow {
  const ItemSpendRow({
    required this.name,
    required this.amount,
    this.qty = 0,
    this.unit = '',
    this.delta,
    this.isNew = false,
    this.isOther = false,
  });

  /// 보여줄 이름. 처음 만난 영수증의 표기를 그대로 쓴다.
  final String name;
  final double amount;

  /// 0 이면 수량을 적지 않는다.
  final double qty;

  /// 비어 있으면 수량을 적지 않는다. (단위가 섞여 있었다는 뜻)
  final String unit;

  /// 전월 대비. null 이면 **적지 않는다.**
  ///
  /// 🔴 지난달 금액이 5만원 미만이면 비율이 널뛴다. 3만원이 9만원이 되면
  ///    `+200%` 가 되는데, 그건 "값이 올랐다" 가 아니라 "그 달에 조금
  ///    샀다" 는 뜻이다. 그래서 아예 숨긴다.
  final double? delta;

  /// 지난 기간에 아예 없던 품목.
  final bool isNew;

  /// `기타 절화` 묶음인가. 늘고 준 품목 문장에서 뺀다.
  final bool isOther;

  bool get hasQty => qty > 0 && unit.isNotEmpty;

  /// `90단`
  String get qtyText => hasQty ? '${InsightFmt.comma(qty)}$unit' : '';

  /// `+29.0%` · `신규` · 빈 글자.
  String get deltaText {
    final d = delta;
    if (d != null) return InsightFmt.signedPct(d);
    return isNew ? '신규' : '';
  }

  /// `90단 · +29.0%`
  String get sub =>
      [qtyText, deltaText].where((e) => e.isNotEmpty).join(' · ');
}

/// 품목별 지출 분석 한 달치.
@immutable
class ItemSpendReport {
  const ItemSpendReport({
    required this.month,
    required this.total,
    required this.slices,
    required this.rows,
    required this.notes,
    required this.cutFlowerTotal,
    this.cutFlowerDelta,
    this.hasCompare = false,
    this.inProgress = false,
    this.asOf,
  });

  /// 보고 있는 달의 1일.
  final DateTime month;

  /// 그 달 품목 금액 합계. **영수증 합계가 아니라 품목 줄의 합**이다.
  ///
  /// 🔴 품목군 네 조각을 더한 값과 반드시 같아야 해서 이렇게 센다.
  ///    영수증 총액을 쓰면 품목이 비어 있는 영수증 때문에 도넛과 어긋난다.
  final double total;

  final List<GroupSlice> slices;

  /// 절화 품목 줄. 금액 순 네 개 + `기타 절화`.
  final List<ItemSpendRow> rows;

  /// 데이터 분석 문장.
  final List<String> notes;

  final double cutFlowerTotal;

  /// 절화 전체의 전월 대비. null 이면 적지 않는다.
  final double? cutFlowerDelta;

  /// 비교할 기간에 영수증이 있었나.
  final bool hasCompare;

  /// 보고 있는 달이 아직 진행 중인 이번 달인가.
  final bool inProgress;

  /// 진행 중일 때의 '오늘'.
  final DateTime? asOf;

  bool get isEmpty => total <= 0;

  /// `2026년 7월`
  String get monthLabel => '${month.year}년 ${month.month}월';

  /// `11월 1~24일 기준`. 진행 중인 달에만.
  String? get periodNote {
    final d = asOf;
    if (!inProgress || d == null) return null;
    return '${month.month}월 1~${d.day}일 기준';
  }

  /// `지난달 같은 기간` · `지난달`
  String get compareLabel => inProgress ? '지난달 같은 기간' : '지난달';

  /// 카드 2 머리줄. `7월 2,074,000원 · 지난달 대비 +17.0%`
  String get cutFlowerHead {
    final head = '${month.month}월 ${InsightFmt.won(cutFlowerTotal)}';
    final d = cutFlowerDelta;
    if (d == null) return head;
    return '$head · $compareLabel 대비 ${InsightFmt.signedPct(d)}';
  }

  /// 막대 길이의 기준. 1위 금액.
  double get topAmount => rows.isEmpty ? 0 : rows.first.amount;

  static const String emptyNote = '영수증을 찍으면 품목별로 정리해 드려요';

  static const String taxNote =
      '면세·과세 표시는 품목 분류 기준 참고용이에요. '
      '실제 신고는 받은 계산서·세금계산서를 확인하세요.';
}

/// 이름으로 묶은 품목 하나.
class _NameAgg {
  String display = '';
  double amount = 0;
  double qty = 0;
  final Set<String> units = <String>{};

  /// 단위가 한 가지일 때만 수량을 쓴다. 섞여 있으면 빈 글자.
  String get unit => units.length == 1 ? units.first : '';
}

/// 품목별 지출 분석의 **셈만** 맡는다. 화면을 모른다. (#184)
///
/// 분류·가중평균·다듬기는 [MonthlyInsight] · [InsightFmt] 것을 그대로 쓴다.
/// 같은 값을 두 군데서 구하면 한쪽만 고치고 잊는다.
///
/// ## 비교 기간
///
/// ```
///   보고 있는 달이 진행 중인 이번 달 → 지난달의 **같은 기간**(1일~오늘)
///   그 이전 달                      → 지난달 **한 달 전체**
///   비교할 기간에 영수증이 없으면    → 비교 문구와 % 를 아예 숨긴다
/// ```
///
/// 🔴 진행 중인 달을 지난달 한 달과 견주면 늘 "덜 썼다" 가 된다.
///    달이 끝나지 않았으니 당연한 건데, 그걸 변화라고 말하면 거짓말이다.
class ItemSpend {
  ItemSpend._();

  /// 이 금액 미만인 지난달 품목은 비율을 내지 않는다.
  static const double minCompareAmount = 50000;

  /// 절화 품목을 몇 개까지 따로 보여 주나. 나머지는 `기타 절화`.
  static const int topRows = 4;

  /// 묶음 줄 이름.
  static const String otherLabel = '기타 절화';

  /// 품목 이름을 묶는 열쇠.
  ///
  /// **띄어쓰기·괄호·대소문자만** 무시한다. 그 이상 손대면 `장미` 와
  /// `장미(레드)` 가 한 줄이 되어 버린다. 둘은 값이 다른 품목이다.
  static String nameKey(String raw) {
    const drop = '()[]{}（）［］ \t';
    final b = StringBuffer();
    for (final ch in raw.toLowerCase().split('')) {
      if (drop.contains(ch)) continue;
      b.write(ch);
    }
    return b.toString();
  }

  static bool _inMonth(DateTime d, DateTime m) =>
      d.year == m.year && d.month == m.month;

  /// 품목군별 금액.
  static Map<ItemGroup, double> _byGroup(List<ReceiptModel> rs) {
    final out = <ItemGroup, double>{};
    for (final r in rs) {
      for (final it in r.items) {
        if (it.name.trim().isEmpty) continue;
        final amount = it.unitPrice * it.quantity;
        if (amount <= 0) continue;
        out.update(MonthlyInsight.groupOf(it.name), (v) => v + amount,
            ifAbsent: () => amount);
      }
    }
    return out;
  }

  /// 절화만 이름으로 묶는다.
  static Map<String, _NameAgg> _cutFlowers(List<ReceiptModel> rs) {
    final out = <String, _NameAgg>{};
    for (final r in rs) {
      for (final it in r.items) {
        final raw = it.name.trim();
        if (raw.isEmpty) continue;
        if (MonthlyInsight.groupOf(raw) != ItemGroup.cutFlower) continue;
        final amount = it.unitPrice * it.quantity;
        if (amount <= 0) continue;
        final a = out.putIfAbsent(nameKey(raw), _NameAgg.new);
        if (a.display.isEmpty) a.display = raw;
        a.amount += amount;
        a.qty += it.quantity;
        if (it.unit.trim().isNotEmpty) a.units.add(it.unit.trim());
      }
    }
    return out;
  }

  /// 전월 대비. 지난달이 5만원 미만이면 null (적지 않는다).
  static double? _delta(double now, double? before) {
    if (before == null || before < minCompareAmount) return null;
    return (now - before) / before;
  }

  /// 한 달치 분석을 만든다.
  ///
  /// [month] 를 비워 두면 이번 달. [now] 는 테스트에서 '오늘'을 고정한다.
  static ItemSpendReport build(
    List<ReceiptModel> receipts, {
    DateTime? month,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final m = month == null
        ? DateTime(n.year, n.month)
        : DateTime(month.year, month.month);
    final inProgress = m.year == n.year && m.month == n.month;

    // 진행 중인 달은 오늘까지만 센다. 비교할 지난달도 같은 날짜까지만.
    final cutDay = inProgress ? n.day : 31;
    final prev = DateTime(m.year, m.month - 1);

    List<ReceiptModel> pick(DateTime target) => receipts
        .where((r) => _inMonth(r.date, target) && r.date.day <= cutDay)
        .toList();

    final baseRs = pick(m);
    final prevRs = pick(prev);
    final hasCompare = prevRs.isNotEmpty;

    // ── 카드 1 : 품목군 도넛 ─────────────────────────────────────
    final byGroup = _byGroup(baseRs);
    final total = byGroup.values.fold<double>(0, (s, v) => s + v);

    const order = [
      ItemGroup.cutFlower,
      ItemGroup.supply,
      ItemGroup.plant,
      ItemGroup.etc,
    ];
    final slices = <GroupSlice>[
      for (final g in order)
        if ((byGroup[g] ?? 0) > 0)
          GroupSlice(
            group: g,
            amount: byGroup[g]!,
            share: total <= 0 ? 0 : byGroup[g]! / total,
          ),
    ];

    final cutTotal = byGroup[ItemGroup.cutFlower] ?? 0;

    if (total <= 0) {
      return ItemSpendReport(
        month: m,
        total: 0,
        slices: const [],
        rows: const [],
        notes: const [],
        cutFlowerTotal: 0,
        hasCompare: hasCompare,
        inProgress: inProgress,
        asOf: inProgress ? n : null,
      );
    }

    // ── 카드 2 : 절화 품목별 매입 ────────────────────────────────
    final nowItems = _cutFlowers(baseRs);
    final prevItems = hasCompare ? _cutFlowers(prevRs) : <String, _NameAgg>{};

    final prevGroup = hasCompare ? _byGroup(prevRs) : <ItemGroup, double>{};
    final prevCut = prevGroup[ItemGroup.cutFlower] ?? 0;
    final prevTotal = prevGroup.values.fold<double>(0, (s, v) => s + v);

    final sorted = nowItems.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));

    /// 품목 한 줄 만들기. [key] 가 null 이면 묶음 줄.
    ItemSpendRow rowOf(String key, _NameAgg a) {
      final before = prevItems[key]?.amount;
      return ItemSpendRow(
        name: a.display,
        amount: a.amount,
        qty: a.qty,
        unit: a.unit,
        delta: hasCompare ? _delta(a.amount, before) : null,
        isNew: hasCompare && (before == null || before == 0),
      );
    }

    final rows = <ItemSpendRow>[
      for (final e in sorted.take(topRows)) rowOf(e.key, e.value),
    ];

    // 나머지를 `기타 절화` 로 묶는다.
    final rest = sorted.skip(topRows).toList();
    if (rest.isNotEmpty) {
      final bundle = _NameAgg()..display = otherLabel;
      var restBefore = 0.0;
      for (final e in rest) {
        bundle.amount += e.value.amount;
        bundle.qty += e.value.qty;
        bundle.units.addAll(e.value.units);
        restBefore += prevItems[e.key]?.amount ?? 0;
      }
      rows.add(ItemSpendRow(
        name: otherLabel,
        amount: bundle.amount,
        qty: bundle.qty,
        unit: bundle.unit,
        delta: hasCompare ? _delta(bundle.amount, restBefore) : null,
        isNew: hasCompare && restBefore == 0,
        isOther: true,
      ));
    }

    // ── 카드 3 : 데이터 분석 ─────────────────────────────────────
    final notes = <String>[];
    if (sorted.isNotEmpty && cutTotal > 0) {
      final top = sorted.first.value;
      notes.add('${top.display}에 가장 많이 썼어요. '
          '절화 지출의 ${InsightFmt.pct(top.amount / cutTotal)}인 '
          '${InsightFmt.won(top.amount)}이에요.');
    }

    if (!hasCompare) {
      notes.add(MonthlyInsightReport.firstMonthNote);
      return ItemSpendReport(
        month: m,
        total: total,
        slices: slices,
        rows: rows,
        notes: notes,
        cutFlowerTotal: cutTotal,
        hasCompare: false,
        inProgress: inProgress,
        asOf: inProgress ? n : null,
      );
    }

    // 🔴 늘고 준 품목은 **실제 품목**만 본다. `기타 절화` 묶음은 여러
    //    품목을 합친 것이라, 거기에 +36% 가 붙어도 무엇이 오른 건지
    //    알 수 없다. 그런 문장은 아무 도움이 안 된다.
    final moved = <(String, double)>[];
    for (final e in sorted) {
      final d = _delta(e.value.amount, prevItems[e.key]?.amount);
      if (d == null) continue;
      moved.add((e.value.display, d));
    }
    moved.sort((a, b) => b.$2.compareTo(a.$2));

    if (moved.isNotEmpty && moved.first.$2 > 0) {
      final up = moved.first;
      notes.add('${up.$1} 매입은 전월 대비 '
          '${InsightFmt.pct(up.$2)} 늘었어요.');
    }
    if (moved.isNotEmpty && moved.last.$2 < 0) {
      final down = moved.last;
      notes.add('${down.$1} 매입은 전월 대비 '
          '${InsightFmt.pct(down.$2.abs())} 줄었어요.');
    }

    double? cutDelta;
    if (prevCut >= minCompareAmount) cutDelta = (cutTotal - prevCut) / prevCut;

    if (prevTotal > 0) {
      final nowShare = cutTotal / total;
      final beforeShare = prevCut / prevTotal;
      final diff = (nowShare - beforeShare) * 100;
      final word = diff >= 0 ? '늘었어요' : '줄었어요';
      final gap = (diff.abs() * 10).round() / 10;
      notes.add('전체 지출에서 절화 비중은 ${InsightFmt.pct(nowShare)}로, '
          '전월 대비 ${gap.toStringAsFixed(1)}%p $word.');
    }

    return ItemSpendReport(
      month: m,
      total: total,
      slices: slices,
      rows: rows,
      notes: notes,
      cutFlowerTotal: cutTotal,
      cutFlowerDelta: cutDelta,
      hasCompare: true,
      inProgress: inProgress,
      asOf: inProgress ? n : null,
    );
  }
}
