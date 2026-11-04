import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/services/cost_calc.dart';

String _read(String p) => File(p).readAsStringSync();

/// 영수증 몇 장. 자동완성·최근 단가를 확인하는 데 쓴다.
List<ReceiptModel> _receipts() => [
      ReceiptModel(
        id: 'r2',
        date: DateTime(2026, 7, 20),
        storeName: '양재',
        rawOcrText: '',
        createdAt: DateTime(2026, 7, 20),
        totalAmount: 80000,
        items: [
          // 같은 품목이 두 번 나온다. **최근(7/20)** 값이 이겨야 한다.
          FlowerItem(name: '장미(레드)', quantity: 10, unitPrice: 8000, unit: '단'),
        ],
      ),
      ReceiptModel(
        id: 'r1',
        date: DateTime(2026, 5, 2),
        storeName: '양재',
        rawOcrText: '',
        createdAt: DateTime(2026, 5, 2),
        totalAmount: 36000,
        items: [
          FlowerItem(name: '장미(레드)', quantity: 10, unitPrice: 7000, unit: '단'),
          FlowerItem(name: '거베라', quantity: 5, unitPrice: 6000, unit: '속'),
        ],
      ),
    ];

void main() {
  Future<void> pumpAt(WidgetTester t, Widget w, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: w,
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  /// 실제 폰 크기.
  Future<void> pump(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 844));

  /// 🔴 이 화면은 `ListView` 라 화면 밖 카드는 아예 그려지지 않는다.
  ///    아래쪽 카드까지 한 번에 보려면 화면을 길게 잡아야 한다.
  Future<void> pumpTall(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 4000));

  /// 라벨이 붙은 입력칸을 집는다. 같은 라벨이 여러 개면 [at] 번째.
  Finder fieldBy(String label, {int at = 0}) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .at(0),
        matching: find.byType(TextField),
      );

  group('원가 계산기 — 셈', () {
    test('🔴 로스는 꽃에만 매긴다', () {
      final r = CostCalc.run(
        flowers: [const CostLine(name: '장미', qty: 10, unitPrice: 8000)],
        supplies: [const CostLine(name: '포장지', qty: 2, unitPrice: 500)],
        lossRate: 10,
        labor: 0,
        multiplier: 2,
      );
      expect(r.flower, 80000);
      expect(r.supplies, 1000);
      // 로스 = 꽃 80,000 × 10% = 8,000. 부자재 1,000 은 안 섞인다.
      expect(r.loss, 8000);
      expect(r.totalCost, 89000);
    });

    test('🔴 판매가는 1,000원 단위로 올린다 (반올림이 아니다)', () {
      expect(CostCalc.roundUpPrice(122880 * 2.5), 307000 + 1000);
      expect(CostCalc.roundUpPrice(10001), 11000);
      expect(CostCalc.roundUpPrice(11000), 11000);
      expect(CostCalc.roundUpPrice(0), 0);
    });

    test('마진율과 대당 이익이 판매가 기준이다', () {
      final r = CostCalc.run(
        flowers: [const CostLine(name: '꽃', qty: 1, unitPrice: 50000)],
        supplies: const [],
        lossRate: 0,
        labor: 0,
        multiplier: 2,
      );
      expect(r.totalCost, 50000);
      expect(r.price, 100000);
      expect(r.marginAmount, 50000);
      expect(r.marginRate, 0.5);
    });

    test('🔴 아무것도 안 적으면 0 으로 두고 터지지 않는다', () {
      final r = CostCalc.run(
        flowers: const [],
        supplies: const [],
        lossRate: 8,
        labor: 0,
        multiplier: 2.5,
      );
      expect(r.totalCost, 0);
      expect(r.price, 0);
      // 0 나누기를 하면 NaN 이 화면에 찍힌다. 0 으로 막아야 한다.
      expect(r.marginRate, 0);
      expect(CostCalc.pct(r.marginRate), '0%');
    });

    test('배수 다섯 가지가 사장님 지정대로다', () {
      expect(CostCalc.multipliers, [2, 2.5, 3, 3.5, 4]);
      expect(CostCalc.multiplierLabel(2), '×2');
      expect(CostCalc.multiplierLabel(2.5), '×2.5');
      expect(CostCalc.multiplierLabel(4), '×4');
    });
  });

  group('원가 계산기 — 영수증 단가 장부', () {
    test('🔴 같은 품목이면 가장 최근 영수증 단가를 쓴다', () {
      final book = PriceBook.fromReceipts(_receipts());
      final rose = book.lookup('장미(레드)')!;
      // 5/2 의 7,000 이 아니라 7/20 의 8,000 이어야 한다.
      expect(rose.unitPrice, 8000);
      expect(rose.unit, '단');
    });

    test('영수증에 적힌 단위를 그대로 쓴다', () {
      final book = PriceBook.fromReceipts(_receipts());
      expect(book.lookup('거베라')!.unit, '속');
      expect(book.lookup('거베라')!.label, '6,000원 · 1속 기준');
    });

    test('자동완성은 적은 글자가 들어간 품목만 준다', () {
      final book = PriceBook.fromReceipts(_receipts());
      expect(book.suggest('장미').map((e) => e.name), ['장미(레드)']);
      expect(book.suggest('거베').map((e) => e.name), ['거베라']);
      expect(book.suggest('튤립'), isEmpty);
      expect(book.suggest(''), isEmpty);
    });

    test('영수증이 없으면 빈 장부다', () {
      expect(PriceBook.fromReceipts(const []).isEmpty, isTrue);
      expect(PriceBook.empty.lookup('장미'), isNull);
    });
  });

  group('원가 계산기 — 화면', () {
    testWidgets('제목과 안내문이 시안대로다', (t) async {
      await pump(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      expect(find.text('원가 계산기'), findsOneWidget);
      expect(
        find.text('최근 영수증의 매입 단가에\n'
            '로스율과 직접비를 더해 판매가와 마진율을 계산해요.'),
        findsOneWidget,
      );
    });

    testWidgets('상품 구성 칩 다섯 개가 사장님 지정대로다', (t) async {
      await pump(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      // 🔴 칩 줄은 가로 ListView 라 화면을 넘어가는 칩은 그려지지 않는다.
      for (final s in ['꽃다발', '꽃바구니', '화병꽂이']) {
        expect(find.text(s), findsOneWidget, reason: '$s 칩이 없다');
      }
      await t.drag(find.text('꽃다발'), const Offset(-220, 0));
      await t.pump(const Duration(milliseconds: 200));
      for (final s in ['플라워박스', '직접입력']) {
        expect(find.text(s), findsOneWidget, reason: '$s 칩이 없다');
      }
    });

    testWidgets('꽃·부자재 카드가 따로 있고 빈 안내가 보인다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      expect(find.text('꽃'), findsWidgets);
      expect(find.text('부자재'), findsWidgets);
      expect(find.text('꽃을 한 가지 이상 입력해 주세요.'), findsOneWidget);
      expect(find.text('부자재(포장지·리본 등)도 입력해 주세요.'), findsOneWidget);
      // 카드마다 '항목 추가' 가 하나씩.
      expect(find.text('항목 추가'), findsNWidgets(2));
      expect(find.text('0개 품목 · 0원'), findsNWidgets(2));
    });

    testWidgets('작업비·로스율·판매 배수 다섯 개가 보인다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      expect(find.text('작업비 · 부대비용'), findsOneWidget);
      expect(find.text('로스율'), findsOneWidget);
      expect(find.text('로스율은 꽃에만 매겨요.'), findsOneWidget);
      expect(find.text('판매 배수'), findsOneWidget);
      for (final s in ['×2', '×2.5', '×3']) {
        expect(find.text(s), findsWidgets, reason: '$s 배수가 없다');
      }
    });

    testWidgets('원가 구성·권장 판매가·가격대 제안 카드가 있다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      for (final s in [
        '원가 구성', '총 원가',
        '권장 판매가', '마진율', '대당 이익',
        '가격대 제안',
      ]) {
        expect(find.text(s), findsWidgets, reason: '$s 가 없다');
      }
      expect(find.textContaining('1,000원 단위 올림'), findsOneWidget);
    });
  });

  group('원가 계산기 — 적으면 바로 다시 센다', () {
    testWidgets('🔴 꽃 수량·단가를 적으면 합계와 판매가가 따라 바뀐다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));

      // 처음에는 전부 0 이다.
      expect(find.text('0개 품목 · 0원'), findsNWidgets(2));

      final qty = find.byType(TextField).at(1);   // 꽃 카드 첫 줄 수량
      final price = find.byType(TextField).at(2); // 꽃 카드 첫 줄 단가
      await t.enterText(qty, '10');
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(price, '8000');
      await t.pump(const Duration(milliseconds: 200));

      // 꽃 80,000 · 로스 8% = 6,400 · 작업비 3,000 → 총 89,400
      expect(find.text('1개 품목 · 80,000원'), findsOneWidget);
      expect(find.text('89,400원'), findsWidgets);
      // 89,400 × 2.5 = 223,500 → 1,000원 올림 = 224,000
      expect(find.text('224,000원'), findsWidgets);
    });

    testWidgets('🔴 로스율을 바꾸면 총 원가가 따라 바뀐다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      await t.enterText(find.byType(TextField).at(1), '10');
      await t.enterText(find.byType(TextField).at(2), '10000');
      await t.pump(const Duration(milliseconds: 200));

      // 꽃 100,000 · 로스 8% = 8,000 · 작업비 3,000 → 111,000
      expect(find.text('111,000원'), findsWidgets);

      await t.enterText(fieldBy('로스율'), '0');
      await t.pump(const Duration(milliseconds: 200));
      // 로스가 0 이 되면 103,000
      expect(find.text('103,000원'), findsWidgets);
    });

    testWidgets('🔴 판매 배수를 바꾸면 권장 판매가가 따라 바뀐다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      await t.enterText(find.byType(TextField).at(1), '1');
      await t.enterText(find.byType(TextField).at(2), '100000');
      await t.enterText(fieldBy('로스율'), '0');
      await t.enterText(fieldBy('작업비 · 부대비용'), '0');
      await t.pump(const Duration(milliseconds: 200));

      expect(find.text('200,000원'), findsWidgets); // ×2
      await t.tap(find.text('×3').first);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('300,000원'), findsWidgets);
    });

    testWidgets('🔴 항목 추가를 누르면 줄이 늘고, 지우면 준다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      final before = t.widgetList<TextField>(find.byType(TextField)).length;

      await t.tap(find.text('항목 추가').first);
      await t.pump(const Duration(milliseconds: 200));
      final after = t.widgetList<TextField>(find.byType(TextField)).length;
      // 한 줄은 품목명·수량·단가 세 칸이다.
      expect(after, before + 3);

      await t.tap(find.byIcon(Icons.remove_circle_outline_rounded).first);
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widgetList<TextField>(find.byType(TextField)).length, before);
    });

    testWidgets('🔴 줄이 하나뿐이면 지우기 버튼이 없다', (t) async {
      await pumpTall(t, const GuideCostDsScreen(priceBook: PriceBook.empty));
      // 꽃·부자재 각각 한 줄씩이라 지우기 버튼이 하나도 없어야 한다.
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNothing);
    });
  });

  group('원가 계산기 — 소스 계약', () {
    /// 화면 파일에서 원가 계산기 부분만 떼어 본다.
    String costPart() {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      return src.substring(src.indexOf('/// 원가 계산기 — 사장님 시안'),
          src.indexOf('/// 예산 검토'));
    }

    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final part = costPart();
      expect(part.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(part.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 가이드에서 이 화면으로 들어갈 수 있어야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains("'cost' => const GuideCostDsScreen()"), isTrue,
          reason: '스마트 사입 가이드의 연결이 끊겼다');
    });

    test('🔴 가이드 카드는 영역 전체가 눌려야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final card = src.substring(src.indexOf('class _GuideMenuCard'));
      expect(card.contains('HitTestBehavior.opaque'), isTrue,
          reason: '여백을 누르면 반응이 없게 된다');
    });

    test('🔴 셈은 화면이 하지 않고 CostCalc 가 한다', () {
      final part = costPart();
      expect(part.contains('CostCalc.run('), isTrue,
          reason: '화면이 직접 계산하면 숫자를 테스트하기 어려워진다');
      // 이제는 예시값이 아니라 사장님이 적은 값으로 센다.
      expect(part.contains('예시값'), isFalse,
          reason: '기능이 붙었는데 예시값이라는 설명이 남아 있다');
    });

    test('🔴 계산 결과를 저장하지 않는다 (사장님 지시)', () {
      final part = costPart();
      for (final no in ['Firestore', 'SharedPreferences', 'Hive']) {
        expect(part.contains(no), isFalse, reason: '$no 로 저장하려 한다');
      }
    });

    test('🔴 영수증 단가를 끌어오는 길이 살아 있다', () {
      final part = costPart();
      expect(part.contains('PriceBook'), isTrue);
      expect(part.contains('ReceiptProvider'), isTrue,
          reason: '내 영수증에서 단가를 못 가져오게 된다');
    });

    test('🔴 문서에 원가 계산기 절과 남은 숙제가 적혀 있어야 한다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('## 원가 계산기'), isTrue);
      for (final key in ['로스율', '판매 배수', '상품 구성', '칩별 기본 품목']) {
        expect(doc.contains(key), isTrue, reason: '$key 가 문서에 없다');
      }
    });

    test('🔴 "나중에 결정할 것" 섹션이 문서 앞쪽에 있어야 한다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('나중에 결정할 것'), isTrue);
      // 기능 작업을 시작할 때 이 섹션부터 먼저 여쭙기로 했다.
      expect(doc.indexOf('나중에 결정할 것'),
          lessThan(doc.indexOf('## 스마트 사입 가이드')),
          reason: '먼저 읽어야 할 섹션이 뒤에 있다');
      for (final key in [
        '품목군 4분류', '사입 메모장', '사입 한도', '금액 표기',
      ]) {
        expect(doc.contains(key), isTrue, reason: '$key 가 미정 목록에 없다');
      }
    });

    test('🔴 형제 화면 두 개를 지우지 않았다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      for (final c in [
        'class GuideSeasonDsScreen',
        'class GuideBudgetDsScreen',
      ]) {
        expect(src.contains(c), isTrue, reason: '$c 가 사라졌다');
      }
    });
  });
}
