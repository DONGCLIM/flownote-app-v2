// FnDemo.resolve() 가 실데이터를 실제로 반영하는지 검증한다.
//
// 배경: 예전에는 실데이터가 있어도 `taxData` / `priceData` / `insights` 세 항목이
// 시안 고정값(장미(레드) 8000원, 대한꽃도매 42% 등)을 그대로 반환했다.
// 홈 탭 도넛/시세/인사이트 카드가 실제 매입 내역과 무관한 숫자를 보여주던 원인.

import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/fn_data.dart';
import 'package:flow_note/services/insight_service.dart';

/// 특정 달의 영수증 하나
ReceiptModel _r(
  String id,
  String store,
  DateTime date,
  List<({String name, int qty, double price})> items,
) {
  final flowers = items
      .map((e) => FlowerItem(
            name: e.name,
            quantity: e.qty,
            unitPrice: e.price,
            unit: '단',
          ))
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

  group('InsightService — 과세/면세 분리', () {
    test('면세(생화) 매입처와 과세(부자재) 매입처를 금액으로 분리한다', () {
      // '대한꽃도매' = 면세 기본값, '그린플러스' = 과세 기본값
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [(name: '장미', qty: 10, price: 1000)]),
        _r('b', '그린플러스', monthsAgo(0), [(name: '리본', qty: 10, price: 500)]),
      ];

      final b = InsightService.taxBreakdown(receipts);

      expect(b.exempt, 10000, reason: '대한꽃도매 10단 × 1000원 = 면세 10,000원');
      expect(b.taxable, 5000, reason: '그린플러스 10단 × 500원 = 과세 5,000원');
      // 시안 고정값(976000 / 2074000)이 아님을 확인
      expect(b.taxable, isNot(976000));
      expect(b.exempt, isNot(2074000));
    });
  });

  group('FnDemo.resolve — 빈 데이터', () {
    test('영수증이 없으면 isDemo=true 이고 시안 수치를 쓴다', () {
      final d = FnDemo.resolveFrom(const []);

      expect(d.isDemo, isTrue);
      expect(d.taxData, same(FnDemo.demoTaxData));
      expect(d.priceData, same(FnDemo.demoPriceData));
      expect(d.insights, same(FnDemo.demoInsights));
      expect(d.receiptCount, 8, reason: '시안 영수증 매수');
    });
  });

  group('FnDemo.resolve — 실데이터', () {
    test('isDemo=false 이고 taxData 가 실제 금액이다', () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [(name: '장미', qty: 10, price: 1000)]),
        _r('b', '그린플러스', monthsAgo(0), [(name: '리본', qty: 4, price: 500)]),
      ];

      final d = FnDemo.resolveFrom(receipts);

      expect(d.isDemo, isFalse);
      expect(d.taxData, isNot(same(FnDemo.demoTaxData)));

      final total = d.taxData.fold<double>(0, (s, e) => s + e.value);
      expect(total, 12000, reason: '10,000 + 2,000');

      final exempt =
          d.taxData.firstWhere((e) => e.label.contains('면세')).value;
      expect(exempt, 10000);
    });

    test('priceData 가 실제 품목명·실제 단가다', () {
      // 같은 품목을 두 달에 걸쳐, 단가를 올려서 매입
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(1), [(name: '작약', qty: 10, price: 2000)]),
        _r('b', '대한꽃도매', monthsAgo(0), [(name: '작약', qty: 10, price: 2400)]),
      ];

      final d = FnDemo.resolveFrom(receipts);

      expect(d.priceData.keys, contains('작약'));
      // 시안 품목명이 섞여 들어오지 않아야 한다
      expect(d.priceData.keys, isNot(contains('장미(레드)')));
      expect(d.priceData.keys, isNot(contains('거베라')));

      final peony = d.priceData['작약']!;
      expect(peony.unit, 2400, reason: '가장 최근 월평균 단가');
      expect(peony.chg, 20, reason: '2000 → 2400 = +20%');
      expect(peony.locked, isFalse, reason: '첫 품목은 무료 공개');
    });

    test('품목이 여러 개면 첫 품목만 무료, 나머지는 잠긴다', () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [
          (name: '많이산꽃', qty: 100, price: 1000),
          (name: '조금산꽃', qty: 1, price: 1000),
        ]),
      ];

      final d = FnDemo.resolveFrom(receipts);
      final keys = d.priceData.keys.toList();

      expect(keys.first, '많이산꽃', reason: '구매 수량 상위 품목이 먼저');
      expect(d.priceData[keys.first]!.locked, isFalse);
      expect(d.priceData[keys[1]]!.locked, isTrue);
    });

    test('insights 가 실제 거래처명·실제 비중을 담는다', () {
      // 대한꽃도매에 100% 편중 → donut 인사이트가 나와야 한다
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [(name: '장미', qty: 100, price: 1000)]),
      ];

      final d = FnDemo.resolveFrom(receipts);
      final texts = d.insights.map((e) => e.text).toList();

      expect(
        texts.any((t) => t.contains('대한꽃도매') && t.contains('100%')),
        isTrue,
        reason: '실제 비중 100% 가 문구에 들어가야 함. 실제: $texts',
      );
      // 시안의 '42%' 고정 문구가 아님
      expect(texts.any((t) => t.contains('42%')), isFalse);
    });

    test('단가 상승 인사이트에 실제 품목명과 실제 상승률이 들어간다', () {
      final receipts = [
        _r('a', '화훼농장', monthsAgo(1), [(name: '튤립', qty: 10, price: 1000)]),
        _r('b', '화훼농장', monthsAgo(0), [(name: '튤립', qty: 10, price: 1500)]),
      ];

      final d = FnDemo.resolveFrom(receipts);
      final texts = d.insights.map((e) => e.text).toList();

      expect(
        texts.any((t) => t.contains('튤립') && t.contains('+50%')),
        isTrue,
        reason: '1000 → 1500 = +50%. 실제: $texts',
      );
      expect(texts.any((t) => t.contains('장미(레드)')), isFalse,
          reason: '시안 품목명이 남아있으면 안 됨');
    });

    test('거래처별 단가 차이 인사이트가 실제 차이를 계산한다', () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [(name: '수국', qty: 10, price: 2000)]),
        _r('b', '그린플러스', monthsAgo(0), [(name: '수국', qty: 10, price: 2400)]),
      ];

      final d = FnDemo.resolveFrom(receipts);
      final texts = d.insights.map((e) => e.text).toList();

      expect(
        texts.any((t) => t.contains('수국') && t.contains('20%')),
        isTrue,
        reason: '2000 → 2400 = 20% 차이. 실제: $texts',
      );
    });

    test('조건에 맞는 인사이트가 하나도 없으면 시안 문구로 대체된다', () {
      // 한 달·한 품목·한 거래처 → 상승/비교 인사이트 불가.
      // 단, 편중 100% 는 성립하므로 donut 하나는 나온다.
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(0), [(name: '장미', qty: 10, price: 1000)]),
      ];
      final d = FnDemo.resolveFrom(receipts);
      expect(d.insights, isNotEmpty, reason: '빈 리스트를 반환하면 화면이 비어버린다');
    });
  });

  group('회귀 방지 — 시안 상수가 실데이터를 덮어쓰지 않는다', () {
    test('실데이터 존재 시 세 항목 모두 시안 상수와 다른 인스턴스', () {
      final receipts = [
        _r('a', '대한꽃도매', monthsAgo(1), [(name: '작약', qty: 10, price: 2000)]),
        _r('b', '그린플러스', monthsAgo(0), [(name: '작약', qty: 10, price: 2600)]),
      ];

      final d = FnDemo.resolveFrom(receipts);

      expect(d.taxData, isNot(same(FnDemo.demoTaxData)));
      expect(d.priceData, isNot(same(FnDemo.demoPriceData)));
      expect(d.insights, isNot(same(FnDemo.demoInsights)));
    });
  });
}
