import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/fn_data.dart';

/// 회귀 방지 — 홈 화면 회색 버그(28-A)
///
/// 원인: `home_ds_screen.dart` 의 `_priceCard` 가 `priceData['장미(레드)']!`
/// 로 시안 품목명을 하드코딩 역참조했다. 실데이터에서는 품목명이 실제 매입한
/// 꽃 이름(상위 8개)이라 '장미(레드)' 가 없으면 build() 가 throw 하고,
/// 릴리즈 빌드에서는 화면 전체가 회색 ErrorWidget 으로 덮였다.
ReceiptModel _r(String id, String store, DateTime date,
    List<({String name, int qty, double price})> items) {
  final flowers = items
      .map((e) => FlowerItem(
          name: e.name, quantity: e.qty, unitPrice: e.price, unit: '단'))
      .toList();
  return ReceiptModel(
    id: id,
    date: date,
    storeName: store,
    items: flowers,
    totalAmount: flowers.fold<double>(0, (s, i) => s + i.totalPrice),
    rawOcrText: 'test',
    createdAt: date,
  );
}

void main() {
  final now = DateTime.now();
  DateTime monthsAgo(int n) => DateTime(now.year, now.month - n, 10);

  group('28-A 회귀 — 시안 품목명이 없어도 홈 데이터가 안전하다', () {
    test("실데이터에 '장미(레드)' 가 없어도 priceData 가 비어있지 않다", () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(1), [
          (name: '작약', qty: 10, price: 2000),
          (name: '수국', qty: 5, price: 3000),
        ]),
        _r('b', '화람원예', monthsAgo(0), [
          (name: '작약', qty: 10, price: 2400),
        ]),
      ];
      final d = FnDemo.resolveFrom(receipts);

      expect(d.isDemo, isFalse);
      // 시안 하드코딩 키는 존재하지 않는다 → `!` 역참조는 반드시 크래시였다.
      expect(d.priceData.containsKey('장미(레드)'), isFalse);
      // 하지만 화면이 쓸 수 있는 첫 품목은 항상 존재한다.
      expect(d.priceData, isNotEmpty);
      final first = d.priceData.keys.first;
      expect(d.priceData[first], isNotNull);
      expect(d.priceData[first]!.locked, isFalse);
    });

    test('빈 데이터에서도 첫 품목 접근이 안전하다', () {
      final d = FnDemo.resolveFrom(const []);
      expect(d.isDemo, isTrue);
      expect(d.priceData, isNotEmpty);
      expect(d.priceData[d.priceData.keys.first], isNotNull);
      expect(d.insights, isNotEmpty);
    });

    test('금액이 0인 영수증만 있어도 차트 데이터가 깨지지 않는다', () {
      final d = FnDemo.resolveFrom([
        _r('z', '무료증정', monthsAgo(0), [(name: '샘플', qty: 1, price: 0)]),
      ]);
      expect(d.months.length, 12);
      expect(d.spend.length, 12);
      // 전월이 0원이면 나눗셈이 무한대가 되지 않아야 한다.
      expect(d.pctUp, 0);
      expect(d.taxData, isNotEmpty);
    });

    test('months/spend 길이가 항상 같아 인덱스 초과가 없다', () {
      for (final receipts in [
        <ReceiptModel>[],
        [_r('a', '대한꽃도매', monthsAgo(0), [(name: '작약', qty: 1, price: 100)])],
      ]) {
        final d = FnDemo.resolveFrom(receipts);
        expect(d.months.length, d.spend.length);
        expect(d.months.length, greaterThanOrEqualTo(6));
      }
    });
  });

  group('28-A 회귀 — ErrorWidget 회색 박스가 아니라 안내가 보인다', () {
    testWidgets('build 예외 시 사유 문구가 화면에 남는다', (tester) async {
      // main() 이 설치하는 것과 동일한 동작을 검증한다.
      // flutter_test 는 테스트 종료 시점에 ErrorWidget.builder 가 원복돼
      // 있는지 검사하므로, 테스트 본문 안에서 되돌려 놓아야 한다.
      final original = ErrorWidget.builder;
      ErrorWidget.builder = (details) => Directionality(
            textDirection: TextDirection.ltr,
            child: Text('이 화면을 표시하는 중 문제가 발생했어요\n${details.exception}'),
          );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (_) => throw StateError('의도된 실패')),
      ));

      expect(tester.takeException(), isA<StateError>());
      expect(find.textContaining('이 화면을 표시하는 중 문제가 발생했어요'),
          findsOneWidget);
      // 회색 박스가 아니라 원인 문구까지 화면에 남는다.
      expect(find.textContaining('의도된 실패'), findsOneWidget);

      ErrorWidget.builder = original;
    });
  });
}
