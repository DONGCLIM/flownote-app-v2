// 요청 #97 회귀 — 구매 내역의 **날짜별 / 업체별** 보기.
//
// 사용자 요청: "업체별 같은 경우에는 3번째 이미지처럼 우리가 1년중에 얼마나
// 차지하는지 보여주는걸로 하자."
//
// 이 테스트가 지키려는 것:
//
//  1. 점유율의 **분모는 연도 전체 매입**이다. 검색·필터로 목록이 줄어도
//     개별 거래처의 % 는 흔들리지 않아야 한다. (분모를 "보이는 목록의 합"으로
//     바꾸면 대한꽃도매 30% 가 검색 한 번에 80% 로 튀어서, 숫자를 믿을 수 없다)
//  2. 분모가 0 일 때 NaN 이 나오지 않는다. NaN 이 `FractionallySizedBox`
//     의 widthFactor 로 들어가면 렌더링이 터진다.
//  3. 점유율 합이 100% 다 (필터가 없을 때).
//  4. 날짜별/업체별이 **같은 조건**을 받으면 같은 영수증 집합을 본다.
//     한쪽에만 필터가 걸리면 "업체별은 3곳인데 날짜별로 보면 5곳" 같은
//     모순이 생기고, 그때부터 사용자는 숫자를 믿지 않는다.
//  5. 금액이 있는데 반올림해서 0% 가 되는 거래처는 `1% 미만` 으로 적는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/settle_data_live.dart';
import 'package:flow_note/screens/ds/settle_views_ds.dart';
import 'package:flow_note/services/vendor_tax_service.dart';

ReceiptModel _r(
  String id,
  String store,
  DateTime date,
  double amount, {
  List<({String name, String? color})> items = const [],
}) {
  return ReceiptModel(
    id: id,
    date: date,
    storeName: store,
    items: [
      for (final it in items)
        FlowerItem(
          name: it.name,
          quantity: 1,
          unitPrice: amount,
          unit: '단',
          color: it.color,
        ),
    ],
    totalAmount: amount,
    rawOcrText: 'test',
    createdAt: date,
  );
}

void main() {
  // 연도를 고정한다. `SettleLiveData.build` 는 year 인자가 null 이면
  // 데이터에 있는 가장 최근 연도를 쓴다.
  const y = 2026;
  DateTime d(int m, int day) => DateTime(y, m, day);

  // 시안과 같은 구성: 면세 생화 2곳 + 과세 부자재 1곳
  List<ReceiptModel> sample() => [
        _r('1', '대한꽃도매', d(7, 24), 256000,
            items: [
              (name: '장미', color: '레드'),
              (name: '거베라', color: null),
              (name: '수국', color: null),
            ]),
        _r('2', '대한꽃도매', d(7, 20), 132000,
            items: [(name: '안스리움', color: null)]),
        _r('3', '대한꽃도매', d(7, 8), 212000,
            items: [(name: '장미', color: '화이트')]),
        _r('4', '그린플러스', d(7, 24), 100000,
            items: [(name: '포장리본', color: null)]),
        _r('5', '화람원예', d(7, 22), 300000,
            items: [(name: '장미', color: '핑크')]),
      ];

  group('SettleLiveData — 연간 점유율(업체별)', () {
    test('분모는 연도 전체 매입 합계다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      // 256000 + 132000 + 212000 + 100000 + 300000
      expect(data.yearTotal, 1000000);
      expect(data.receiptCount, 5);

      final shares = data.vendorShares();
      final map = {for (final s in shares) s.name: s};

      expect(map['대한꽃도매']!.total, 600000);
      expect(map['대한꽃도매']!.share, closeTo(0.60, 1e-9));
      expect(map['화람원예']!.share, closeTo(0.30, 1e-9));
      expect(map['그린플러스']!.share, closeTo(0.10, 1e-9));
    });

    test('점유율 합은 100% 다', () {
      final data = SettleLiveData.build(sample(), year: '$y');
      final sum =
          data.vendorShares().fold<double>(0, (s, e) => s + e.share);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('🔴 검색으로 목록이 줄어도 개별 % 는 그대로다', () {
      // 이게 이 요청의 핵심이다. 분모를 "보이는 목록의 합" 으로 바꾸면
      // 아래 두 값이 달라지고, 사용자는 같은 거래처의 다른 퍼센트를 보게 된다.
      final data = SettleLiveData.build(sample(), year: '$y');

      final all = data.vendorShares().firstWhere((s) => s.name == '대한꽃도매');
      final filtered = data
          .vendorShares(query: '대한')
          .firstWhere((s) => s.name == '대한꽃도매');

      expect(filtered.share, all.share);
      expect(filtered.share, closeTo(0.60, 1e-9));
      // 목록 자체는 실제로 줄어들었는지도 확인 (필터가 동작 안 해서
      // 우연히 같은 값이 나온 게 아니어야 한다)
      expect(data.vendorShares(query: '대한').length, 1);
    });

    test('🔴 과세 필터를 걸어도 개별 % 는 그대로다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      // ⚠️ `화람원예` 가 과세로 잡히는 건 `VendorTaxService._guess` 의
      //    `원예` 힌트 때문이다. 시안 3번째 이미지에는 화람원예가 **면세**
      //    배지로 그려져 있어 실제 분류와 어긋난다. 여기서는 있는 그대로의
      //    동작을 고정한다 — 분류 규칙을 바꾸면 정산 문서의 과세/면세 분리
      //    금액까지 같이 달라지므로, 사용자 확인 없이 손대지 않는다.
      final taxable = data.vendorShares(tax: TaxType.taxable);
      expect(taxable.map((e) => e.name).toList(), ['화람원예', '그린플러스']);

      // 과세만 남겨도 "연간 매입의 30% / 10%" 는 유지된다.
      expect(taxable[0].share, closeTo(0.30, 1e-9));
      expect(taxable[1].share, closeTo(0.10, 1e-9));

      final exempt = data.vendorShares(tax: TaxType.exempt);
      expect(exempt.map((e) => e.name).toList(), ['대한꽃도매']);
      expect(exempt.single.share, closeTo(0.60, 1e-9));
    });

    test('🔴 분모가 0 이면 NaN 이 아니라 0 이다', () {
      // 금액 0원 영수증만 있는 상태. 예전 구현이라면 0/0 = NaN 이 되고
      // 그 NaN 이 바 너비로 들어가 렌더링이 터졌다.
      final data = SettleLiveData.build(
        [_r('z', '대한꽃도매', d(7, 1), 0)],
        year: '$y',
      );
      expect(data.yearTotal, 0);

      final s = data.vendorShares().single;
      expect(s.share.isNaN, isFalse);
      expect(s.share, 0);
      expect(s.shareLabel, '전체 매입의 0%');
    });

    test('🔴 금액이 있는데 0% 로 반올림되면 `1% 미만` 으로 적는다', () {
      // 999,900 : 100 → 0.01%
      final data = SettleLiveData.build([
        _r('big', '대한꽃도매', d(7, 1), 999900),
        _r('tiny', '화람원예', d(7, 2), 100),
      ], year: '$y');

      final tiny = data.vendorShares().firstWhere((s) => s.name == '화람원예');
      expect(tiny.total, 100);
      expect((tiny.share * 100).round(), 0); // 반올림하면 0%
      expect(tiny.shareLabel, '전체 매입의 1% 미만'); // 그래도 0% 라고 쓰지 않는다
    });

    test('정렬 옵션이 실제로 동작한다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      expect(data.vendorShares(sortBy: 'amountDesc').first.name, '대한꽃도매');
      expect(data.vendorShares(sortBy: 'amountAsc').first.name, '그린플러스');
      expect(data.vendorShares(sortBy: 'name').map((e) => e.name).toList(),
          ['그린플러스', '대한꽃도매', '화람원예']);
    });

    test('영수증은 최신순이고 최근 날짜 표기가 맞다', () {
      final data = SettleLiveData.build(sample(), year: '$y');
      final v = data.vendorShares().firstWhere((s) => s.name == '대한꽃도매');

      expect(v.count, 3);
      expect(v.receipts.map((r) => r.id).toList(), ['1', '2', '3']);
      expect(v.lastDateLabel, '07.24');
    });
  });

  group('SettleLiveData — 날짜별 보기', () {
    test('같은 날 영수증을 묶고 최신 날짜가 먼저 온다', () {
      final data = SettleLiveData.build(sample(), year: '$y');
      final groups = data.dayGroups();

      // 07.24(2건) · 07.22 · 07.20 · 07.08
      expect(groups.length, 4);
      expect(groups.first.date, DateTime(y, 7, 24));
      expect(groups.first.count, 2);
      expect(groups.first.total, 356000); // 256000 + 100000
      expect(groups.last.date, DateTime(y, 7, 8));
    });

    test('날짜 라벨이 로케일 초기화 없이 나온다', () {
      // `DateFormat('E','ko')` 는 initializeDateFormatting 이 없으면 던진다.
      // 그래서 직접 표를 갖고 있는데, 그 표가 맞는지 확인한다.
      final data = SettleLiveData.build(sample(), year: '$y');
      final g = data.dayGroups().first; // 2026-07-24
      expect(g.monthLabel, '7월');
      expect(g.dayLabel, '24');
      expect(g.weekdayLabel, '금'); // 2026-07-24 는 금요일
    });

    test('한 날짜 안에서는 금액 큰 순이다', () {
      final data = SettleLiveData.build(sample(), year: '$y');
      final g = data.dayGroups().first;
      expect(g.receipts.first.storeName, '대한꽃도매'); // 256000
      expect(g.receipts.last.storeName, '그린플러스'); // 100000
    });
  });

  group('🔴 두 보기가 같은 조건을 같게 해석한다', () {
    // 한쪽에만 필터가 먹으면 "업체별 3곳인데 날짜별 5곳" 같은 모순이 난다.
    void sameSet({String? query, TaxType? tax, bool Function(String)? where}) {
      final data = SettleLiveData.build(sample(), year: '$y');

      final fromDays = data
          .dayGroups(query: query, tax: tax, vendorWhere: where)
          .expand((g) => g.receipts)
          .map((r) => r.id)
          .toSet();
      final fromVendors = data
          .vendorShares(query: query, tax: tax, vendorWhere: where)
          .expand((s) => s.receipts)
          .map((r) => r.id)
          .toSet();

      expect(fromDays, fromVendors);
    }

    test('필터 없음', () => sameSet());
    test('검색어', () => sameSet(query: '대한'));
    test('과세', () => sameSet(tax: TaxType.taxable));
    test('면세', () => sameSet(tax: TaxType.exempt));
    test('전송 상태(거래처 조건)',
        () => sameSet(where: (v) => v == '대한꽃도매'));
    test('검색어 + 면세', () => sameSet(query: '꽃', tax: TaxType.exempt));
  });

  group('receiptItemSummary — 품목 한 줄 요약', () {
    test('색이 있으면 괄호로 붙인다', () {
      final r = _r('a', 'x', d(7, 1), 1000, items: [
        (name: '장미', color: '레드'),
        (name: '거베라', color: null),
        (name: '수국', color: null),
      ]);
      expect(receiptItemSummary(r), '장미(레드) · 거베라 · 수국');
    });

    test('많으면 `외 N건` 으로 줄인다', () {
      final r = _r('a', 'x', d(7, 1), 1000, items: [
        (name: '장미', color: '레드'),
        (name: '거베라', color: null),
        (name: '수국', color: null),
        (name: '안개', color: null),
        (name: '카네이션', color: null),
      ]);
      expect(receiptItemSummary(r), '장미(레드) · 거베라 · 수국 외 2건');
      // 업체별 행은 한 개만 보여준다: `장미(레드) 외 4건`
      expect(receiptShortSummary(r), '장미(레드) 외 4건');
    });

    test('중복 품목명은 한 번만 센다', () {
      final r = _r('a', 'x', d(7, 1), 1000, items: [
        (name: '장미', color: '레드'),
        (name: '장미', color: '레드'),
        (name: '수국', color: null),
      ]);
      expect(receiptItemSummary(r), '장미(레드) · 수국');
    });

    test('품목이 없으면 없다고 적는다 (빈 문자열을 내보내지 않는다)', () {
      final r = _r('a', 'x', d(7, 1), 1000);
      expect(receiptItemSummary(r), '품목 정보 없음');
    });
  });

  group('거래처명이 비어 있는 영수증', () {
    test('두 보기 모두 같은 키(`거래처 미확인`)로 묶는다', () {
      // OCR 이 상호를 못 읽는 일은 실제로 있다. 그때 영수증이 사라지거나
      // 두 보기에서 다르게 묶이면 안 된다.
      final data = SettleLiveData.build([
        _r('1', '', d(7, 1), 5000),
        _r('2', '   ', d(7, 2), 5000),
      ], year: '$y');

      final shares = data.vendorShares();
      expect(shares.length, 1);
      expect(shares.single.name, '거래처 미확인');
      expect(shares.single.count, 2);
      expect(shares.single.share, closeTo(1.0, 1e-9));

      expect(data.dayGroups().length, 2);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  요청 #98 — 시안과 완전히 동일하게
  // ══════════════════════════════════════════════════════════════
  //
  // 사용자 요청: "내가 준 이미지랑 완전히 동일하게 해야해. 이제 프로 어쩌고
  // 이런거는 다 빼기로 했잖아. 그걸 빼고 (...) 거기에 맞게 기능을 넣으라는 말이야."
  //
  // 시안 숫자를 직접 검산해서 나온 규칙을 고정한다.
  group('🔴 #98 시안 산술 — 헤더 금액이 곧 점유율의 분모다', () {
    // 시안 이미지의 실제 숫자를 그대로 쓴다.
    //   헤더 `2026년 7월 총 매입` = ₩1,184,000
    //   그린플러스 ₩123,000 → `전체 매입의 10%`
    //   미림화훼  ₩107,000 → `전체 매입의  9%`
    //   화람원예  ₩352,000 → `전체 매입의 30%`
    // 나머지 ₩602,000 은 대한꽃도매(시안 2번 이미지, 펼친 카드).
    List<ReceiptModel> mockup() => [
          _r('a1', '대한꽃도매', d(7, 24), 256000),
          _r('a2', '대한꽃도매', d(7, 20), 132000),
          _r('a3', '대한꽃도매', d(7, 8), 214000),
          _r('b1', '그린플러스', d(7, 24), 123000),
          _r('c1', '미림화훼', d(7, 17), 107000),
          _r('d1', '화람원예', d(7, 22), 352000),
          // 6월 영수증 — 7월을 고르면 분모에서 빠져야 한다.
          _r('e1', '대한꽃도매', d(6, 30), 500000),
        ];

    test('시안의 10% / 9% / 30% 가 그대로 재현된다', () {
      final data = SettleLiveData.build(mockup(), year: '$y');

      // 헤더에 찍히는 금액
      expect(data.periodTotal('7월'), 1184000);
      expect(data.periodCount('7월'), 6);

      final shares = data.vendorShares(monthFilter: '7월');
      final map = {for (final s in shares) s.name: s};

      expect(map['그린플러스']!.shareLabel, '전체 매입의 10%');
      expect(map['미림화훼']!.shareLabel, '전체 매입의 9%');
      expect(map['화람원예']!.shareLabel, '전체 매입의 30%');
      expect(map['대한꽃도매']!.total, 602000);
    });

    test('🔴 헤더 금액 === 점유율 분모 (모든 월에서)', () {
      final data = SettleLiveData.build(mockup(), year: '$y');

      for (final m in const ['전체', '6월', '7월', '8월']) {
        final denom = data.periodTotal(m);
        final shares = data.vendorShares(monthFilter: m);
        if (shares.isEmpty) {
          // 해당 월에 자료가 없으면 헤더도 0 이어야 한다.
          expect(denom, 0, reason: '$m: 목록은 비었는데 헤더 금액이 남아 있다');
          continue;
        }
        final sum = shares.fold<double>(0, (s, e) => s + e.total);
        expect(sum, denom, reason: '$m: 카드 합계와 헤더 금액이 다르다');

        // 퍼센트 합도 100% 여야 한다 (필터가 없을 때).
        final pct = shares.fold<double>(0, (s, e) => s + e.share);
        expect(pct, closeTo(1.0, 1e-9), reason: '$m: 점유율 합이 100% 가 아니다');
      }
    });

    test('🔴 월을 골라도 검색·과세 필터는 % 를 흔들지 않는다', () {
      final data = SettleLiveData.build(mockup(), year: '$y');

      final plain = data.vendorShares(monthFilter: '7월');
      final searched = data.vendorShares(monthFilter: '7월', query: '그린');

      final a = plain.firstWhere((s) => s.name == '그린플러스');
      final b = searched.single;
      expect(b.name, '그린플러스');
      expect(b.share, a.share);
      expect(b.shareLabel, '전체 매입의 10%');
    });

    test('날짜별 보기도 같은 월 범위를 본다', () {
      final data = SettleLiveData.build(mockup(), year: '$y');

      final ids = <String>{};
      for (final g in data.dayGroups(monthFilter: '7월')) {
        for (final r in g.receipts) {
          ids.add(r.id);
          expect(r.date.month, 7);
        }
      }
      expect(ids.length, 6);
      expect(ids.contains('e1'), isFalse); // 6월 영수증은 빠진다

      // 업체별과 같은 집합이어야 한다.
      final vIds = <String>{};
      for (final s in data.vendorShares(monthFilter: '7월')) {
        vIds.addAll(s.receipts.map((r) => r.id));
      }
      expect(vIds, ids);
    });

    test('`전체` 는 연도 전체를 뜻한다 (기본 칩 `2026년 전체`)', () {
      final data = SettleLiveData.build(mockup(), year: '$y');
      expect(data.periodTotal('전체'), data.yearTotal);
      expect(data.periodCount('전체'), data.receiptCount);
      expect(SettleLiveData.monthNumberOf('전체'), isNull);
      expect(SettleLiveData.monthNumberOf('7월'), 7);
      expect(SettleLiveData.monthNumberOf('12월'), 12);
    });

    test('🔴 자료가 없는 월을 골라도 NaN 이 아니다', () {
      final data = SettleLiveData.build(mockup(), year: '$y');
      expect(data.periodTotal('1월'), 0);
      expect(data.periodCount('1월'), 0);
      expect(data.vendorShares(monthFilter: '1월'), isEmpty);
      expect(data.dayGroups(monthFilter: '1월'), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  🔴 #100 회귀 — 날짜별에 최근 하루만 나오던 버그
  // ══════════════════════════════════════════════════════════════
  //
  // 원인: `_DayBlock` 이 `Row(crossAxisAlignment: stretch)` + 기둥의
  //       `Expanded(세로선)` 조합인데, 이 Row 가 `SingleChildScrollView`
  //       (높이 무한) 안에 있어 `h=Infinity` 가 기둥에 전달되어
  //       레이아웃이 실패했다. debug 는 assert 로 잡지만 **release 는
  //       assert 가 삭제되어 조용히 깨지고 첫 날짜만 남았다.**
  //       → `IntrinsicHeight` 로 감싸 실제 하루 높이를 주도록 고쳤다.
  //
  // 이 테스트는 **데이터층이 아니라 렌더 결과**를 본다. 데이터층은
  // 처음부터 4일을 정확히 돌려주고 있었기 때문에, 데이터 테스트만으로는
  // 이 버그를 절대 잡을 수 없었다.
  group('🔴 #100 날짜별 렌더 — 모든 날짜가 그려진다', () {
    testWidgets('스크롤 뷰 안에서 4일이 전부 보인다 (h=Infinity 회귀)', (t) async {
      final data = SettleLiveData.build([
        _r('대한꽃도매-724', '대한꽃도매', DateTime(2026, 7, 24), 602000),
        _r('화람원예-722', '화람원예', DateTime(2026, 7, 22), 352000),
        _r('그린플러스-718', '그린플러스', DateTime(2026, 7, 18), 123000),
        _r('미림화훼-79', '미림화훼', DateTime(2026, 7, 9), 107000),
      ], year: '2026');

      final groups = data.dayGroups();
      expect(groups.length, 4, reason: '데이터층은 원래도 4일을 준다');

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [SettleDayTimeline(groups: groups)],
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();

      // 🔴 렌더 예외가 하나라도 나면 실패시킨다. 이 버그의 본질이
      //    "예외가 조용히 삼켜지는 것"이었기 때문이다.
      expect(t.takeException(), isNull,
          reason: '레이아웃 예외가 나면 release 에서 조용히 깨진다');

      for (final name in ['대한꽃도매', '화람원예', '그린플러스', '미림화훼']) {
        expect(find.text(name), findsOneWidget, reason: '$name 이 안 보인다');
      }
      // 날짜 기둥도 4개 다 있어야 한다.
      for (final d in ['24', '22', '18', '9']) {
        expect(find.text(d), findsOneWidget, reason: '$d 일 기둥이 없다');
      }
    });

    testWidgets('한 날짜에 여러 건이 있어도 전부 보인다', (t) async {
      final data = SettleLiveData.build([
        _r('대한꽃도매-724', '대한꽃도매', DateTime(2026, 7, 24), 602000),
        _r('화람원예-724', '화람원예', DateTime(2026, 7, 24), 352000),
        _r('그린플러스-720', '그린플러스', DateTime(2026, 7, 20), 123000),
      ], year: '2026');

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettleDayTimeline(groups: data.dayGroups()),
          ),
        ),
      ));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.text('대한꽃도매'), findsOneWidget);
      expect(find.text('화람원예'), findsOneWidget);
      expect(find.text('그린플러스'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════
  //  🔴 #100 캘린더와 같은 원본을 본다
  // ══════════════════════════════════════════════════════════════
  //
  // 캘린더(`calendar_ds_screen.dart:99`)도 `ReceiptProvider.allReceipts`
  // 를 읽고, 구매 내역도 같은 목록을 `SettleLiveData.build` 에 넣는다.
  // 저장소가 갈라져 있지 않다는 걸 못박아 둔다.
  test('🔴 캘린더가 세는 하루 합계 == 날짜별이 세는 하루 합계', () {
    final all = [
      _r('대한꽃도매-724', '대한꽃도매', DateTime(2026, 7, 24), 602000),
      _r('화람원예-724', '화람원예', DateTime(2026, 7, 24), 352000),
      _r('그린플러스-720', '그린플러스', DateTime(2026, 7, 20), 123000),
    ];

    // 캘린더 방식: 연·월 일치하는 것만 일자별로 모은다.
    final calByDay = <int, double>{};
    for (final r in all) {
      if (r.date.year != 2026 || r.date.month != 7) continue;
      calByDay[r.date.day] = (calByDay[r.date.day] ?? 0) + r.totalAmount;
    }

    // 날짜별 방식
    final groups = SettleLiveData.build(all, year: '2026').dayGroups();
    final settleByDay = {for (final g in groups) g.date.day: g.total};

    expect(settleByDay, calByDay, reason: '두 화면의 하루 합계가 달라졌다');
    expect(settleByDay[24], 954000);
    expect(settleByDay[20], 123000);
  });

}
