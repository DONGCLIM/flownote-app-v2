import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/purchase_list_model.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/screens/ds/purchase_memo_ds_screen.dart';
import 'package:flow_note/services/cost_calc.dart';
import 'package:flow_note/services/purchase_list_service.dart';
import 'package:flow_note/theme/fn_ds.dart';

String _read(String p) => File(p).readAsStringSync();

/// 스마트 사입 가이드 화면 — 시안 1:1 확인.
///
/// 🔴 지금은 **화면만** 있고 기능은 없다. 그래서 이 테스트도
///    "숫자가 맞는지"가 아니라 "시안대로 그려지는지"만 본다.
///    실제 계산이 붙으면 그때 값 테스트를 따로 넣어야 한다.
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

  /// 실제 폰 크기. 치수·접힘을 볼 때 쓴다.
  Future<void> pump(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 844));

  /// 🔴 이 화면은 `ListView` 라 화면 밖 카드는 **아예 그려지지 않는다.**
  ///    맨 아래 '사입 메모장' 과 안내 문구를 한 번에 확인하려면 화면을
  ///    길게 잡아야 한다. 스크롤해서 보면 위쪽 카드가 반대로 사라진다.
  Future<void> pumpTall(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 1800));

  /// 예산 검토는 카드가 더 많아 1800 으로는 아래쪽이 안 그려진다.
  Future<void> pumpTallBudget(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 2600));

  /// 라벨이 붙은 입력칸을 집는다.
  ///
  /// 🔴 칸을 **번호로 집지 않는다.** 카드를 하나 끼우거나 순서를 바꾸면
  ///    번호가 통째로 밀려서, 테스트가 엉뚱한 칸을 보고도 통과하거나
  ///    까닭 없이 깨진다. 라벨은 화면이 바뀌어도 그대로다.
  Finder fieldFor(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first,
        matching: find.byType(TextField),
      );

  group('스마트 사입 가이드 — 시안 문구', () {
    testWidgets('제목과 맨 위 카드가 시안대로다', (t) async {
      await pump(t, const GuideDsScreen());
      expect(find.text('스마트 사입 가이드'), findsOneWidget);
      expect(find.text('이번 주 사입 준비'), findsOneWidget);
      expect(find.text('예상 예산'), findsOneWidget);
      expect(find.text('27.4만원'), findsOneWidget);
      expect(find.text('금요일 사입 예정 · 3개 품목'), findsOneWidget);
      expect(find.text('한도 400,000원'), findsOneWidget);
    });

    testWidgets('🔴 남은 금액 줄이 한 덩어리로 나온다', (t) async {
      await pump(t, const GuideDsScreen());
      // Text.rich 라 find.text 로는 안 잡힌다. 합쳐진 글자로 찾는다.
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText() == '한도까지 12.6만원 남았어요'),
        findsOneWidget,
      );
    });

    testWidgets('다섯 장의 메뉴 카드가 시안 순서대로 있다', (t) async {
      await pumpTall(t, const GuideDsScreen());
      for (final title in [
        '시즌 매입 비교',
        '원가 계산기',
        '예산 검토',
        '저장된 사입 리스트',
        '사입 메모장',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '$title 카드가 없다');
      }
    });

    testWidgets('메뉴 카드 설명이 시안 문구 그대로다', (t) async {
      await pumpTall(t, const GuideDsScreen());
      for (final desc in [
        '올해 매입을 전년 동기·월 평균과 비교해요.',
        '꽃 조합과 수량으로 판매가와 마진을 계산해요.',
        '직전 매입 단가로 예상 예산을 계산해요.',
        '날짜별 사입 리스트와 예산을 확인해요.',
        '사입 메모와 부케 스케치를 함께 기록해요.',
      ]) {
        expect(find.text(desc), findsOneWidget, reason: '$desc 가 없다');
      }
    });

    testWidgets('메뉴 카드 아래 줄 숫자가 시안 그대로다', (t) async {
      await pumpTall(t, const GuideDsScreen());
      for (final s in [
        '1~7월 +7.5%', '전년 동기 대비',
        '권장가 307,200원', '마진 60%',
        '한도 40만원 중 27.4만원', '69% 사용',
        '3건 저장 · 1회 평균 13.8만원', '최근 07.24',
        '마지막 기록 07.24', '메모 2줄',
      ]) {
        expect(find.text(s), findsOneWidget, reason: '$s 가 없다');
      }
    });

    testWidgets('맨 아래 안내 두 줄이 있다', (t) async {
      await pumpTall(t, const GuideDsScreen());
      expect(
        find.text('내 영수증의 매입 단가를 기준으로 계산해요.\n'
            '저장하면 다음 사입에 이어서 쓸 수 있어요.'),
        findsOneWidget,
      );
    });
  });

  group('스마트 사입 가이드 — 색과 치수', () {
    testWidgets('🔴 예상 예산 금액이 코랄이다', (t) async {
      await pump(t, const GuideDsScreen());
      expect(t.widget<Text>(find.text('27.4만원')).style!.color, FnDs.coral);
    });

    testWidgets('🔴 눈여겨볼 값만 코랄, 나머지는 회색이다', (t) async {
      await pumpTall(t, const GuideDsScreen());
      Color c(String s) => t.widget<Text>(find.text(s)).style!.color!;
      expect(c('마진 60%'), FnDs.coral);
      expect(c('69% 사용'), FnDs.coral);
      expect(c('전년 동기 대비'), FnDs.sub);
      expect(c('최근 07.24'), FnDs.sub);
      expect(c('메모 2줄'), FnDs.sub);
    });

    testWidgets('🔴 막대가 68.5% 만큼만 차 있다', (t) async {
      await pump(t, const GuideDsScreen());
      final bars = t.widgetList<Expanded>(find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(Expanded),
      )).toList();
      expect(bars.length, 2, reason: '막대가 채움/빈칸 두 조각이 아니다');
      final fill = bars[0].flex / (bars[0].flex + bars[1].flex);
      expect(fill, closeTo(0.685, 0.001));
    });

    testWidgets('🔴 화면 좌우 여백이 기준(24)과 같다', (t) async {
      await pump(t, const GuideDsScreen());
      final lv = t.widget<ListView>(find.byType(ListView));
      final pad = lv.padding! as EdgeInsets;
      expect(pad.left, FnDs.pagePad);
      expect(pad.right, FnDs.pagePad);
    });

    testWidgets('카드가 테두리 없이 그림자만 쓴다', (t) async {
      await pump(t, const GuideDsScreen());
      final box = t.widget<Container>(find.ancestor(
        of: find.text('이번 주 사입 준비'),
        matching: find.byType(Container),
      ).first);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, FnDs.card);
      expect(deco.border, isNull, reason: '그림자와 테두리를 같이 쓰면 가장자리가 두 번 보인다');
      expect(deco.boxShadow, isNotNull);
    });
  });

  group('스마트 사입 가이드 — 소스 계약', () {
    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final guide = src.substring(src.indexOf('class GuideDsScreen'),
          src.indexOf('class GuideSeasonDsScreen'));
      expect(guide.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(guide.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 홈에서 이 화면으로 들어갈 수 있어야 한다', () {
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('GuideDsScreen()'), isTrue,
          reason: '홈의 스마트 사입 가이드 연결이 끊겼다');
    });

    test('🔴 아직 없는 화면은 넘어가지 않고 안내만 띄운다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains('곧 준비해서 알려드릴게요.'), isTrue,
          reason: '빈 화면으로 보내면 고장난 것처럼 보인다');
    });

    test('🔴 예시값이라는 사실이 코드에 적혀 있어야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains('예시값'), isTrue);
    });

    test('🔴 나중에 붙일 기능 목록이 문서로 남아 있어야 한다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('스마트 사입 가이드'), isTrue);
      for (final key in [
        'budgetSpend', 'budgetRatio', '저장된 사입 리스트', '사입 메모장',
      ]) {
        expect(doc.contains(key), isTrue, reason: '$key 가 문서에 없다');
      }
    });

    test('🔴 기존 하위 화면 세 개를 지우지 않았다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      for (final c in [
        'class GuideSeasonDsScreen',
        'class GuideCostDsScreen',
        'class GuideBudgetDsScreen',
      ]) {
        expect(src.contains(c), isTrue, reason: '$c 가 사라졌다');
      }
    });
  });

  group('예산 검토 — 사입 리스트 저장 (#179)', () {
    /// 영수증 몇 장. 자동완성·자주 산 품목을 확인하는 데 쓴다.
    List<ReceiptModel> receipts() => [
          ReceiptModel(
            id: 'r3',
            date: DateTime(2026, 7, 24),
            storeName: '양재',
            rawOcrText: '',
            createdAt: DateTime(2026, 7, 24),
            totalAmount: 160000,
            items: [
              FlowerItem(
                  name: '장미(레드)', quantity: 20, unitPrice: 8000, unit: '단'),
            ],
          ),
          ReceiptModel(
            id: 'r2',
            date: DateTime(2026, 7, 17),
            storeName: '양재',
            rawOcrText: '',
            createdAt: DateTime(2026, 7, 17),
            totalAmount: 90000,
            items: [
              FlowerItem(
                  name: '장미(레드)', quantity: 10, unitPrice: 7000, unit: '단'),
              FlowerItem(name: '거베라', quantity: 15, unitPrice: 6000, unit: '단'),
            ],
          ),
        ];

    testWidgets('제목과 안내문이 시안대로다', (t) async {
      await pump(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('예산 검토'), findsOneWidget);
      expect(
        find.text('사입 목록을 적으면 직전 영수증 단가로 예상 예산을 계산해요.\n'
            '이번 주 한도와 비교해 남은 금액도 확인하세요.'),
        findsOneWidget,
      );
    });

    testWidgets('🔴 날짜·목적 칸이 맨 위에 있다', (t) async {
      await pump(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('사입 날짜'), findsOneWidget);
      expect(find.text('목적'), findsOneWidget);
      // 목적 칸 힌트가 시안 그대로여야 한다.
      expect(find.text('예) 주말 부케 3건 대비'), findsOneWidget);
    });

    testWidgets('🔴 날짜 기본값이 내일이다', (t) async {
      await pump(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      final now = DateTime.now();
      final tm = DateTime(now.year, now.month, now.day + 1);
      const dow = ['월', '화', '수', '목', '금', '토', '일'];
      final label = '${tm.year}.${tm.month.toString().padLeft(2, '0')}.'
          '${tm.day.toString().padLeft(2, '0')} (${dow[tm.weekday - 1]})';
      expect(find.text(label), findsOneWidget,
          reason: '시장 전날 밤에 적으므로 기본값은 내일이어야 한다');
    });

    testWidgets('🔴 한도 처음 값이 스마트 사입 가이드 한도와 같다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('이번 사입 한도'), findsOneWidget);
      // 가이드의 '한도 400,000원' 과 같은 값이어야 한다.
      expect(GuideDsScreen.defaultBudgetCap, 400000);
      expect(GuideDsScreen.budgetCap.contains('400,000'), isTrue,
          reason: '두 곳의 한도가 어긋났다');
    });

    testWidgets('🔴 "이번 주 사입 한도" 가 아니라 "이번 사입 한도" 다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('이번 주 사입 한도'), findsNothing);
      expect(find.text('이번 사입 한도'), findsOneWidget);
    });

    testWidgets('🔴 하단 버튼이 "저장하고 사입 메모장으로" 다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('사입 메모장 열기'), findsNothing);
      expect(find.text('저장하고 사입 메모장으로'), findsOneWidget);
    });

    testWidgets('🔴 적으면 예상 예산과 남은 예산이 바로 바뀐다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(find.text('0개 품목 · 0원'), findsOneWidget);

      // 첫 줄: 품목명 / 수량 / 단가
      await t.enterText(fieldFor('수량'), '20');
      await t.enterText(fieldFor('단가'), '8000');
      await t.pump(const Duration(milliseconds: 200));

      expect(find.text('1개 품목 · 160,000원'), findsOneWidget);
      expect(find.text('160,000원'), findsWidgets);
      // 한도 400,000 - 160,000 = 240,000
      expect(find.text('240,000원'), findsWidgets);
      expect(find.text('남은 예산'), findsOneWidget);
    });

    testWidgets('🔴 한도를 넘으면 얼마나 넘었는지 빨간 글씨로 알려 준다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      await t.enterText(fieldFor('수량'), '100');
      await t.enterText(fieldFor('단가'), '5000');
      await t.pump(const Duration(milliseconds: 200));

      // 500,000 - 400,000 = 100,000 초과
      expect(find.text('한도 초과'), findsOneWidget);
      expect(find.text('남은 예산'), findsNothing);
      final over = find.text('한도를 100,000원 넘었어요');
      expect(over, findsOneWidget);
      expect(t.widget<Text>(over).style!.color, FnDs.negative);
    });

    testWidgets('🔴 단가를 가져온 영수증 날짜가 보인다', (t) async {
      final book = PriceBook.fromReceipts(receipts());
      await pumpTallBudget(
          t, GuideBudgetDsScreen(priceBook: book, frequent: const []));

      await t.tap(fieldFor('품목명'));                 // 칸을 눌러 목록을 편다
      await t.enterText(fieldFor('품목명'), '장미');
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('장미(레드)').last);        // 자동완성에서 고르기
      await t.pump(const Duration(milliseconds: 300));

      // 가장 최근(7/24) 단가가 채워지고, 그 날짜가 함께 보여야 한다.
      expect(find.textContaining('07/24 기준'), findsOneWidget);
    });

    testWidgets('🔴 자주 산 품목을 누르면 한 줄이 채워진다', (t) async {
      final freq = PurchaseListService.frequentItems(receipts(),
          now: DateTime(2026, 7, 25));
      expect(freq.isNotEmpty, isTrue);
      await pumpTallBudget(
          t, GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: freq));

      expect(find.text('자주 산 품목'), findsOneWidget);
      await t.tap(find.text('장미(레드)').first);
      await t.pump(const Duration(milliseconds: 300));

      // 품목명 칸에 들어가고 단가도 채워진다.
      final name = t.widget<TextField>(fieldFor('품목명'));
      expect(name.controller!.text, '장미(레드)');
      final price = t.widget<TextField>(fieldFor('단가'));
      expect(price.controller!.text, '8,000');
    });
  });

  group('사입 리스트 — 셈과 상태 (#179)', () {
    test('🔴 "못 샀어요"도 처리된 것으로 쳐서 완료가 된다', () {
      final now = DateTime.now();
      final list = PurchaseList(
        id: 'x', date: now, createdAt: now, updatedAt: now,
        items: [
          PurchaseItem(name: 'a', qty: 1, unitPrice: 1000, checked: true),
          PurchaseItem(name: 'b', qty: 1, unitPrice: 2000, missed: true),
        ],
      );
      list.refreshStatus();
      // 하나를 못 샀어도 나머지를 다 처리했으면 완료다. (사장님 확정)
      expect(list.status, PurchaseStatus.done);
    });

    test('상태가 준비 → 사입 중 → 완료 순으로 간다', () {
      final now = DateTime.now();
      final list = PurchaseList(
        id: 'x', date: now, createdAt: now, updatedAt: now,
        items: [
          PurchaseItem(name: 'a', qty: 1, unitPrice: 1000),
          PurchaseItem(name: 'b', qty: 1, unitPrice: 2000),
        ],
      );
      list.refreshStatus();
      expect(list.status, PurchaseStatus.ready);

      list.items[0].checked = true;
      list.refreshStatus();
      expect(list.status, PurchaseStatus.shopping);

      list.items[1].checked = true;
      list.refreshStatus();
      expect(list.status, PurchaseStatus.done);
    });

    test('🔴 못 산 품목은 돈을 안 쓴 것으로 센다', () {
      final now = DateTime.now();
      final list = PurchaseList(
        id: 'x', date: now, createdAt: now, updatedAt: now,
        budgetCap: 100000,
        items: [
          PurchaseItem(name: 'a', qty: 2, unitPrice: 10000, checked: true),
          PurchaseItem(name: 'b', qty: 3, unitPrice: 5000, missed: true),
        ],
      );
      expect(list.plannedTotal, 35000);   // 계획은 둘 다 센다
      expect(list.spentTotal, 20000);     // 실제로 쓴 건 산 것만
      expect(list.liveRemaining, 80000);
    });

    test('🔴 시장에서 고친 실제 단가로 센다', () {
      final it = PurchaseItem(
          name: 'a', qty: 10, unitPrice: 8000, checked: true, actualPrice: 9000);
      expect(it.plannedAmount, 80000);
      expect(it.spentAmount, 90000);      // 비싸게 샀으면 그 값으로
    });

    test('한도를 넘었는지 알려 준다', () {
      final now = DateTime.now();
      final list = PurchaseList(
        id: 'x', date: now, createdAt: now, updatedAt: now,
        budgetCap: 100000,
        items: [PurchaseItem(name: 'a', qty: 1, unitPrice: 120000)],
      );
      expect(list.overBudget, isTrue);
      expect(list.remaining, -20000);
    });

    test('🔴 한도를 안 정했으면 초과로 보지 않는다', () {
      final now = DateTime.now();
      final list = PurchaseList(
        id: 'x', date: now, createdAt: now, updatedAt: now,
        items: [PurchaseItem(name: 'a', qty: 1, unitPrice: 120000)],
      );
      // 한도 0 은 "안 정함" 이다. 늘 초과라고 하면 빨간 글씨만 남는다.
      expect(list.overBudget, isFalse);
    });
  });

  group('자주 산 품목 고르기 (#179)', () {
    ReceiptModel r(String id, DateTime d, List<FlowerItem> items) =>
        ReceiptModel(
          id: id, date: d, storeName: '양재', rawOcrText: '',
          createdAt: d, totalAmount: 0, items: items,
        );
    FlowerItem f(String n, double p) =>
        FlowerItem(name: n, quantity: 1, unitPrice: p, unit: '단');

    test('🔴 산 횟수가 많은 순으로 준다', () {
      final now = DateTime(2026, 7, 25);
      final list = PurchaseListService.frequentItems([
        r('1', DateTime(2026, 7, 20), [f('장미', 8000), f('거베라', 6000)]),
        r('2', DateTime(2026, 7, 10), [f('장미', 7000)]),
        r('3', DateTime(2026, 6, 30), [f('장미', 7500), f('튤립', 5000)]),
      ], now: now);
      expect(list.first.name, '장미');
      expect(list.map((e) => e.name), containsAll(['장미', '거베라', '튤립']));
    });

    test('🔴 3개월보다 오래된 영수증은 안 센다', () {
      final now = DateTime(2026, 7, 25);
      final list = PurchaseListService.frequentItems([
        r('old', DateTime(2026, 1, 5), [f('작약', 9000)]),
        r('new', DateTime(2026, 7, 20), [f('장미', 8000)]),
      ], now: now);
      expect(list.map((e) => e.name), ['장미']);
    });

    test('🔴 한 영수증에 같은 품목이 두 줄이어도 한 번으로 센다', () {
      final now = DateTime(2026, 7, 25);
      final list = PurchaseListService.frequentItems([
        // 장미를 한 영수증에 두 줄 적었다 — 1회로 센다.
        r('1', DateTime(2026, 7, 20), [f('장미', 8000), f('장미', 8200)]),
        // 거베라는 다른 날 두 번 샀다 — 2회.
        r('2', DateTime(2026, 7, 18), [f('거베라', 6000)]),
        r('3', DateTime(2026, 7, 10), [f('거베라', 6100)]),
      ], now: now);
      expect(list.first.name, '거베라', reason: '줄을 나눠 적은 날이 더 자주 산 것처럼 보이면 안 된다');
    });

    test('최대 여섯 개까지만 준다', () {
      final now = DateTime(2026, 7, 25);
      final many = List.generate(
        10,
        (i) => r('$i', DateTime(2026, 7, 20 - i), [f('꽃$i', 1000.0 + i)]),
      );
      expect(PurchaseListService.frequentItems(many, now: now).length, 6);
    });

    test('영수증이 없으면 빈 목록이다', () {
      expect(PurchaseListService.frequentItems(const []), isEmpty);
    });
  });

  group('예산 검토 — 소스 계약 (#179)', () {
    test('🔴 원가 계산기와 같은 조각을 쓴다 (복사하지 않았다)', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains("import '../../widgets/fn_purchase_parts.dart';"),
          isTrue);
      // 예전에 화면 안에 있던 중복 클래스가 사라졌어야 한다.
      for (final gone in ['class _CostNamedField', 'class _CostLineRow',
                          'class _CostPill', 'class _LineCtrl']) {
        expect(src.contains(gone), isFalse, reason: '$gone 가 아직 화면에 남아 있다');
      }
    });

    test('🔴 계정마다 상자를 따로 쓴다', () {
      // 남의 사입 리스트가 보이면 안 된다. 영수증에서 겪은 문제다(#179).
      final a = PurchaseListService.boxNameFor('uidA');
      final b = PurchaseListService.boxNameFor('uidB');
      expect(a == b, isFalse);
      expect(a.startsWith('plists_'), isTrue);
      // 로그인 전에는 손님 상자.
      expect(PurchaseListService.boxNameFor(null), 'plists_guest');
    });

    test('🔴 상자 이름에 uid 를 그대로 쓰지 않는다', () {
      // Hive 는 상자 이름 대소문자를 구분하지 않는데 uid 는 구분한다.
      // 카카오 uid 의 ':' 는 파일 이름에 못 쓴다.
      final k = PurchaseListService.boxNameFor('kakao:5056436825');
      expect(k.contains(':'), isFalse);
      expect(PurchaseListService.boxNameFor('aB') ==
             PurchaseListService.boxNameFor('Ab'), isFalse);
    });

    test('🔴 서버 저장을 글자마다 하지 않는다', () {
      final src = _read('lib/services/purchase_list_service.dart');
      // 모아서 올리는 장치가 있어야 한다.
      expect(src.contains('_syncDelay'), isTrue);
      expect(src.contains('Future<void> flush()'), isTrue);
    });

    test('🔴 스케치를 그림이 아니라 좌표로 저장한다', () {
      final src = _read('lib/models/purchase_list_model.dart');
      expect(src.contains('class SketchStroke'), isTrue);
      expect(src.contains('List<double> points'), isTrue);
      // 그림 파일로 저장하면 이어 그릴 수 없다. (사장님 선택)
      expect(src.contains('Uint8List'), isFalse);
    });

    test('🔴 영수증이 쓰는 typeId 를 다시 쓰지 않는다', () {
      final src = _read('lib/models/purchase_list_model.dart');
      // 0·1 은 ReceiptModel·FlowerItem 이 쓴다. 겹치면 저장된 게 깨진다.
      expect(src.contains('@HiveType(typeId: 2)'), isTrue);
      expect(src.contains('@HiveType(typeId: 0)'), isFalse);
      expect(src.contains('@HiveType(typeId: 1)'), isFalse);
    });

    test('🔴 사입 리스트도 탈퇴 때 같이 지운다', () {
      final src = _read('lib/services/user_repository.dart');
      final del = src.substring(src.indexOf('deleteAllUserData'));
      expect(del.contains('_plistsCol'), isTrue,
          reason: '탈퇴해도 서버에 사입 기록이 남는다');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 사입 메모장 (#185)
  // ═══════════════════════════════════════════════════════════════════

  /// 🔴 메모장은 `PurchaseListService` 를 바로 읽는다. 테스트에서는 Hive 를
  ///    열 수 없어서 서비스가 비어 있는데, 그때도 화면이 떠야 한다.
  ///    (리스트를 못 찾으면 스스로 내일 날짜로 만든다 — 사장님 지시 #185)
  group('사입 메모장 — 화면 (#185)', () {
    testWidgets('🔴 날짜·안내문·탭이 시안대로다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      expect(find.text('사입 메모장'), findsOneWidget);
      expect(
          find.text('사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를 그려 기록해요.'),
          findsOneWidget);
      expect(find.text('메모'), findsOneWidget);
      expect(find.text('스케치'), findsOneWidget);
      // 날짜는 `11/26(목) 사입` 꼴이다.
      expect(find.textContaining(RegExp(r'^\d+/\d+\(.\) 사입$')), findsOneWidget);
    });

    testWidgets('🔴 기본은 메모 탭이고, 누르면 스케치 탭으로 바뀐다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      // 메모 탭 — 글칸이 있고 색 고르개는 없다.
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('지우기'), findsNothing);

      await t.tap(find.text('스케치'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('지우기'), findsOneWidget);
      expect(find.text('얇게'), findsOneWidget);
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('굵게'), findsOneWidget);
      expect(find.text('꽃 배치나 부케 모양을 손으로 그려 기록해두세요.'), findsOneWidget);
    });

    testWidgets('🔴 탭을 바꿔도 적은 글이 그대로 남는다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      await t.enterText(find.byType(TextField).first, '금요일 웨딩 부케 3개');
      await t.pump(const Duration(milliseconds: 200));

      await t.tap(find.text('스케치'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('금요일 웨딩 부케 3개'), findsNothing);

      // 🔴 `textContaining('메모')` 로 집으면 제목 '사입 메모장' 과
      //    안내문까지 세 개가 잡혀 tap() 이 고르지 못한다.
      await t.tap(find.text('메모 0/1'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('금요일 웨딩 부케 3개'), findsOneWidget);
    });

    testWidgets('🔴 글을 적으면 메모 탭에 "0/1" 처럼 개수가 붙는다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      expect(find.text('메모'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '소국 두 단');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('메모 0/1'), findsOneWidget);
    });

    testWidgets('🔴 체크하면 코랄 ✓ 가 되고 글자에 가운데줄이 그어진다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      await t.enterText(find.byType(TextField).first, '소국 두 단');
      await t.pump(const Duration(milliseconds: 200));

      // 구매 전 — 체크 표시가 없다.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      var field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.style!.decoration, isNot(TextDecoration.lineThrough));

      await t.tap(find.bySemanticsLabel('구매 전'));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      field = t.widget<TextField>(find.byType(TextField).first);
      expect(field.style!.decoration, TextDecoration.lineThrough);
      expect(field.style!.color, FnDs.sub);
      expect(find.text('메모 1/1'), findsOneWidget);

      // 다시 누르면 취소된다.
      await t.tap(find.bySemanticsLabel('구매 완료'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.text('메모 0/1'), findsOneWidget);
    });

    testWidgets('🔴 엔터를 치면 체크칸이 있는 새 줄이 생긴다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      expect(find.byType(TextField), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '첫 줄');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byType(TextField), findsNWidgets(2));
      // 체크칸도 두 개여야 한다. 체크칸 없는 줄이 생기면 안 된다.
      expect(find.bySemanticsLabel('구매 전'), findsNWidgets(2));
    });

    testWidgets('🔴 체크해도 줄 순서가 바뀌지 않는다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      await t.enterText(find.byType(TextField).first, '가');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField).last, '나');
      await t.pump(const Duration(milliseconds: 200));

      // 첫 줄을 체크한다.
      await t.tap(find.bySemanticsLabel('구매 전').first);
      await t.pump(const Duration(milliseconds: 300));

      // 산 줄이 아래로 내려가면 안 된다. 첫 칸이 그대로 '가' 여야 한다.
      final first = t.widget<TextField>(find.byType(TextField).first);
      expect(first.controller!.text, '가');
      expect(first.style!.decoration, TextDecoration.lineThrough);
    });

    testWidgets('🔴 고른 탭의 카드가 화면 아래까지 꽉 찬다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      // 🔴 `Expanded` 로 집지 않는다. FnShell 안에도 Expanded 가 있어서
      //    바깥 것이 먼저 잡히고, 그 안의 첫 Container 는 탭 칩이다.
      //    카드는 기준 꾸밈(모서리 18)으로 가린다.
      final cards = t
          .widgetList<Container>(find.byType(Container))
          .where((e) =>
              e.decoration is BoxDecoration &&
              (e.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(FnDs.cardRadius))
          .toList();
      expect(cards, isNotEmpty);

      final heights = <double>[];
      for (final el in find.byType(Container).evaluate()) {
        final w = el.widget as Container;
        final d = w.decoration;
        if (d is! BoxDecoration) continue;
        if (d.borderRadius != BorderRadius.circular(FnDs.cardRadius)) continue;
        heights.add(el.size!.height);
      }
      expect(heights.reduce((a, b) => a > b ? a : b), greaterThan(400),
          reason: '카드가 내용만큼만 높으면 아래가 비어 보인다');
    });

    testWidgets('🔴 "그림 저장은 곧 추가돼요" 같은 미완성 안내가 없다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      await t.tap(find.text('스케치'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('곧 추가'), findsNothing);
      expect(find.textContaining('준비'), findsNothing);
      expect(find.text('사입 리스트를 찾지 못했어요.'), findsNothing);
    });

    testWidgets('🔴 그림을 그리면 스케치 탭에 코랄 점이 붙는다', (t) async {
      await pump(t, const PurchaseMemoDsScreen());
      await t.tap(find.text('스케치'));
      await t.pump(const Duration(milliseconds: 300));

      // 🔴 크기로 가른다. 펜 색 고르개의 첫 칸도 코랄 동그라미(30)라
      //    색·모양만 보면 그것까지 잡혀 "이미 점이 있다" 가 된다.
      //    탭에 붙는 점은 7 이다.
      Iterable<Container> dots() => t
          .widgetList<Container>(find.byType(Container))
          .where((e) =>
              e.decoration is BoxDecoration &&
              (e.decoration! as BoxDecoration).color == FnDs.coral &&
              (e.decoration! as BoxDecoration).shape == BoxShape.circle &&
              e.constraints?.maxWidth == 7);
      expect(dots(), isEmpty);

      // 스케치 칸 가운데에 선을 긋는다.
      final pad = find.byType(CustomPaint).last;
      final c = t.getCenter(pad);
      await t.dragFrom(c, const Offset(40, 30));
      await t.pump(const Duration(milliseconds: 300));

      expect(dots(), isNotEmpty, reason: '그림이 있으면 탭에 점이 붙어야 한다');
    });
  });

  group('사입 메모장 — 저장 (#185)', () {
    test('🔴 체크 상태를 memo 한 칸에 같이 담는다 (새 구조 안 만듦)', () {
      const lines = [
        MemoLine(text: '금요일 웨딩 부케 3개'),
        MemoLine(text: '소국으로 대체', checked: true),
      ];
      final raw = MemoText.encode(lines);
      expect(raw, '[ ] 금요일 웨딩 부케 3개\n[x] 소국으로 대체');
      expect(MemoText.parse(raw), lines);
    });

    test('🔴 표시가 없는 옛 메모도 그대로 읽는다', () {
      // 1단계에서 적어 둔 메모에는 `[ ]` 가 없다. 못 읽으면 글이 사라진다.
      final out = MemoText.parse('그냥 적은 줄\n또 한 줄');
      expect(out.length, 2);
      expect(out.first.text, '그냥 적은 줄');
      expect(out.first.checked, isFalse);
    });

    test('🔴 끝의 빈 줄은 버린다', () {
      const lines = [
        MemoLine(text: '한 줄'),
        MemoLine(text: ''),
        MemoLine(text: '   '),
      ];
      expect(MemoText.encode(lines), '[ ] 한 줄');
    });

    test('가운데 빈 줄은 남긴다', () {
      const lines = [
        MemoLine(text: '가'),
        MemoLine(text: ''),
        MemoLine(text: '나'),
      ];
      expect(MemoText.encode(lines), '[ ] 가\n[ ] \n[ ] 나');
    });

    test('🔴 탭 옆 개수는 글이 있는 줄만 센다', () {
      const lines = [
        MemoLine(text: '가', checked: true),
        MemoLine(text: '나'),
        MemoLine(text: ''), // 빈 줄은 품목이 아니다
      ];
      expect(MemoText.counter(lines), '1/2');
      // 아무것도 안 적었으면 숫자를 안 붙인다.
      expect(MemoText.counter(const [MemoLine(text: '')]), '');
    });

    test('빈 메모는 빈 목록이다', () {
      expect(MemoText.parse(''), isEmpty);
      expect(MemoText.encode(const []), '');
    });
  });

  group('사입 메모장 — 소스 계약 (#185)', () {
    String memoSrc() => _read('lib/screens/ds/purchase_memo_ds_screen.dart');

    test('🔴 1단계 저장 구조를 그대로 쓴다 (새로 만들지 않았다)', () {
      final src = memoSrc();
      expect(src.contains('PurchaseListService.instance'), isTrue);
      expect(src.contains('PurchaseList'), isTrue);
      // 새 Hive 상자·새 타입을 만들면 안 된다.
      expect(src.contains('Hive.openBox'), isFalse);
      expect(src.contains('@HiveType'), isFalse);
    });

    test('🔴 저장을 1단계와 같은 방식으로 한다 (모아서 + 나갈 때 즉시)', () {
      final src = memoSrc();
      expect(src.contains('.touch('), isTrue, reason: '폰에 바로 안 쓴다');
      expect(src.contains('.flush()'), isTrue, reason: '나갈 때 안 올린다');
      // 4초 모으기는 서비스가 한다. 화면이 따로 타이머를 돌리면 안 된다.
      expect(src.contains('Timer('), isFalse);
    });

    test('🔴 스케치를 그림이 아니라 좌표로 담는다', () {
      final src = memoSrc();
      expect(src.contains('SketchStroke('), isTrue);
      expect(src.contains('points'), isTrue);
      // 이미지로 떠서 저장하면 용량이 커지고 이어 그릴 수 없다.
      expect(src.contains('toImage'), isFalse);
      expect(src.contains('toByteData'), isFalse);
    });

    test('🔴 색 8개·굵기 3개가 시안대로다', () {
      final src = memoSrc();
      final head = src.substring(src.indexOf('const List<int> _penColors'));
      expect('0xFF'.allMatches(head).length, greaterThanOrEqualTo(8));
      for (final w in ['얇게', '보통', '굵게']) {
        expect(src.contains("'$w'"), isTrue);
      }
    });

    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final src = memoSrc();
      expect(src.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(src.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 칩 모양을 새로 만들지 않고 FnPill 을 쓴다', () {
      expect(memoSrc().contains('FnPill('), isTrue);
    });

    test('🔴 세 군데에서 들어올 수 있다 (예산 검토·가이드·홈 칩)', () {
      final budget = _read('lib/screens/ds/insight_ds_screens.dart');
      // 예산 검토 → 저장한 그 리스트로
      expect(budget.contains('PurchaseMemoDsScreen(listId: list.id)'), isTrue);
      // 가이드 목록 → 화면이 스스로 고른다
      expect(budget.contains("'memo' => const PurchaseMemoDsScreen()"), isTrue);
      // 홈 바로가기 칩
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('const PurchaseMemoDsScreen()'), isTrue);
    });

    test('🔴 리스트를 못 찾아도 적을 수 있다', () {
      final src = memoSrc();
      // 가장 최근 준비/사입 중 → 없으면 새로 만든다.
      expect(src.contains('svc.activeOne'), isTrue);
      expect(src.contains('svc.draft()'), isTrue);
      expect(src.contains('사입 리스트를 찾지 못했어요'), isFalse);
    });

    test('🔴 사입 리스트 진행 상태가 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('메모장 탭·체크·스케치 저장 완료'), isTrue);
    });
  });
}
