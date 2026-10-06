import 'package:intl/intl.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_charts_ds.dart';
import '../../models/receipt_model.dart';
import '../../providers/receipt_provider.dart';
import '../../services/insight_service.dart';

/// 시안 `AppH3` 상단의 데이터 정의를 그대로 옮긴 모듈.
///
/// 실데이터(ReceiptProvider)가 비어 있으면 시안 숫자를 그대로 사용해
/// 프로토타입과 동일한 화면을 보여준다. 데이터가 쌓이면 실값으로 대체된다.

enum FnInsightTarget { price, compare, donut, trend }

class FnInsight {
  const FnInsight({
    required this.text,
    required this.badge,
    required this.color,
    required this.target,
  });

  final String text;

  /// insights 화면 배지 문구
  /// `it.status === 'cautionary' ? '단가 변동' : 'accent' ? '비교 안내' : '지출 점검'`
  final String badge;
  final String color; // cautionary | accent | negative
  final FnInsightTarget target;
}

class FnPriceItem {
  const FnPriceItem({
    required this.unit,
    required this.chg,
    required this.months,
    required this.locked,
    this.dates = const [],
    this.vendorPrices = const [],
  });

  final double unit;
  final int chg;
  final List<double> months;
  final bool locked;
  final List<({String label, double value})> dates;
  final List<({String vendor, double price})> vendorPrices;
}

class FnDemoData {
  const FnDemoData({
    required this.months,
    required this.spend,
    required this.thisMonth,
    required this.lastMonth,
    required this.pctUp,
    required this.receiptCount,
    required this.taxData,
    required this.priceData,
    required this.insights,
    required this.isDemo,
  });

  final List<String> months;
  final List<double> spend;
  final double thisMonth;
  final double lastMonth;
  final int pctUp;
  final int receiptCount;
  final List<FnChartDatum> taxData;
  final Map<String, FnPriceItem> priceData;
  final List<FnInsight> insights;

  /// true면 시안 데모 수치를 그리고 있다는 뜻
  final bool isDemo;
}

class FnDemo {
  FnDemo._();

  static final _fmt = NumberFormat('#,###');

  /// 시안: `const won = n => '₩' + Math.round(n).toLocaleString('ko-KR')`
  static String won(num n) => '₩${_fmt.format(n.round())}';

  /// 시안 원본 상수
  /// ```js
  /// months = ['8월','9월','10월','11월','12월','1월','2월','3월','4월','5월','6월','7월'];
  /// spend  = [212,198,231,260,340,305,218,236,254,289,262,305].map(v => v*10000);
  /// ```
  static const List<String> _months = [
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
  ];

  static const List<double> _spendRaw = [
    212,
    198,
    231,
    260,
    340,
    305,
    218,
    236,
    254,
    289,
    262,
    305,
  ];

  static List<double> get _spend => _spendRaw.map((v) => v * 10000).toList();

  /// 시안 고정 수치를 직접 참조해야 하는 서브 화면용
  static List<String> get demoMonths => _months;
  static List<double> get demoSpend => _spend;

  /// ```js
  /// taxData = [
  ///   { label:'부자재/식물 (과세)', value: 976000,  color: 'var(--violet-50)' },   // #F4796E
  ///   { label:'생화 (면세)',        value: 2074000, color: 'var(--green-50)'  },   // #86B06B
  /// ];
  /// ```
  static const List<FnChartDatum> demoTaxData = [
    FnChartDatum(
      label: '부자재/식물 (과세)',
      value: 976000,
      color: FnColors.rose60, // violet-50 = #F4796E
    ),
    FnChartDatum(
      label: '생화 (면세)',
      value: 2074000,
      color: FnColors.leaf50, // green-50 = #86B06B
    ),
  ];

  /// 시안 도넛 회전값
  static const double donutRotate = -57.6;

  /// ```js
  /// priceData = {
  ///  '장미(레드)': { unit:8000, chg:12, months:[7100,7300,7200,7600,7900,8000], locked:false,
  ///                 dates:[...], vendorPrices:[{대한꽃도매,8000},{그린플러스,8700}] },
  ///  '거베라':    { unit:6000, chg:-3, months:[6300,6200,6100,6050,6100,6000], locked:true },
  ///  '카네이션':  { unit:5200, chg: 4, months:[4900,5000,5000,5100,5150,5200], locked:true },
  ///  '국화':      { unit:3800, chg: 1, months:[3760,3770,3780,3790,3790,3800], locked:true },
  /// };
  /// ```
  static const Map<String, FnPriceItem> demoPriceData = {
    '장미(레드)': FnPriceItem(
      unit: 8000,
      chg: 12,
      months: [7100, 7300, 7200, 7600, 7900, 8000],
      locked: false,
      dates: [
        (label: '07.02', value: 7300),
        (label: '07.09', value: 7500),
        (label: '07.15', value: 7700),
        (label: '07.20', value: 7900),
        (label: '07.24', value: 8000),
      ],
      vendorPrices: [
        (vendor: '대한꽃도매', price: 8000),
        (vendor: '그린플러스', price: 8700),
      ],
    ),
    '거베라': FnPriceItem(
      unit: 6000,
      chg: -3,
      months: [6300, 6200, 6100, 6050, 6100, 6000],
      locked: true,
    ),
    '카네이션': FnPriceItem(
      unit: 5200,
      chg: 4,
      months: [4900, 5000, 5000, 5100, 5150, 5200],
      locked: true,
    ),
    '국화': FnPriceItem(
      unit: 3800,
      chg: 1,
      months: [3760, 3770, 3780, 3790, 3790, 3800],
      locked: true,
    ),
  };

  /// ```js
  /// insights = [
  ///  { color:'cautionary', text:'장미(레드) 단가가 전월 대비 +12% 상승했어요', go: price },
  ///  { color:'accent',     text:'거베라를 두 거래처에서 매입 중 — 단가 차이 8%', go: compare },
  ///  { color:'negative',   text:'대한꽃도매 매입 비중이 42%로 높아요 — 거래처 다변화를 고려해보세요', go: donut },
  ///  { color:'negative',   text:'이번 달 지출이 최근 3개월 평균 대비 21% 많아요', go: trend },
  /// ];
  /// ```
  static const List<FnInsight> demoInsights = [
    FnInsight(
      text: '장미(레드) 단가가 전월 대비 +12% 상승했어요',
      badge: '단가 변동',
      color: 'cautionary',
      target: FnInsightTarget.price,
    ),
    FnInsight(
      text: '거베라를 두 거래처에서 매입 중 — 단가 차이 8%',
      badge: '비교 안내',
      color: 'accent',
      target: FnInsightTarget.compare,
    ),
    FnInsight(
      text: '대한꽃도매 매입 비중이 42%로 높아요 — 거래처 다변화를 고려해보세요',
      badge: '지출 점검',
      color: 'negative',
      target: FnInsightTarget.donut,
    ),
    FnInsight(
      text: '이번 달 지출이 최근 3개월 평균 대비 21% 많아요',
      badge: '지출 점검',
      color: 'negative',
      target: FnInsightTarget.trend,
    ),
  ];

  /// 실데이터가 있으면 **전부** 실값으로 계산하고, 비어 있을 때만 시안 수치를 쓴다.
  ///
  /// 예전에는 `taxData` / `priceData` / `insights` 세 항목이 실데이터가 있어도
  /// 시안 고정값을 그대로 반환했다. 홈 탭의 과세/면세 도넛, 품목 시세 카드,
  /// 인사이트 카드가 실제 매입 내역과 무관한 숫자를 보여주던 원인.
  static FnDemoData resolve(ReceiptProvider rp) => resolveFrom(rp.allReceipts);

  /// `resolve` 의 순수 함수 버전 — Hive/Provider 없이 테스트할 수 있다.
  static FnDemoData resolveFrom(List<ReceiptModel> receipts) {
    if (receipts.isEmpty) {
      final spend = _spend;
      final thisMonth = spend[11];
      final lastMonth = spend[10];
      return FnDemoData(
        months: _months,
        spend: spend,
        thisMonth: thisMonth,
        lastMonth: lastMonth,
        pctUp: ((thisMonth - lastMonth) / lastMonth * 100).round(),
        receiptCount: 8,
        taxData: demoTaxData,
        priceData: demoPriceData,
        insights: demoInsights,
        isDemo: true,
      );
    }

    // 최근 12개월 실지출 집계
    final now = DateTime.now();
    final labels = <String>[];
    final values = <double>[];
    for (var i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      labels.add('${m.month}월');
      final sum = receipts
          .where((r) => r.date.year == m.year && r.date.month == m.month)
          .fold<double>(0, (s, r) => s + r.totalAmount);
      values.add(sum);
    }
    final thisMonth = values.last;
    final lastMonth = values[values.length - 2];
    final pct = lastMonth == 0
        ? 0
        : ((thisMonth - lastMonth) / lastMonth * 100).round();
    final count = receipts
        .where((r) => r.date.year == now.year && r.date.month == now.month)
        .length;

    return FnDemoData(
      months: labels,
      spend: values,
      thisMonth: thisMonth,
      lastMonth: lastMonth,
      pctUp: pct,
      receiptCount: count,
      taxData: _liveTaxData(receipts),
      priceData: _livePriceData(receipts),
      insights: _liveInsights(receipts, values),
      isDemo: false,
    );
  }

  // ── 실데이터 파생값 ────────────────────────────────────────

  /// 과세/면세 도넛 — `VendorTaxService` 분류 기준으로 실제 금액 집계.
  static List<FnChartDatum> _liveTaxData(List<ReceiptModel> receipts) {
    final b = InsightService.taxBreakdown(receipts);
    final out = <FnChartDatum>[];
    if (b.taxable > 0) {
      out.add(FnChartDatum(
        label: '부자재/식물 (과세)',
        value: b.taxable,
        color: FnColors.rose60,
      ));
    }
    if (b.exempt > 0) {
      out.add(FnChartDatum(
        label: '생화 (면세)',
        value: b.exempt,
        color: FnColors.leaf50,
      ));
    }
    // 둘 다 0이면(금액 없는 영수증만 있는 경우) 차트가 비어 깨지므로 시안값 유지
    return out.isEmpty ? demoTaxData : out;
  }

  /// 품목 시세 카드 — 구매 빈도 상위 품목의 실제 월평균 단가 시계열.
  ///
  /// 시안은 4개 품목 중 3개가 `locked: true`(프로 전용)였다.
  /// 실데이터도 동일하게 **첫 품목만 무료 공개**하고 나머지는 잠근다.
  static Map<String, FnPriceItem> _livePriceData(List<ReceiptModel> receipts) {
    final summaries = InsightService.allItemSummaries(receipts, limit: 8);
    if (summaries.isEmpty) return demoPriceData;

    final out = <String, FnPriceItem>{};
    for (var i = 0; i < summaries.length; i++) {
      final s = summaries[i];
      // 최근 6개 구간만 (시안 months 길이와 동일)
      final series =
          s.series.length > 6 ? s.series.sublist(s.series.length - 6) : s.series;

      final vendors = InsightService.comparePrices(receipts, s.name);

      out[s.name] = FnPriceItem(
        unit: s.current,
        chg: s.changePercent.round(),
        months: series.map((e) => e.avgUnitPrice).toList(),
        locked: i != 0,
        dates: series
            .map((e) => (label: e.label, value: e.avgUnitPrice))
            .toList(),
        vendorPrices: vendors
            .map((v) => (vendor: v.vendor, price: v.avgUnitPrice))
            .toList(),
      );
    }
    return out;
  }

  /// 인사이트 카드 — 실제 매입 내역에서 규칙 기반으로 생성.
  ///
  /// 시안의 4줄과 같은 4가지 유형을 유지한다:
  ///   1) 단가 급등 품목            → price
  ///   2) 같은 품목 복수 거래처 단가차 → compare
  ///   3) 특정 거래처 편중          → donut
  ///   4) 이번 달 지출이 평균 대비 과다 → trend
  /// 조건에 맞는 게 하나도 없으면 시안 문구를 그대로 보여준다.
  static List<FnInsight> _liveInsights(
      List<ReceiptModel> receipts, List<double> spend) {
    final out = <FnInsight>[];

    // 1) 전월 대비 단가 상승률이 가장 큰 품목
    final items = InsightService.allItemSummaries(receipts, limit: 20);
    ItemPriceSummary? topUp;
    for (final s in items) {
      if (s.series.length < 2) continue;
      if (!s.isUp) continue;
      if (topUp == null || s.changePercent > topUp.changePercent) topUp = s;
    }
    if (topUp != null) {
      out.add(FnInsight(
        text: '${topUp.name} 단가가 전월 대비 '
            '+${topUp.changePercent.round()}% 상승했어요',
        badge: '단가 변동',
        color: 'cautionary',
        target: FnInsightTarget.price,
      ));
    }

    // 2) 두 곳 이상에서 매입 중이고 단가 차이가 가장 큰 품목
    ({String name, int gap})? topGap;
    for (final s in items) {
      final vs = InsightService.comparePrices(receipts, s.name);
      if (vs.length < 2) continue;
      final lo = vs.first.avgUnitPrice;
      final hi = vs.last.avgUnitPrice;
      if (lo <= 0) continue;
      final gap = ((hi - lo) / lo * 100).round();
      if (gap < 3) continue;
      if (topGap == null || gap > topGap.gap) {
        topGap = (name: s.name, gap: gap);
      }
    }
    if (topGap != null) {
      out.add(FnInsight(
        text: '${topGap.name}을(를) 여러 거래처에서 매입 중 — '
            '단가 차이 ${topGap.gap}%',
        badge: '비교 안내',
        color: 'accent',
        target: FnInsightTarget.compare,
      ));
    }

    // 3) 매입 비중이 40% 이상인 거래처
    final vendors = InsightService.vendorSummaries(receipts);
    final grand = vendors.fold<double>(0, (s, v) => s + v.total);
    if (vendors.isNotEmpty && grand > 0) {
      final top = vendors.first;
      final share = (top.total / grand * 100).round();
      if (share >= 40) {
        out.add(FnInsight(
          text: '${top.name} 매입 비중이 $share%로 높아요 — '
              '거래처 다변화를 고려해보세요',
          badge: '지출 점검',
          color: 'negative',
          target: FnInsightTarget.donut,
        ));
      }
    }

    // 4) 이번 달 지출이 최근 3개월 평균보다 15% 이상 많음
    if (spend.length >= 4) {
      final cur = spend.last;
      final prev3 = spend.sublist(spend.length - 4, spend.length - 1);
      final avg = prev3.reduce((a, b) => a + b) / prev3.length;
      if (avg > 0 && cur > avg * 1.15) {
        out.add(FnInsight(
          text: '이번 달 지출이 최근 3개월 평균 대비 '
              '${((cur - avg) / avg * 100).round()}% 많아요',
          badge: '지출 점검',
          color: 'negative',
          target: FnInsightTarget.trend,
        ));
      }
    }

    return out.isEmpty ? demoInsights : out;
  }
}

// ─────────────────────────────────────────────────────────────
// AppH2 (구매 내역 / 정산) 데이터 — 시안 원본 그대로
// ─────────────────────────────────────────────────────────────

/// ```js
/// { id:'v1', name:'대한꽃도매', lastDate:'07.24',
///   months:{ '01':360000, ... '12':0 } }
/// ```
class FnVendor {
  const FnVendor({
    required this.id,
    required this.name,
    required this.lastDate,
    required this.months,
  });

  final String id;
  final String name;
  final String lastDate;

  /// key: '01'~'12'
  final Map<String, double> months;
}

/// 거래처 과세 유형
enum FnVendorTax { taxable, exempt }

class FnSettleData {
  FnSettleData._();

  static const years = ['2026', '2025'];

  static const months = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
    '11',
    '12',
  ];

  static const monthLabel = <String, String>{
    '01': '1월',
    '02': '2월',
    '03': '3월',
    '04': '4월',
    '05': '5월',
    '06': '6월',
    '07': '7월',
    '08': '8월',
    '09': '9월',
    '10': '10월',
    '11': '11월',
    '12': '12월',
  };

  static const vendors = <FnVendor>[
    FnVendor(id: 'v1', name: '대한꽃도매', lastDate: '07.24', months: {
      '01': 360000,
      '02': 340000,
      '03': 410000,
      '04': 395000,
      '05': 420000,
      '06': 480000,
      '07': 384000,
      '08': 0,
      '09': 0,
      '10': 0,
      '11': 0,
      '12': 0,
    }),
    FnVendor(id: 'v2', name: '화람원예', lastDate: '07.22', months: {
      '01': 150000,
      '02': 160000,
      '03': 170000,
      '04': 175000,
      '05': 180000,
      '06': 190000,
      '07': 242000,
      '08': 0,
      '09': 0,
      '10': 0,
      '11': 0,
      '12': 0,
    }),
    FnVendor(id: 'v3', name: '그린플러스', lastDate: '07.17', months: {
      '01': 180000,
      '02': 190000,
      '03': 195000,
      '04': 198000,
      '05': 200000,
      '06': 210000,
      '07': 255000,
      '08': 0,
      '09': 0,
      '10': 0,
      '11': 0,
      '12': 0,
    }),
    FnVendor(id: 'v4', name: '미림화훼', lastDate: '07.15', months: {
      '01': 120000,
      '02': 125000,
      '03': 130000,
      '04': 135000,
      '05': 140000,
      '06': 150000,
      '07': 197000,
      '08': 0,
      '09': 0,
      '10': 0,
      '11': 0,
      '12': 0,
    }),
  ];

  /// ```js
  /// seedVendorTaxDefaults({'화람원예':'taxable', '미림화훼':'exempt'});
  /// setVendorTax('그린플러스','taxable');
  /// ```
  static const vendorTax = <String, FnVendorTax>{
    '화람원예': FnVendorTax.taxable,
    '미림화훼': FnVendorTax.exempt,
    '그린플러스': FnVendorTax.taxable,
  };

  static FnVendorTax taxOf(String name) =>
      vendorTax[name] ?? FnVendorTax.taxable;

  /// 시안: `const hasYear = filterYear === '2026'`
  static bool hasYear(String year) => year == '2026';

  /// ```js
  /// visibleMonths = !hasYear ? []
  ///   : (filterMonth === '전체' ? months : [key(filterMonth)])
  ///       .filter(m => vendors.some(v => v.months[m] > 0));
  /// ```
  static List<String> visibleMonths(String year, String monthFilter) {
    if (!hasYear(year)) return const [];
    final base = monthFilter == '전체'
        ? months
        : [
            monthLabel.entries
                .firstWhere((e) => e.value == monthFilter,
                    orElse: () => const MapEntry('', ''))
                .key
          ];
    return base
        .where(
            (m) => m.isNotEmpty && vendors.any((v) => (v.months[m] ?? 0) > 0))
        .toList();
  }

  /// 정산 미리보기용 품목
  static const previewItems = <({String name, int qty, double amount})>[
    (name: '장미(레드)', qty: 60, amount: 480000),
    (name: '거베라', qty: 45, amount: 270000),
    (name: '카네이션', qty: 30, amount: 240000),
    (name: '포장 부자재', qty: 12, amount: 40000),
  ];

  /// 시안: `MVP_EXPORT_CAP = 3`
  static const int exportCap = 3;
}
