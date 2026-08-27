import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/receipt_model.dart';
import '../../services/vendor_tax_service.dart';
import 'fn_data.dart';

/// 정산(구매 내역) 화면용 **실 데이터** 어댑터.
///
/// 시안 `AppH2Mvp` 는 `vendors` 하드코딩 배열(`{id, name, lastDate, months}`)을
/// 전제로 작성되어 있다. 디자인은 그대로 유지하면서 데이터만 실제
/// `ReceiptProvider.allReceipts` 에서 만들어 꽂아주기 위해, 영수증 목록을
/// 시안과 동일한 `FnVendor` 형태로 변환한다.
///
/// - `id`      : 거래처명을 그대로 사용 (영수증에 거래처 PK가 없다)
/// - `lastDate`: 시안과 같은 `MM.dd` 포맷
/// - `months`  : `'01'`~`'12'` → 해당 연도의 월별 합계
class SettleLiveData {
  const SettleLiveData({
    required this.vendors,
    required this.years,
    required this.receipts,
  });

  /// 시안 `vendors` 와 동일한 형태 (선택된 연도 기준)
  final List<FnVendor> vendors;

  /// 실제 데이터에 존재하는 연도 목록 (내림차순, 문자열)
  final List<String> years;

  /// 선택된 연도의 영수증 (정산서 생성에 필요)
  final List<ReceiptModel> receipts;

  bool get isEmpty => vendors.isEmpty;

  /// 특정 거래처 + 월 목록에 해당하는 영수증만 골라낸다.
  List<ReceiptModel> receiptsOf(String vendorName, List<String> months) {
    final keys = months.toSet();
    return receipts
        .where((r) =>
            r.storeName == vendorName &&
            keys.contains(r.date.month.toString().padLeft(2, '0')))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 영수증 → 시안 형태로 변환.
  ///
  /// [year] 가 주어지면 그 연도만, 없으면 전체 연도를 합산한다.
  static SettleLiveData build(List<ReceiptModel> all, {String? year}) {
    // 존재하는 연도 (내림차순)
    final yearSet = all.map((r) => r.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final years = yearSet.map((y) => y.toString()).toList();

    final target = year ?? (years.isNotEmpty ? years.first : null);
    final scoped = target == null
        ? const <ReceiptModel>[]
        : all.where((r) => r.date.year.toString() == target).toList();

    // 거래처별 그룹
    final grouped = <String, List<ReceiptModel>>{};
    for (final r in scoped) {
      final name = r.storeName.trim().isEmpty ? '거래처 미확인' : r.storeName.trim();
      grouped.putIfAbsent(name, () => []).add(r);
    }

    final vendors = grouped.entries.map((e) {
      final months = <String, double>{
        for (final m in FnSettleData.months) m: 0,
      };
      DateTime? last;
      for (final r in e.value) {
        final key = r.date.month.toString().padLeft(2, '0');
        months[key] = (months[key] ?? 0) + r.totalAmount;
        if (last == null || r.date.isAfter(last)) last = r.date;
      }
      final md = last == null
          ? '-'
          : '${last.month.toString().padLeft(2, '0')}.'
              '${last.day.toString().padLeft(2, '0')}';
      return FnVendor(id: e.key, name: e.key, lastDate: md, months: months);
    }).toList();

    return SettleLiveData(vendors: vendors, years: years, receipts: scoped);
  }

  /// 시안 `visibleMonths` 와 같은 규칙: 값이 있는 월만 노출.
  ///
  /// ```js
  /// visibleMonths = (filterMonth === '전체' ? months : [key(filterMonth)])
  ///   .filter(m => vendors.some(v => v.months[m] > 0));
  /// ```
  List<String> visibleMonths(String monthFilter) {
    final base = monthFilter == '전체'
        ? FnSettleData.months
        : [
            FnSettleData.monthLabel.entries
                .firstWhere((e) => e.value == monthFilter,
                    orElse: () => const MapEntry('', ''))
                .key,
          ];
    return base
        .where((m) =>
            m.isNotEmpty && vendors.any((v) => (v.months[m] ?? 0) > 0))
        .toList();
  }

  /// 거래처 과세 유형 — 실제 `VendorTaxService` 를 사용한다.
  static TaxType taxOf(String vendor) => VendorTaxService.instance.typeOf(vendor);

  /// 공급가액 / 부가세 분리 — 실제 `VendorTaxService.split` 사용.
  static TaxSplit split(String vendor, double amount) =>
      VendorTaxService.instance.split(vendor, amount);

  // ══════════════════════════════════════════════════════════════
  //  구매 내역 화면 — 날짜별 / 업체별 보기
  // ══════════════════════════════════════════════════════════════

  /// 이 연도 전체 매입 합계.
  double get yearTotal =>
      receipts.fold<double>(0, (s, r) => s + r.totalAmount);

  int get receiptCount => receipts.length;

  // ══════════════════════════════════════════════════════════════
  //  조회 기간(scope) — 연도 + 월
  // ══════════════════════════════════════════════════════════════

  /// 월 필터까지 적용한 영수증.
  ///
  /// 🔴 이 값이 **헤더에 찍히는 금액이면서 동시에 점유율의 분모**다.
  ///    시안 숫자를 직접 검산해서 이렇게 묶었다:
  ///      헤더 `2026년 7월 총 매입` = ₩1,184,000
  ///      그린플러스 123,000 / 1,184,000 = 10.4% → 시안 `10%`
  ///      미림화훼  107,000 / 1,184,000 =  9.0% → 시안  `9%`
  ///      화람원예  352,000 / 1,184,000 = 29.7% → 시안 `30%`
  ///    세 개 다 맞는다. 즉 시안의 기준은 "헤더에 보이는 금액"이다.
  ///
  ///    "1년 중에 얼마나 차지하는지" 라는 요청과도 어긋나지 않는다 —
  ///    기본 칩이 `2026년 전체`(시안 그대로)라서 기본 분모는 연도 전체다.
  ///    월을 고르면 헤더와 퍼센트가 **같이** 그 월 기준으로 바뀐다.
  ///
  ///    분모를 "보이는 목록의 합"으로 하지는 **않는다**. 그러면 검색어나
  ///    과세 필터를 건드릴 때마다 같은 거래처의 %가 달라져서 숫자를
  ///    믿을 수 없게 된다.
  List<ReceiptModel> scopedReceipts(String monthFilter) {
    final m = monthNumberOf(monthFilter);
    if (m == null) return receipts;
    return receipts.where((r) => r.date.month == m).toList();
  }

  /// 헤더 금액 = 점유율의 분모.
  double periodTotal(String monthFilter) =>
      scopedReceipts(monthFilter).fold<double>(0, (s, r) => s + r.totalAmount);

  /// 헤더의 `N건`.
  int periodCount(String monthFilter) => scopedReceipts(monthFilter).length;

  /// `'7월'` → `7`, `'전체'` → `null`.
  static int? monthNumberOf(String monthFilter) {
    if (monthFilter == '전체') return null;
    return int.tryParse(monthFilter.replaceAll('월', '').trim());
  }

  /// 날짜별 보기 — 같은 날의 영수증을 하나로 묶어 최신순으로.
  ///
  /// [vendorWhere] 는 거래처명 기준 추가 조건이다(예: 전송 상태).
  /// 🔴 두 보기가 **같은 조건**을 받도록 시그니처를 맞춰둔다.
  ///    한쪽에만 필터가 걸리면 "업체별에서는 3곳인데 날짜별로 보면 5곳"
  ///    같은 모순이 생기고, 그때부터 사용자는 숫자를 믿지 않는다.
  List<SettleDayGroup> dayGroups({
    String? query,
    TaxType? tax,
    bool Function(String vendor)? vendorWhere,
    String monthFilter = '전체',
  }) {
    final q = (query ?? '').trim();

    final matched = scopedReceipts(monthFilter).where((r) {
      final name = _vendorKey(r);
      if (q.isNotEmpty && !name.contains(q)) return false;
      if (tax != null && taxOf(name) != tax) return false;
      if (vendorWhere != null && !vendorWhere(name)) return false;
      return true;
    });

    // 같은 날짜(연-월-일)로 묶는다. 시각은 무시한다 —
    // 사용자는 "7월 24일에 뭘 샀나" 를 보고 싶은 것이다.
    final byDay = <DateTime, List<ReceiptModel>>{};
    for (final r in matched) {
      final key = DateTime(r.date.year, r.date.month, r.date.day);
      byDay.putIfAbsent(key, () => []).add(r);
    }

    final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        SettleDayGroup(
          date: k,
          receipts: byDay[k]!
            ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount)),
        ),
    ];
  }

  /// 업체별 보기 — 조회 기간 전체 대비 점유율까지 계산해서 돌려준다.
  List<SettleVendorShare> vendorShares({
    String? query,
    TaxType? tax,
    String sortBy = 'amountDesc',
    bool Function(String vendor)? vendorWhere,
    String monthFilter = '전체',
  }) {
    final q = (query ?? '').trim();

    final scoped = scopedReceipts(monthFilter);
    // 🔴 분모는 헤더와 **동일한** 기간 합계다. 검색·과세·전송 필터가
    //    아무리 걸려도 이 값은 변하지 않으므로 개별 %가 흔들리지 않는다.
    final denom = scoped.fold<double>(0, (s, r) => s + r.totalAmount);

    final byVendor = <String, List<ReceiptModel>>{};
    for (final r in scoped) {
      byVendor.putIfAbsent(_vendorKey(r), () => []).add(r);
    }

    final out = <SettleVendorShare>[];
    byVendor.forEach((name, rs) {
      if (q.isNotEmpty && !name.contains(q)) return;
      final t = taxOf(name);
      if (tax != null && t != tax) return;
      if (vendorWhere != null && !vendorWhere(name)) return;

      final total = rs.fold<double>(0, (s, r) => s + r.totalAmount);
      rs.sort((a, b) => b.date.compareTo(a.date));

      out.add(SettleVendorShare(
        name: name,
        total: total,
        // 🔴 분모가 0 이면 나눗셈이 NaN 이 되고, 그 NaN 이 그대로
        //    바 너비(`FractionallySizedBox.widthFactor`)로 들어가면
        //    렌더링이 터진다. 0 으로 막는다.
        share: denom <= 0 ? 0 : total / denom,
        receipts: rs,
        tax: t,
      ));
    });

    switch (sortBy) {
      case 'name':
        out.sort((a, b) => a.name.compareTo(b.name));
      case 'amountAsc':
        out.sort((a, b) => a.total.compareTo(b.total));
      case 'recent':
        out.sort((a, b) => b.receipts.first.date.compareTo(
            a.receipts.first.date));
      default:
        out.sort((a, b) => b.total.compareTo(a.total));
    }
    return out;
  }

  /// 거래처명 정규화. 두 보기가 **같은 키**를 써야 묶음이 어긋나지 않는다.
  static String _vendorKey(ReceiptModel r) =>
      r.storeName.trim().isEmpty ? '거래처 미확인' : r.storeName.trim();
}

/// 영수증의 품목을 한 줄 요약으로 만든다.
///
/// 시안 날짜별: `장미(레드) · 거베라 · 수국`
/// 시안 업체별: `장미(레드) 외 2건`
///
/// 🔴 OCR 품목명은 틀릴 수 있다. 그래도 보여주는 이유는, 금액만 있으면
///    "이게 무슨 거래였는지" 사용자가 기억하지 못하기 때문이다.
///    다만 **정산 문서에는 요청서 종류에 품목을 넣지 않는다** — 화면에서
///    참고용으로 보는 것과, 거래처에 보내는 문서에 박는 것은 다르다.
String receiptItemSummary(ReceiptModel r, {int max = 3}) {
  final names = <String>[];
  for (final it in r.items) {
    final n = it.name.trim();
    if (n.isEmpty) continue;
    final label = (it.color ?? '').trim().isEmpty ? n : '$n(${it.color})';
    if (!names.contains(label)) names.add(label);
  }
  if (names.isEmpty) return '품목 정보 없음';
  if (names.length <= max) return names.join(' · ');
  return '${names.take(max).join(' · ')} 외 ${names.length - max}건';
}

/// 업체별 목록의 영수증 한 줄 요약 — 시안 `장미(레드) 외 2건`
String receiptShortSummary(ReceiptModel r) => receiptItemSummary(r, max: 1);

/// 날짜별 카드의 품목 줄 — 프로토타입 원본 `AppH10`:
///
/// ```js
/// div{fontSize:12.5, color:MUTE, marginTop:6, paddingLeft:41, ellipsis}
///   t.items.map(i => i[0]).join(' · ')
/// ```
///
/// 🔴 원본은 **`외 N건`으로 줄이지 않는다.** 품목 전체를 ` · `로 이어 붙이고,
///    넘치면 CSS `text-overflow: ellipsis`가 잘라낸다. Flutter에서도 마찬가지로
///    문자열은 자르지 않고 `TextOverflow.ellipsis`에 맡긴다 —
///    화면 폭에 따라 보이는 양이 달라지는 것이 원본의 "반응형" 동작이다.
///
/// `receiptItemSummary`/`receiptShortSummary`는 업체별 펼침 줄에서 쓰이므로
/// 건드리지 않는다(테스트가 정확한 출력을 검증한다).
String receiptFullItemList(ReceiptModel r) {
  final names = <String>[];
  for (final it in r.items) {
    final n = it.name.trim();
    if (n.isEmpty) continue;
    final label = (it.color ?? '').trim().isEmpty ? n : '$n(${it.color})';
    if (!names.contains(label)) names.add(label);
  }
  if (names.isEmpty) return '품목 정보 없음';
  return names.join(' · ');
}

/// 날짜별 보기의 한 날짜 묶음.
class SettleDayGroup {
  const SettleDayGroup({required this.date, required this.receipts});

  final DateTime date;
  final List<ReceiptModel> receipts;

  double get total => receipts.fold<double>(0, (s, r) => s + r.totalAmount);
  int get count => receipts.length;

  /// `'7월'`
  String get monthLabel => '${date.month}월';

  /// `'24'`
  String get dayLabel => date.day.toString();

  /// `'금'` — 시안의 요일 표기.
  ///
  /// `intl` 의 `DateFormat('E','ko')` 는 로케일 데이터 초기화가 필요해서
  /// 플랫폼에 따라 실패할 수 있다. 요일 7개는 직접 쓰는 게 확실하다.
  String get weekdayLabel =>
      const ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1];
}

/// 업체별 보기의 한 거래처.
class SettleVendorShare {
  const SettleVendorShare({
    required this.name,
    required this.total,
    required this.share,
    required this.receipts,
    required this.tax,
  });

  final String name;
  final double total;

  /// 연도 전체 매입 대비 비중 (0.0 ~ 1.0)
  final double share;

  /// 최신순 영수증
  final List<ReceiptModel> receipts;

  final TaxType tax;

  int get count => receipts.length;

  /// 시안 `2건 · 최근 07.24`
  String get lastDateLabel {
    if (receipts.isEmpty) return '-';
    final d = receipts.first.date;
    return '${d.month.toString().padLeft(2, '0')}.'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// 시안 `전체 매입의 30%`
  ///
  /// 🔴 반올림해서 0% 가 되는 거래처가 생긴다. 금액이 있는데 `0%` 라고
  ///    적으면 "안 산 걸로 잡혔나?" 하고 의심하게 된다. 그래서 값이
  ///    있으면 최소 `1%` 미만으로 표기한다.
  String get shareLabel {
    if (total <= 0) return '전체 매입의 0%';
    final pct = share * 100;
    if (pct < 1) return '전체 매입의 1% 미만';
    return '전체 매입의 ${pct.round()}%';
  }
}

/// 정산서 내보내기 이력 저장소.
///
/// 레거시 `SettlementPreviewScreen.historyKey` 와 **동일한 키/스키마**를 사용해
/// 기존 사용자의 이력이 그대로 보이게 한다.
class SettleHistoryStore {
  SettleHistoryStore._();

  /// 레거시와 동일한 SharedPreferences 키
  static const key = 'fn_settlement_history';

  static Future<List<SettleHistoryEntry>> load() async {
    final out = <SettleHistoryEntry>[];
    try {
      final p = await SharedPreferences.getInstance();
      for (final s in p.getStringList(key) ?? const <String>[]) {
        try {
          out.add(SettleHistoryEntry.fromJson(
              jsonDecode(s) as Map<String, dynamic>));
        } catch (_) {
          // 손상된 항목은 건너뛴다
        }
      }
    } catch (_) {
      // 저장소 접근 실패 시 빈 목록
    }
    return out;
  }

  /// 최신 항목을 맨 앞에 추가하고 최대 50건까지만 보관 (레거시와 동일).
  static Future<void> add(SettleHistoryEntry e) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(key) ?? <String>[];
      list.insert(0, jsonEncode(e.toJson()));
      await p.setStringList(key, list.take(50).toList());
    } catch (_) {
      // 저장 실패는 사용자 흐름을 막지 않는다
    }
  }
}

/// 레거시 스키마와 호환되는 이력 항목.
///
/// 레거시 저장 형태:
/// ```json
/// { "month":"2026-7", "vendors":["대한꽃도매"], "vendorCount":1,
///   "receiptCount":12, "total":384000, "sentAt":"2026-07-24T..." }
/// ```
/// 새 화면에서는 여기에 `months`(선택 월 라벨) / `method`(Excel|PDF) /
/// `fileCount` 를 덧붙여 저장한다. 레거시 항목에는 없으므로 모두 nullable.
class SettleHistoryEntry {
  const SettleHistoryEntry({
    required this.month,
    required this.vendors,
    required this.receiptCount,
    required this.total,
    required this.sentAt,
    this.months = const [],
    this.method,
    this.fileCount,
  });

  /// `'yyyy-M'` (레거시 포맷 유지)
  final String month;
  final List<String> vendors;
  final int receiptCount;
  final double total;
  final DateTime sentAt;

  /// 선택된 월 라벨 목록 (`['1월','2월']`) — 신규 필드
  final List<String> months;

  /// `'Excel'` | `'PDF'` — 신규 필드
  final String? method;

  /// 내보낸 파일 개수 — 신규 필드
  final int? fileCount;

  int get vendorCount => vendors.length;

  /// (아래는 이력 항목 — 구매 내역 보기와 무관)
  /// 시안 `history[].period` = `'2026.07'`
  String get period {
    final parts = month.split('-');
    if (parts.length < 2) return month;
    return '${parts[0]}.${parts[1].padLeft(2, '0')}';
  }

  /// 시안 `history[].saved` = `'07.24'`
  String get savedLabel =>
      '${sentAt.month.toString().padLeft(2, '0')}.'
      '${sentAt.day.toString().padLeft(2, '0')}';

  String get vendorLabel => vendors.isEmpty
      ? '거래처 $vendorCount곳'
      : vendors.length == 1
          ? vendors.first
          : '${vendors.first} 외 ${vendors.length - 1}곳';

  Map<String, dynamic> toJson() => {
        'month': month,
        'vendors': vendors,
        'vendorCount': vendors.length,
        'receiptCount': receiptCount,
        'total': total,
        'sentAt': sentAt.toIso8601String(),
        'months': months,
        if (method != null) 'method': method,
        if (fileCount != null) 'fileCount': fileCount,
      };

  factory SettleHistoryEntry.fromJson(Map<String, dynamic> m) {
    DateTime sent;
    try {
      sent = DateTime.parse(m['sentAt'] as String);
    } catch (_) {
      sent = DateTime.now();
    }
    return SettleHistoryEntry(
      month: (m['month'] as String?) ?? '-',
      vendors: (m['vendors'] as List?)?.cast<String>() ?? const [],
      receiptCount: (m['receiptCount'] as num?)?.toInt() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      sentAt: sent,
      months: (m['months'] as List?)?.cast<String>() ?? const [],
      method: m['method'] as String?,
      fileCount: (m['fileCount'] as num?)?.toInt(),
    );
  }
}
