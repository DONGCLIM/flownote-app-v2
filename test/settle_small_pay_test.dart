// 요청 #115 회귀 — 구매 내역의 `종합소득세용(5월)` 칩.
//
// 사용자 요청: "이거는 3만원 미만인 영수증건에 대해서만 정렬하게 해놓은거야.
//              그거로 볼 수 있게 해주는데"
//
// 🔴 고치기 전의 실제 동작(=이 테스트가 막으려는 회귀):
//    칩은 **거래처 단위**로 걸러졌다. "3만원 이하 건이 하나라도 있는 거래처"
//    를 남긴 다음, 그 거래처의 **모든** 영수증을 그대로 보여줬다. 그래서
//    헤더 총액 · 건수 · 점유율 분모 · 날짜별 목록 · 카드 안 거래 목록에
//    3만원을 넘는 건이 전부 섞여 있었다.
//
// 이 테스트가 지키려는 것:
//
//  1. 3만원 이하 영수증**만** 남는다 — 날짜별과 업체별 양쪽 모두.
//  2. 헤더 금액/건수도 같은 기준으로 줄어든다. 한 곳만 고치면
//     "헤더는 100만원인데 목록 합은 5만원" 이 되고, 그러면 숫자를 못 믿는다.
//  3. 점유율 분모(`denom`)도 같이 줄어들어, 보이는 카드들의 % 합이 100% 다.
//  4. 칩을 끄면 원래 전체 금액으로 정확히 되돌아온다.
//  5. `3만원 이하 결제` 하위 블록이 본 목록과 중복되어 두 번 그려지지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/settle_data_live.dart';
import 'package:flow_note/screens/ds/settle_views_ds.dart';

ReceiptModel _r(String id, String store, DateTime date, double amount) {
  return ReceiptModel(
    id: id,
    date: date,
    storeName: store,
    items: [
      FlowerItem(
        name: '장미',
        quantity: 1,
        unitPrice: amount,
        unit: '단',
      ),
    ],
    totalAmount: amount,
    rawOcrText: 'test',
    createdAt: date,
  );
}

void main() {
  const y = 2026;
  DateTime d(int m, int day) => DateTime(y, m, day);

  // 🔴 구성이 중요하다. `대한꽃도매` 는 큰 건과 작은 건을 **같이** 갖고
  //    있다. 예전 구현은 이 거래처를 통째로 통과시켜서 256,000원까지
  //    보여줬다. `그린플러스` 는 작은 건만, `화람원예` 는 큰 건만 갖는다.
  List<ReceiptModel> sample() => [
        _r('1', '대한꽃도매', d(7, 24), 256000), // 초과
        _r('2', '대한꽃도매', d(7, 20), 28000), // 이하
        _r('3', '대한꽃도매', d(7, 8), 12000), // 이하
        _r('4', '그린플러스', d(7, 24), 30000), // 경계값 — 포함
        _r('5', '그린플러스', d(6, 2), 9000), // 이하 (다른 달)
        _r('6', '화람원예', d(7, 22), 300000), // 초과
      ];

  // 3만원 이하 영수증만: 28000 + 12000 + 30000 + 9000 = 79000 (4건)
  const smallTotal = 79000.0;
  const smallCount = 4;

  // 요청 #115의 조건 그대로. 화면(`settle_ds_screen._receiptWhere`)과
  // 같은 식이어야 한다.
  bool small(ReceiptModel r) =>
      r.totalAmount > 0 && r.totalAmount <= kSmallPayLimit;

  group('#115 종합소득세용(5월) — 3만원 이하 영수증만', () {
    test('한계값은 30,000원이고 30,000원 자체는 포함된다', () {
      // 사용자는 "3만원 미만" 이라고 말했지만 기존 구현/시안이 모두
      // `<= 30000` 이었다. 경계 처리를 조용히 바꾸지 않고 여기에 고정한다.
      expect(kSmallPayLimit, 30000);
      expect(small(_r('x', 'a', d(1, 1), 30000)), isTrue);
      expect(small(_r('x', 'a', d(1, 1), 30001)), isFalse);
      // 0원 영수증(스캔 실패 등)은 제외한다 — 신고에 쓸 값이 없다.
      expect(small(_r('x', 'a', d(1, 1), 0)), isFalse);
    });

    test('🔴 헤더 금액·건수가 3만원 이하 합계로 줄어든다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      // 필터 없음 = 연간 전체
      expect(data.periodTotal('전체'), 635000);
      expect(data.periodCount('전체'), 6);

      // 칩 켜짐
      expect(data.periodTotal('전체', receiptWhere: small), smallTotal);
      expect(data.periodCount('전체', receiptWhere: small), smallCount);
    });

    test('월 필터와 함께 걸려도 두 조건이 모두 적용된다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      // 7월 3만원 이하: 28000 + 12000 + 30000 = 70000 (3건)
      expect(data.periodTotal('7월', receiptWhere: small), 70000);
      expect(data.periodCount('7월', receiptWhere: small), 3);

      // 6월 3만원 이하: 9000 (1건)
      expect(data.periodTotal('6월', receiptWhere: small), 9000);
      expect(data.periodCount('6월', receiptWhere: small), 1);
    });

    test('🔴 업체별 — 카드 금액에 3만원 초과 건이 섞이지 않는다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      final shares = data.vendorShares(receiptWhere: small);
      final map = {for (final s in shares) s.name: s};

      // 큰 건만 있던 거래처는 아예 사라진다.
      expect(map.containsKey('화람원예'), isFalse);

      // 예전 구현이라면 600,000원(= 256000+28000+12000)이 찍혔다.
      expect(map['대한꽃도매']!.total, 40000);
      expect(map['그린플러스']!.total, 39000);

      // 카드 안 거래 목록에도 초과 건이 남아 있지 않다.
      for (final s in shares) {
        for (final r in s.receipts) {
          expect(r.totalAmount, lessThanOrEqualTo(kSmallPayLimit),
              reason: '${s.name} / ${r.id} 이 3만원을 넘는다');
        }
      }
    });

    test('🔴 업체별 — 점유율 분모도 같이 줄어들어 합이 100% 다', () {
      // 분모가 연간 전체(635,000)로 남아 있으면 보이는 카드 % 합이
      // 12% 밖에 안 되어, 화면상 막대가 전부 붙어버린다.
      final data = SettleLiveData.build(sample(), year: '$y');

      final shares = data.vendorShares(receiptWhere: small);
      final sum = shares.fold<double>(0, (s, e) => s + e.share);
      expect(sum, closeTo(1.0, 1e-9));

      final map = {for (final s in shares) s.name: s};
      expect(map['대한꽃도매']!.share, closeTo(40000 / smallTotal, 1e-9));
      expect(map['그린플러스']!.share, closeTo(39000 / smallTotal, 1e-9));
    });

    test('🔴 날짜별 — 3만원 초과 건이 나오지 않고, 합이 헤더와 같다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      final groups = data.dayGroups(receiptWhere: small, monthFilter: '전체');

      var total = 0.0;
      var count = 0;
      for (final g in groups) {
        for (final r in g.receipts) {
          expect(r.totalAmount, lessThanOrEqualTo(kSmallPayLimit),
              reason: '${r.id} 이 3만원을 넘는다');
          total += r.totalAmount;
          count++;
        }
      }

      // 4번(그린플러스 30,000)과 1번(대한꽃도매 256,000)이 같은 날짜라서,
      // 날짜 단위로만 걸렀다면 초과 건이 같이 따라왔을 것이다.
      expect(count, smallCount);
      expect(total, smallTotal);
      expect(total, data.periodTotal('전체', receiptWhere: small));
    });

    test('칩을 끄면(receiptWhere: null) 전체 금액으로 정확히 돌아온다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      expect(data.periodTotal('전체', receiptWhere: null), 635000);
      expect(data.periodCount('전체', receiptWhere: null), 6);

      final shares = data.vendorShares(receiptWhere: null);
      final map = {for (final s in shares) s.name: s};
      expect(map['대한꽃도매']!.total, 296000);
      expect(map['화람원예']!.total, 300000);
      expect(map['그린플러스']!.total, 39000);
    });

    test('전송 상태 등 거래처 조건과 함께 걸어도 둘 다 적용된다', () {
      final data = SettleLiveData.build(sample(), year: '$y');

      final shares = data.vendorShares(
        vendorWhere: (v) => v == '그린플러스',
        receiptWhere: small,
      );
      expect(shares.map((e) => e.name).toList(), ['그린플러스']);
      expect(shares.single.total, 39000);
    });
  });

  group('#115 렌더 — 헤더 문구와 소액 블록 중복', () {
    testWidgets('헤더 라벨이 무엇을 더한 값인지 밝힌다', (tester) async {
      // 소액만 보는데 그냥 `총 매입` 이라고 쓰면 그 금액을 전체 매입으로
      // 오해한다. 화면의 `_headerLabel` 과 같은 문구를 고정한다.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SettleTotalHeader(
            label: '2026년 3만원 이하 매입',
            total: smallTotal,
            count: smallCount,
          ),
        ),
      ));
      expect(find.text('2026년 3만원 이하 매입'), findsOneWidget);
    });

    testWidgets('🔴 상위에서 이미 걸러졌으면 `3만원 이하 결제` 블록을 또 그리지 않는다',
        (tester) async {
      final data = SettleLiveData.build(sample(), year: '$y');
      final shares = data.vendorShares(receiptWhere: small);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettleVendorShareList(
              shares: shares,
              expandedName: '대한꽃도매', // 펼친 상태
              onToggle: (_) {},
              onExport: (_) {},
              exportedAt: const {},
              smallOnly: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 카드 안 목록이 이미 3만원 이하만이므로 하위 블록은 중복이다.
      expect(find.text('3만원 이하 결제'), findsNothing);
    });

    testWidgets('상위 필터가 없을 때는 소액 블록이 그대로 보인다', (tester) async {
      final data = SettleLiveData.build(sample(), year: '$y');
      // 필터 없이 = 대한꽃도매가 큰 건 + 작은 건을 함께 가진 상태
      final shares = data.vendorShares();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettleVendorShareList(
              shares: shares,
              expandedName: '대한꽃도매',
              onToggle: (_) {},
              onExport: (_) {},
              exportedAt: const {},
              smallOnly: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3만원 이하 결제'), findsOneWidget);
    });
  });
}
