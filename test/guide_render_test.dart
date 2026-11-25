import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/purchase_list_model.dart';
import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/screens/ds/purchase_memo_ds_screen.dart';
import 'package:flow_note/screens/ds/saved_lists_ds_screen.dart';
import 'package:flow_note/services/cost_calc.dart';
import 'package:flow_note/services/purchase_list_service.dart';
import 'package:flow_note/theme/fn_ds.dart';
import 'package:flow_note/widgets/fn_inquiry_parts.dart';
import 'package:flow_note/widgets/fn_purchase_parts.dart';

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

    testWidgets('🔴 하단 버튼이 "사입 리스트 저장" 이다 (#188)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      // 🔴 #188 에서 글자를 짧게 바꿨다. 저장하면 저장된 사입 리스트로 간다.
      expect(find.text('사입 메모장 열기'), findsNothing);
      expect(find.text('저장하고 사입 메모장으로'), findsNothing);
      expect(find.text('저장하고 사입 리스트로'), findsNothing);
      expect(find.text('사입 리스트 저장'), findsOneWidget);
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
      // 🔴 #188 에서 문구가 '07/24 영수증 기준' 으로 짧아졌다.
      //    반쪽 폭 줄에 들어가야 해서 '1단 기준' 을 뺐다.
      expect(find.textContaining('07/24 영수증 기준'), findsOneWidget);
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
    /// 🔴 #189 에서 머리 카드(날짜·목적)가 생겨 글칸이 하나 늘었다.
    ///    메모 줄 칸은 **맨 뒤**다. 목적 칸을 집으면 엉뚱한 곳에 적힌다.
    Finder memoField() => find.byType(TextField).last;

    testWidgets('🔴 날짜·안내문·탭이 시안대로다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
      expect(find.text('사입 메모장'), findsOneWidget);
      expect(
          find.text('사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치를 그려 기록해요.'),
          findsOneWidget);
      expect(find.text('메모'), findsOneWidget);
      expect(find.text('스케치'), findsOneWidget);
      // 🔴 #189 에서 `11/26(목) 사입` 한 줄 대신 예산 검토와 같은
      //    날짜·목적 카드가 들어왔다. (사장님 지시)
      expect(find.text('사입 날짜'), findsOneWidget);
      expect(find.text('목적'), findsOneWidget);
    });

    testWidgets('🔴 기본은 메모 탭이고, 누르면 스케치 탭으로 바뀐다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
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
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.enterText(memoField(), '금요일 웨딩 부케 3개');
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
      await pumpTall(t, const PurchaseMemoDsScreen());
      expect(find.text('메모'), findsOneWidget);

      await t.enterText(memoField(), '소국 두 단');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('메모 0/1'), findsOneWidget);
    });

    testWidgets('🔴 체크하면 코랄 ✓ 가 되고 글자에 가운데줄이 그어진다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.enterText(memoField(), '소국 두 단');
      await t.pump(const Duration(milliseconds: 200));

      // 구매 전 — 체크 표시가 없다.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      var field = t.widget<TextField>(memoField());
      expect(field.style!.decoration, isNot(TextDecoration.lineThrough));

      await t.tap(find.bySemanticsLabel('구매 전'));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      field = t.widget<TextField>(memoField());
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
      await pumpTall(t, const PurchaseMemoDsScreen());
      // 목적 칸 1 + 메모 줄 1. (#189 머리 카드)
      expect(find.byType(TextField), findsNWidgets(2));

      await t.enterText(memoField(), '첫 줄');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byType(TextField), findsNWidgets(3));
      // 체크칸도 두 개여야 한다. 체크칸 없는 줄이 생기면 안 된다.
      expect(find.bySemanticsLabel('구매 전'), findsNWidgets(2));
    });

    testWidgets('🔴 체크해도 줄 순서가 바뀌지 않는다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.enterText(memoField(), '가');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(memoField(), '나');
      await t.pump(const Duration(milliseconds: 200));

      // 첫 줄을 체크한다.
      await t.tap(find.bySemanticsLabel('구매 전').first);
      await t.pump(const Duration(milliseconds: 300));

      // 산 줄이 아래로 내려가면 안 된다. 첫 메모 칸이 '가' 여야 한다.
      // (목적 칸 다음이 첫 메모 줄이다)
      final first = t.widget<TextField>(find.byType(TextField).at(1));
      expect(first.controller!.text, '가');
      expect(first.style!.decoration, TextDecoration.lineThrough);
    });

    testWidgets('🔴 고른 탭의 카드가 화면 아래까지 꽉 찬다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
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
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.tap(find.text('스케치'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('곧 추가'), findsNothing);
      expect(find.textContaining('준비'), findsNothing);
      expect(find.text('사입 리스트를 찾지 못했어요.'), findsNothing);
    });

    testWidgets('🔴 그림을 그리면 스케치 탭에 코랄 점이 붙는다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
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

    test('🔴 가이드 목록·홈 칩에서 들어올 수 있다', () {
      // 🔴 #187 에서 **예산 검토는 빠졌다.** 저장 버튼이 저장된 사입
      //    리스트로 간다. (#189 에서 저장된 리스트 → 메모장 길이 생겼다)
      final guide = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(guide.contains("'memo' => const PurchaseMemoDsScreen()"), isTrue);
      expect(guide.contains('PurchaseMemoDsScreen(listId: list.id)'), isFalse,
          reason: '예산 검토가 아직 메모장으로 간다');
      // 홈 바로가기 칩
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('const PurchaseMemoDsScreen()'), isTrue);
    });

    test('🔴 리스트를 못 찾아도 적을 수 있다', () {
      final src = memoSrc();
      // 🔴 #189 에서 `svc.activeOne` 을 끊었다. 그건 예산 검토에서 저장해
      //    둔 남의 리스트를 집어 와 메모를 덮어쓰던 길이다.
      //    이제 자기만의 임시 작성분을 쓴다.
      expect(src.contains('svc.memoDraft()'), isTrue);
      expect(src.contains('사입 리스트를 찾지 못했어요'), isFalse);
    });

    test('🔴 사입 리스트 진행 상태가 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('메모장 탭·체크·스케치 저장 완료'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 저장된 사입 리스트 (#187)
  // ═══════════════════════════════════════════════════════════════════

  PurchaseItem pi(String name, double qty, double price, {String unit = '단'}) =>
      PurchaseItem(name: name, qty: qty, unitPrice: price, unit: unit);

  PurchaseList plist(
    String id,
    DateTime date, {
    String purpose = '',
    List<PurchaseItem>? items,
    String memo = '',
  }) =>
      PurchaseList(
        id: id,
        date: date,
        purpose: purpose,
        items: items,
        memo: memo,
        createdAt: date,
        updatedAt: date,
      );

  /// 🔴 사장님이 주신 검산값 그대로.
  ///
  /// ```
  ///   07.24  장미 20단×8,000 + 거베라 15단×6,000 + 수국 5개×2,400
  ///          = 160,000 + 90,000 + 12,000 = 262,000원
  ///   07.17  소국 10단×2,500 + 유칼립투스 5단×3,500 = 42,500원
  ///   07.11  장미 8단×8,000 + 안개 12단×2,800 + 포장지 2롤×6,400
  ///          = 64,000 + 33,600 + 12,800 = 110,400원
  ///   ─────────────────────────────────────────
  ///   합계 414,900원 · 1회 평균 138,300원
  /// ```
  List<PurchaseList> saved() => [
        plist('a', DateTime(2026, 7, 24), purpose: '주말 부케 3건 대비', items: [
          pi('장미(레드)', 20, 8000),
          pi('거베라', 15, 6000),
          pi('수국', 5, 2400, unit: '개'),
        ]),
        plist('b', DateTime(2026, 7, 17), purpose: '개업 화환 2건', items: [
          pi('소국', 10, 2500),
          pi('유칼립투스', 5, 3500),
        ]),
        plist('c', DateTime(2026, 7, 11), purpose: '정기 매장 진열', items: [
          pi('장미(레드)', 8, 8000),
          pi('안개', 12, 2800),
          pi('포장지', 2, 6400, unit: '롤'),
        ]),
      ];

  group('저장된 사입 리스트 — 검산 (사장님이 주신 값)', () {
    test('🔴 262,000 / 42,500 / 110,400 → 합계 414,900 · 평균 138,300', () {
      final lists = saved();
      expect(lists[0].plannedTotal, 262000);
      expect(lists[1].plannedTotal, 42500);
      expect(lists[2].plannedTotal, 110400);

      final s = PurchaseListService.summarize(lists);
      expect(s.count, 3);
      expect(s.total, 414900);
      expect(s.average, 138300);
    });

    test('🔴 메모 리스트가 하나 더 있어도 합계·평균은 그대로', () {
      // 🔴 메모만 적은 리스트를 평균에 넣으면 138,300 → 103,725 가 된다.
      //    사장님 지시(#187): "예산 없는 메모 리스트는 금액 계산에서 제외".
      final lists = [
        ...saved(),
        plist('memo', DateTime(2026, 7, 20),
            memo: '[ ] 화병 사오기\n[x] 리본 주문'),
      ];
      final s = PurchaseListService.summarize(lists);
      // 건수는 넷이지만 금액은 셋만 센다.
      expect(s.count, 4);
      expect(s.total, 414900);
      expect(s.average, 138300);
    });

    test('메모 리스트인지 알아본다', () {
      final memo = plist('m', DateTime(2026, 7, 20),
          memo: '[ ] 화병 사오기\n[x] 리본 주문\n[ ] ');
      expect(memo.isMemoOnly, isTrue);
      // 빈 줄은 세지 않는다.
      expect(memo.memoLineCount, 2);
      expect(saved().first.isMemoOnly, isFalse);
    });

    test('하나도 없으면 전부 0', () {
      final s = PurchaseListService.summarize(const []);
      expect(s.count, 0);
      expect(s.total, 0);
      expect(s.average, 0);
    });

    test('메모 리스트만 있으면 평균이 0 이다 (0 으로 안 나눈다)', () {
      final s = PurchaseListService.summarize([
        plist('m1', DateTime(2026, 7, 20), memo: '한 줄'),
        plist('m2', DateTime(2026, 7, 21), memo: '두 줄'),
      ]);
      expect(s.count, 2);
      expect(s.total, 0);
      expect(s.average, 0);
    });
  });

  group('저장된 사입 리스트 — 화면 (#187)', () {
    testWidgets('🔴 시안대로 요약과 리스트가 보인다', (t) async {
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved()));

      expect(find.text('저장된 사입 리스트'), findsOneWidget);
      expect(find.text('날짜별 사입 리스트를 확인하고,\n같은 구성으로 새 리스트를 만들 수 있어요.'),
          findsOneWidget);

      expect(find.text('저장된 리스트'), findsOneWidget);
      expect(find.text('3건'), findsOneWidget);
      expect(find.text('합계'), findsOneWidget);
      expect(find.text('414,900원'), findsOneWidget);
      expect(find.text('1회 평균'), findsOneWidget);
      expect(find.text('138,300원'), findsOneWidget);

      // 날짜(요일) · 목적 · 품목 수 · 금액
      expect(find.text('2026.07.24 (금)'), findsOneWidget);
      expect(find.text('주말 부케 3건 대비 · 3개 품목'), findsOneWidget);
      expect(find.text('262,000원'), findsOneWidget);
      expect(find.text('2026.07.17 (금)'), findsOneWidget);
      expect(find.text('42,500원'), findsOneWidget);
      expect(find.text('2026.07.11 (토)'), findsOneWidget);
      expect(find.text('110,400원'), findsOneWidget);
    });

    testWidgets('🔴 최신순으로 늘어놓는다', (t) async {
      // 일부러 뒤섞어 넣어도 날짜 순으로 와야 한다.
      final shuffled = [saved()[2], saved()[0], saved()[1]];
      await pumpTallBudget(t, SavedListsDsScreen(lists: shuffled));

      final ys = t
          .widgetList<Text>(find.byType(Text))
          .map((e) => e.data ?? '')
          .where((e) => e.startsWith('2026.'))
          .toList();
      expect(ys, ['2026.07.24 (금)', '2026.07.17 (금)', '2026.07.11 (토)']);
    });

    testWidgets('🔴 펼치면 품목별 수량·단가·금액이 보인다', (t) async {
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved(), openId: 'a'));

      expect(find.text('장미(레드)'), findsOneWidget);
      expect(find.text('20단 · 8,000원'), findsOneWidget);
      expect(find.text('160,000원'), findsOneWidget);
      expect(find.text('거베라'), findsOneWidget);
      expect(find.text('15단 · 6,000원'), findsOneWidget);
      expect(find.text('90,000원'), findsOneWidget);
      // 단위가 '개' 인 줄도 그대로 쓴다.
      expect(find.text('5개 · 2,400원'), findsOneWidget);
      expect(find.text('12,000원'), findsOneWidget);

      expect(find.text('이 리스트로 새로 만들기'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('🔴 접었다 폈다 할 수 있다', (t) async {
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved(), openId: 'a'));
      expect(find.text('이 리스트로 새로 만들기'), findsOneWidget);

      // 머리글을 누르면 접힌다.
      await t.tap(find.text('2026.07.24 (금)'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('이 리스트로 새로 만들기'), findsNothing);
      expect(find.text('20단 · 8,000원'), findsNothing);
      // 금액은 접혀도 보인다.
      expect(find.text('262,000원'), findsOneWidget);

      await t.tap(find.text('2026.07.24 (금)'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('이 리스트로 새로 만들기'), findsOneWidget);
    });

    testWidgets('🔴 저장하고 온 리스트가 펼쳐진 채로 있다', (t) async {
      // 가운데 것을 지목해도 그게 펼쳐져야 한다.
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved(), openId: 'b'));
      expect(find.text('소국'), findsOneWidget);
      expect(find.text('10단 · 2,500원'), findsOneWidget);
      // 다른 것은 접혀 있다.
      expect(find.text('20단 · 8,000원'), findsNothing);
    });

    testWidgets('🔴 메모 리스트는 "메모 리스트 · ○줄" 이고 금액 칸이 비어 있다', (t) async {
      final lists = [
        plist('memo', DateTime(2026, 7, 20), memo: '[ ] 화병\n[x] 리본'),
        ...saved(),
      ];
      await pumpTallBudget(t, SavedListsDsScreen(lists: lists, openId: 'memo'));

      expect(find.text('메모 리스트 · 2줄'), findsOneWidget);
      // 🔴 #189 에서 빈 안내 대신 **메모 줄 미리보기**를 보여 준다.
      expect(find.text('화병'), findsOneWidget);
      expect(find.text('리본'), findsOneWidget);
      // 🔴 #190 에서 '메모장 열기' 가 '시장에서 열기' 로 통일됐다.
      expect(find.text('메모장 열기'), findsNothing);
      expect(find.text('시장에서 열기'), findsOneWidget);
      // 금액이 0원으로 적히면 안 된다. 비워야 한다.
      expect(find.text('0원'), findsNothing);
      // 합계·평균은 그대로.
      expect(find.text('414,900원'), findsOneWidget);
      expect(find.text('138,300원'), findsOneWidget);
      expect(find.text('4건'), findsOneWidget);
    });

    testWidgets('🔴 삭제는 확인을 받고서 지운다', (t) async {
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved(), openId: 'a'));
      expect(find.text('2026.07.24 (금)'), findsOneWidget);

      await t.tap(find.text('삭제'));
      await t.pump(const Duration(milliseconds: 300));
      // 확인 창이 뜬다. 아직 안 지웠다.
      expect(find.text('이 사입 리스트를 지울까요?'), findsOneWidget);
      expect(find.text('2026.07.24 (금)'), findsOneWidget);

      await t.tap(find.text('취소'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('2026.07.24 (금)'), findsOneWidget,
          reason: '취소했는데 지워졌다');

      await t.tap(find.text('삭제').first);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('삭제').last);
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text('2026.07.24 (금)'), findsNothing);
      // 요약도 같이 줄어든다. 414,900 - 262,000 = 152,900
      expect(find.text('2건'), findsOneWidget);
      expect(find.text('152,900원'), findsOneWidget);
    });

    testWidgets('🔴 저장된 게 없으면 문구 하나 · 버튼 하나 · 링크 하나 (#188)', (t) async {
      await pumpTallBudget(t, const SavedListsDsScreen(lists: []));
      expect(find.text('아직 저장한 사입 리스트가 없어요'), findsOneWidget);
      expect(find.text('새 사입 리스트 만들기'), findsOneWidget);
      expect(find.text('메모로 빠르게 적기'), findsOneWidget);
      // 옛 문구·옛 버튼은 사라졌다.
      expect(find.text('예산 검토로 리스트 만들기'), findsNothing);
      expect(find.textContaining('여기에 쌓여요'), findsNothing);
      // 버튼은 **하나뿐**이다. 링크는 버튼이 아니다.
      expect(find.byType(FnPrimaryButton), findsOneWidget);
      // 빈 요약 카드를 그리지 않는다.
      expect(find.text('저장된 리스트'), findsNothing);
    });

    testWidgets('🔴 화면 좌우 여백이 기준(24)과 같다', (t) async {
      await pumpTallBudget(t, SavedListsDsScreen(lists: saved()));
      final list = t.widget<ListView>(find.byType(ListView).first);
      expect(list.padding,
          const EdgeInsets.fromLTRB(FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl));
    });
  });

  group('예산 검토 — 입력칸 개선 (#187)', () {
    testWidgets('🔴 품목·수량·단가 칸이 높이 48 · 글자 M 이다 (#189)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 🔴 #187 에서 56·L 로 키웠다가 #189 에서 기본값으로 되돌렸다.
      expect(FnDs.inputBigH, 48.0);
      expect(FnDs.inputBigFont, FnDs.fontM);
      // 기본 입력칸과 **같은 값**이다. 둘이 어긋나면 화면마다 달라 보인다.
      expect(FnDs.inputBigH, FnDs.inputH);
      expect(FnDs.inputBigFont, FnDs.inputFont);

      // 48 짜리 상자가 실제로 쓰였는지.
      final boxes = t
          .widgetList<Container>(find.byType(Container))
          .where((e) => e.constraints?.maxHeight == FnDs.inputBigH);
      expect(boxes, isNotEmpty);
    });

    testWidgets('🔴 수량 칸에 － ＋ 버튼이 없다 (#189)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 🔴 #188 에서 넣었다가 #189 에서 뺐다. 사장님 지시: "－ / ＋ 버튼은
      //    빼기 (왼쪽에 빈 칸으로 보이는 문제도 같이 없어짐)".
      expect(find.byIcon(Icons.remove_rounded), findsNothing);
      // '항목 추가' 의 ＋ 는 남아 있어야 한다. 수량 옆의 ＋ 만 뺐다.
      expect(find.text('항목 추가'), findsOneWidget);

      // 수량은 칸에 직접 적는다.
      await t.enterText(fieldFor('수량'), '20');
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<TextField>(fieldFor('수량')).controller!.text, '20');
    });

    testWidgets('🔴 수량 칸은 숫자만 받고 단위가 오른쪽에 고정이다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      await t.enterText(fieldFor('수량'), '20단abc');
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<TextField>(fieldFor('수량')).controller!.text, '20');

      // 기본 단위는 '단'.
      expect(FnUnits.fallback, '단');
      expect(find.text('단'), findsWidgets);
    });

    testWidgets('🔴 단가 칸은 숫자만 받고 쉼표가 자동으로 붙는다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      await t.enterText(fieldFor('단가'), '8000');
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<TextField>(fieldFor('단가')).controller!.text, '8,000');

      await t.enterText(fieldFor('단가'), '1234567원');
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<TextField>(fieldFor('단가')).controller!.text, '1,234,567');

      // '원' 은 칸 밖에 고정으로 붙어 있다.
      expect(find.text('원'), findsWidgets);
    });

    testWidgets('🔴 영수증 단위가 "개" 면 수량 칸도 "개" 가 된다', (t) async {
      final rs = [
        ReceiptModel(
          id: 'p',
          date: DateTime(2026, 7, 20),
          storeName: '화람원예',
          rawOcrText: '',
          createdAt: DateTime(2026, 7, 20),
          totalAmount: 24000,
          items: [
            FlowerItem(name: '수국', quantity: 10, unitPrice: 2400, unit: '개'),
          ],
        ),
      ];
      final book = PriceBook.fromReceipts(rs);
      expect(FnUnits.forItem('수국', book), '개');
      // 영수증에 없는 품목은 기본값.
      expect(FnUnits.forItem('장미', book), '단');

      await pumpTallBudget(
          t, GuideBudgetDsScreen(priceBook: book, frequent: const []));
      await t.tap(fieldFor('품목명'));
      await t.enterText(fieldFor('품목명'), '수국');
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('수국').last);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('개'), findsWidgets);
      expect(t.widget<TextField>(fieldFor('단가')).controller!.text, '2,400');
    });

    testWidgets('🔴 단위가 섞인 품목은 단가를 자동으로 채우지 않는다', (t) async {
      // 🔴 장미를 단(8,000)과 송이(800)로 둘 다 샀다. 어느 쪽인지 모르는
      //    채로 채우면 예산이 열 배 틀어진다.
      final rs = [
        ReceiptModel(
          id: 'a',
          date: DateTime(2026, 7, 10),
          storeName: '대한꽃도매',
          rawOcrText: '',
          createdAt: DateTime(2026, 7, 10),
          totalAmount: 80000,
          items: [
            FlowerItem(name: '장미', quantity: 10, unitPrice: 8000, unit: '단'),
          ],
        ),
        ReceiptModel(
          id: 'b',
          date: DateTime(2026, 7, 20),
          storeName: '대한꽃도매',
          rawOcrText: '',
          createdAt: DateTime(2026, 7, 20),
          totalAmount: 8000,
          items: [
            FlowerItem(name: '장미', quantity: 10, unitPrice: 800, unit: '송이'),
          ],
        ),
      ];
      final book = PriceBook.fromReceipts(rs);
      expect(book.lookup('장미')!.mixedUnit, isTrue);

      await pumpTallBudget(
          t, GuideBudgetDsScreen(priceBook: book, frequent: const []));
      await t.tap(fieldFor('품목명'));
      await t.enterText(fieldFor('품목명'), '장미');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('단위가 섞여 있어요'), findsOneWidget);

      await t.tap(find.text('장미').last);
      await t.pump(const Duration(milliseconds: 300));

      // 이름은 채우되 단가는 비워 둔다.
      expect(t.widget<TextField>(fieldFor('품목명')).controller!.text, '장미');
      expect(t.widget<TextField>(fieldFor('단가')).controller!.text, '');
    });

    testWidgets('단위가 하나뿐이면 섞였다고 보지 않는다', (t) async {
      final rs = [
        ReceiptModel(
          id: 'a',
          date: DateTime(2026, 7, 10),
          storeName: '대한꽃도매',
          rawOcrText: '',
          createdAt: DateTime(2026, 7, 10),
          totalAmount: 80000,
          items: [
            FlowerItem(name: '장미', quantity: 10, unitPrice: 8000, unit: '단'),
            FlowerItem(name: '장미', quantity: 5, unitPrice: 8200, unit: '단'),
          ],
        ),
      ];
      expect(PriceBook.fromReceipts(rs).lookup('장미')!.mixedUnit, isFalse);
    });
  });


  /// 영수증 몇 장. #188 블록에서 쓴다. (#179 그룹 안의 것과 같은 값)
  List<ReceiptModel> rcpts() => [
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

  // ────────────────────────────────────────────────────────────
  // #188 — 저장 버그 · 입력 칸 정리
  // ────────────────────────────────────────────────────────────

  group('사입 리스트 저장 버그 (#188)', () {
    test('🔴 앱이 뜰 때 사입 리스트 상자를 연다', () {
      // 🔴 이게 빠져서 생긴 버그다. `PurchaseListService.init()` 을 아무도
      //    안 불러서 상자가 닫힌 채였고, `touch()` 는 첫 줄
      //    `if (!_ready) return;` 에서 조용히 끝났다. 저장은 안 됐는데
      //    화면은 넘어갔고, 저장된 사입 리스트는 늘 비어 있었다.
      final main = _read('lib/main.dart');
      expect(main.contains("import 'services/purchase_list_service.dart';"),
          isTrue);
      expect(main.contains('PurchaseListService.instance.init()'), isTrue);
    });

    test('🔴 저장은 자동 저장(4초)을 기다리지 않는다', () {
      final svc = _read('lib/services/purchase_list_service.dart');
      // 성공·실패를 돌려주는 즉시 저장 길이 있어야 한다.
      expect(svc.contains('Future<bool> saveNow('), isTrue);
      // 상자가 닫혀 있으면 열어 본다. 조용히 포기하지 않는다.
      expect(svc.contains('await _openFor(AuthService.instance.uid);'), isTrue);
      // 자동 저장은 4초 그대로 둔다 (메모장이 쓴다).
      expect(svc.contains('Duration(seconds: 4)'), isTrue);
    });

    test('🔴 화면은 저장이 끝난 뒤에만 이동한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains('await PurchaseListService.instance.saveNow(list)'),
          isTrue);
      // 실패하면 안내만 하고 돌아간다.
      expect(src.contains("'저장하지 못했어요. 다시 눌러 주세요'"), isTrue);
      // 성공하면 짧은 안내 뒤에 이동한다.
      expect(src.contains("showFnToast(context, '저장했어요'"), isTrue);
      expect(src.contains('SavedListsDsScreen(openId: list.id)'), isTrue);
      // 🔴 옛 길(touch + 기다리지 않는 flush)로 저장하지 않는다.
      expect(src.contains('PurchaseListService.instance.touch(list)'), isFalse);
    });

    testWidgets('🔴 품목이 없으면 버튼이 흐리고 안내가 뜬다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      final btn = t.widget<FnPrimaryButton>(find.byType(FnPrimaryButton));
      expect(btn.onTap, isNull, reason: '품목이 없는데 눌린다');
      expect(find.text('살 꽃을 한 가지 이상 적어 주세요'), findsWidgets);

      // 한 줄 적으면 살아난다.
      await t.enterText(fieldFor('품목명'), '장미');
      await t.enterText(fieldFor('수량'), '20');
      await t.enterText(fieldFor('단가'), '8000');
      await t.pump(const Duration(milliseconds: 200));

      expect(t.widget<FnPrimaryButton>(find.byType(FnPrimaryButton)).onTap,
          isNotNull);
    });

    testWidgets('🔴 품목 2개를 적고 저장하면 리스트 맨 위에 펼쳐져 보인다', (t) async {
      // 🔴 사장님이 직접 확인해 달라고 하신 흐름이다(#188).
      //    예산 검토에서 적은 두 품목이 그대로 저장돼, 저장된 사입
      //    리스트 **맨 위에 펼쳐진 채** 보여야 한다.
      final list = PurchaseList(
        id: 'new',
        date: DateTime(2026, 7, 24),
        purpose: '주말 부케 3건 대비',
        items: [pi('장미(레드)', 20, 8000), pi('거베라', 15, 6000)],
        budgetCap: 400000,
        createdAt: DateTime(2026, 7, 23),
        updatedAt: DateTime(2026, 7, 23),
      );
      // 날짜가 더 오래된 리스트가 하나 더 있어도 방금 것이 위다.
      await pumpTallBudget(
        t,
        SavedListsDsScreen(openId: 'new', lists: [
          plist('old', DateTime(2026, 7, 11), purpose: '정기 매장 진열',
              items: [pi('안개', 12, 2800)]),
          list,
        ]),
      );

      // 맨 위 = 날짜가 가장 최근인 것.
      expect(find.text('2026.07.24 (금)'), findsOneWidget);
      // 펼쳐져 있다 — 품목 줄이 보인다.
      expect(find.text('장미(레드)'), findsOneWidget);
      expect(find.text('거베라'), findsOneWidget);
      expect(find.text('20단 · 8,000원'), findsOneWidget);
      // 20×8,000 + 15×6,000 = 160,000 + 90,000 = 250,000
      expect(find.text('250,000원'), findsWidgets);
      // 접혀 있는 쪽은 품목이 안 보인다.
      expect(find.text('안개'), findsNothing);
    });
  });

  group('예산 검토 — 입력 칸 한 줄 배치 (#188)', () {
    testWidgets('🔴 수량과 단가가 같은 줄에 나란히 있다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 두 칸을 같이 안고 있는 Row 가 있어야 한다.
      final row = find.ancestor(
        of: find.text('수량'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.last, matching: find.text('단가')),
        findsOneWidget,
        reason: '수량과 단가가 다른 줄에 있다',
      );

      // 수량 칸이 화면 절반쯤이다 (한 줄을 혼자 쓰지 않는다).
      final qtyBox = t.getSize(fieldFor('수량'));
      expect(qtyBox.width, lessThan(200));
    });

    testWidgets('🔴 칸 하나에 테두리가 하나다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 🔴 전역 테마(`app_theme.dart`)가 `enabledBorder` 를 깔아 둬서,
      //    `border: InputBorder.none` 만으로는 안 꺼졌다. 안쪽 TextField 는
      //    테두리를 하나도 그리지 않아야 한다 — 바깥 상자가 그린다.
      for (final label in ['품목명', '수량', '단가']) {
        final f = t.widget<TextField>(fieldFor(label));
        final d = f.decoration!;
        expect(d.border, InputBorder.none, reason: '$label border');
        expect(d.enabledBorder, InputBorder.none, reason: '$label enabled');
        expect(d.focusedBorder, InputBorder.none, reason: '$label focused');
        expect(d.filled, isFalse, reason: '$label filled');
      }
    });

    testWidgets('🔴 수량 칸 왼쪽에 빈 칸이 없다 (#189 － 뺀 뒤)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 버튼이 없으니 칸이 줄 왼쪽 끝에서 시작한다.
      expect(find.byIcon(Icons.remove_rounded), findsNothing);

      // 숫자는 단위 쪽(오른쪽)에 붙는다. 왼쪽에 빈 칸을 남기지 않는다.
      expect(t.widget<TextField>(fieldFor('수량')).textAlign, TextAlign.right);
      // 단가도 '원' 쪽에 붙는다.
      expect(t.widget<TextField>(fieldFor('단가')).textAlign, TextAlign.right);
    });

    testWidgets('🔴 삭제는 ✕ 다 (품목이 둘 이상일 때만)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      // 한 줄뿐이면 지울 수 없다.
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await t.tap(find.text('항목 추가'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
    });

    testWidgets('🔴 아래 작은 글씨가 왼쪽 기준 · 오른쪽 금액이다', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));

      // 직접 적으면 '직접 입력'.
      expect(find.text('직접 입력'), findsOneWidget);
      await t.enterText(fieldFor('수량'), '20');
      await t.enterText(fieldFor('단가'), '8000');
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('160,000원'), findsWidgets);
    });

    testWidgets('🔴 영수증에서 고르면 "○/○ 영수증 기준" 이 된다', (t) async {
      await pumpTallBudget(t, GuideBudgetDsScreen(
          priceBook: PriceBook.fromReceipts(rcpts()), frequent: const []));

      await t.tap(fieldFor('품목명'));
      await t.enterText(fieldFor('품목명'), '장미');
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('장미(레드)').last);
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('07/24 영수증 기준'), findsOneWidget);
      // 반쪽 폭에서 잘리지 않게 '1단 기준' 은 빼 뒀다.
      expect(find.textContaining('1단 기준'), findsNothing);
    });

    testWidgets('🔴 위쪽 "자주 산 품목" 칩은 그대로다', (t) async {
      final freq = PurchaseListService.frequentItems(rcpts(),
          now: DateTime(2026, 7, 25));
      await pumpTallBudget(t, GuideBudgetDsScreen(
          priceBook: PriceBook.fromReceipts(rcpts()), frequent: freq));
      expect(find.text('자주 산 품목'), findsOneWidget);
      expect(find.byType(FnPill), findsWidgets);
    });

    testWidgets('🔴 세 칸 글자가 모두 M 단계다 (#189)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      expect(FnDs.inputBigH, 48.0);
      expect(FnDs.inputBigFont, FnDs.fontM);

      for (final label in ['품목명', '수량', '단가']) {
        expect(t.widget<TextField>(fieldFor(label)).style!.fontSize,
            FnDs.fontM,
            reason: label);
      }
    });

    testWidgets('🔴 수량과 단가 칸 너비가 똑같다 (#189)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      final qty = t.getSize(fieldFor('수량'));
      final price = t.getSize(fieldFor('단가'));
      expect(qty.width, price.width, reason: '두 칸 너비가 다르다');
    });

    testWidgets('🔴 칸 하나에 테두리가 하나다 (세 칸 모두)', (t) async {
      await pumpTallBudget(
          t, const GuideBudgetDsScreen(priceBook: PriceBook.empty, frequent: []));
      // 🔴 안쪽 TextField 는 선을 하나도 안 그린다. 바깥 상자만 그린다.
      for (final label in ['품목명', '수량', '단가']) {
        final d = t.widget<TextField>(fieldFor(label)).decoration!;
        expect(d.border, InputBorder.none, reason: '$label border');
        expect(d.enabledBorder, InputBorder.none, reason: '$label enabled');
        expect(d.focusedBorder, InputBorder.none, reason: '$label focused');
        expect(d.filled, isFalse, reason: '$label filled');
      }
      // 🔴 품목 줄 **안에서만** 센다. 48 은 이제 기본 입력칸 높이라
      //    날짜·목적·한도 칸도 같은 값이다. 화면 전체를 세면 6 이 나온다.
      final boxes = t
          .widgetList<Container>(find.descendant(
            of: find.byType(FnBigItemLineRow),
            matching: find.byType(Container),
          ))
          .where((e) => e.constraints?.maxHeight == FnDs.inputBigH);
      expect(boxes.length, 3, reason: '품목명·수량·단가 세 칸이어야 한다');
    });
  });


  // ────────────────────────────────────────────────────────────
  // #189 — 메모장 → 저장된 사입 리스트
  // ────────────────────────────────────────────────────────────

  group('사입 메모장 — 저장 흐름 (#189)', () {
    String memoSrc2() => _read('lib/screens/ds/purchase_memo_ds_screen.dart');

    test('🔴 남의 리스트에 덮어쓰던 길(activeOne)을 끊었다', () {
      // 🔴 이게 버그였다. 가이드·칩으로 들어오면 `svc.activeOne`(아직 안
      //    끝난 가장 최근 리스트)을 집어 와서, 예산 검토에서 저장해 둔
      //    리스트에 메모가 덮어써졌다.
      final src = memoSrc2();
      expect(src.contains('svc.activeOne'), isFalse,
          reason: '아직 남의 리스트를 집어 온다');
      // 이제 자기만의 임시 작성분을 쓴다.
      expect(src.contains('svc.memoDraft()'), isTrue);
    });

    test('🔴 임시 작성분은 앱을 꺼도 남는다 (새 저장 구조 아님)', () {
      final svc = _read('lib/services/purchase_list_service.dart');
      // 🔴 기다리지 않는다. id 는 init() 에서 미리 읽어 둔다.
      expect(svc.contains('PurchaseList memoDraft()'), isTrue);
      expect(svc.contains('fn_memo_draft_id'), isTrue);
      expect(svc.contains('SharedPreferences'), isTrue);
      // 🔴 담기는 곳은 1단계와 같은 상자다. 새 타입을 만들지 않았다.
      expect(svc.contains('@HiveType'), isFalse);
    });

    test('🔴 저장 버튼은 예산 검토와 같은 saveNow() 를 쓴다', () {
      final src = memoSrc2();
      expect(src.contains('PurchaseListService.instance.saveNow(list)'), isTrue);
      expect(src.contains("'저장했어요'"), isTrue);
      expect(src.contains("'저장하지 못했어요. 다시 눌러 주세요'"), isTrue);
      // 저장이 끝난 뒤에만 옮긴다.
      expect(src.contains('SavedListsDsScreen(openId: list.id)'), isTrue);
    });

    test('🔴 저장이 끝나면 임시 작성분을 비운다', () {
      final src = memoSrc2();
      expect(src.contains('clearMemoDraft()'), isTrue);
      final svc = _read('lib/services/purchase_list_service.dart');
      expect(svc.contains('Future<void> clearMemoDraft()'), isTrue);
      // 🔴 저장에 실패하면 지우면 안 된다. 적은 게 날아간다.
      final fail = src.substring(
          src.indexOf("'저장하지 못했어요"), src.indexOf("showFnToast(context, '저장했어요'"));
      expect(fail.contains('clearMemoDraft'), isFalse,
          reason: '실패했는데 임시 작성분을 지운다');
    });

    test('🔴 임시 작성분은 저장된 목록에 섞이지 않는다', () {
      final svc = _read('lib/services/purchase_list_service.dart');
      expect(svc.contains('List<PurchaseList> get saved'), isTrue);
      expect(svc.contains('isMemoDraft('), isTrue);
      // 화면은 `all` 이 아니라 `saved` 를 본다.
      final saved = _read('lib/screens/ds/saved_lists_ds_screen.dart');
      expect(saved.contains('PurchaseListService.instance.saved'), isTrue);
      expect(saved.contains('PurchaseListService.instance.all'), isFalse);
    });

    testWidgets('🔴 새 메모장: 날짜·목적 칸과 "사입 리스트 저장" 버튼', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.pump(const Duration(milliseconds: 300));

      // 예산 검토와 같은 모양의 머리 카드.
      expect(find.text('사입 날짜'), findsOneWidget);
      expect(find.text('목적'), findsOneWidget);
      // 새 메모장이라 '사입 리스트 저장'.
      expect(find.text('사입 리스트 저장'), findsOneWidget);
      expect(find.text('저장'), findsNothing);
    });

    testWidgets('🔴 적은 게 없으면 버튼이 흐리고 안내가 뜬다', (t) async {
      await pumpTall(t, const PurchaseMemoDsScreen());
      await t.pump(const Duration(milliseconds: 300));

      final btn = t.widget<FnPrimaryButton>(find.byType(FnPrimaryButton));
      expect(btn.onTap, isNull, reason: '빈 메모장인데 눌린다');
      expect(find.text('한 줄 이상 적거나 그려 주세요'), findsOneWidget);

      // 한 줄 적으면 살아난다.
      await t.enterText(find.byType(TextField).last, '금요일 웨딩 부케 3개');
      await t.pump(const Duration(milliseconds: 300));
      expect(t.widget<FnPrimaryButton>(find.byType(FnPrimaryButton)).onTap,
          isNotNull);
      expect(find.text('한 줄 이상 적거나 그려 주세요'), findsNothing);
    });

    testWidgets('🔴 저장된 리스트를 고칠 때는 버튼이 "저장" 이고 머문다', (t) async {
      // listId 가 있으면 고치기 모드다.
      await pumpTall(t, const PurchaseMemoDsScreen(listId: 'x'));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('저장'), findsOneWidget);
      expect(find.text('사입 리스트 저장'), findsNothing);

      // 머무는 쪽은 소스로 본다 — 고치기 모드면 이동하지 않는다.
      final src = memoSrc2();
      expect(src.contains('if (_editing) {'), isTrue);
    });

    test('🔴 들어오는 곳 세 군데가 살아 있다 (가이드·홈 칩·저장된 리스트)', () {
      final guide = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(guide.contains("'memo' => const PurchaseMemoDsScreen()"), isTrue);
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('const PurchaseMemoDsScreen()'), isTrue);
      // 🔴 #189 에서 더해진 길 — 저장된 리스트는 **그 리스트의** 메모장을 연다.
      final saved = _read('lib/screens/ds/saved_lists_ds_screen.dart');
      expect(saved.contains('PurchaseMemoDsScreen(listId: e.id)'), isTrue);
    });
  });

  group('저장된 사입 리스트 — 메모 리스트 (#189)', () {
    /// 메모만 적어 둔 리스트 하나.
    PurchaseList memoList(String id, DateTime d, String memo) => PurchaseList(
          id: id,
          date: d,
          memo: memo,
          createdAt: d,
          updatedAt: d,
        );

    testWidgets('🔴 접힌 줄은 "메모 리스트 · ○줄" 이고 금액 칸이 비었다', (t) async {
      final memo = MemoText.encode(const [
        MemoLine(text: '금요일 웨딩 부케 3개'),
        MemoLine(text: '소국으로 대체', checked: true),
      ]);
      await pumpTallBudget(
        t,
        SavedListsDsScreen(
          openId: 'none',
          lists: [memoList('m', DateTime(2026, 7, 24), memo)],
        ),
      );

      expect(find.text('메모 리스트 · 2줄'), findsOneWidget);
      // 🔴 카드 머리에 금액을 적지 않는다. 0원이라고 쓰면 공짜로 샀다는
      //    말이 된다. (요약 카드의 합계·평균 0원은 맞는 값이다 —
      //    금액을 적은 리스트가 하나도 없으니까)
      final head = find.descendant(
        of: find.byType(ListView),
        matching: find.text('0원'),
      );
      expect(t.widgetList(head).length, 2,
          reason: '요약의 합계·평균 두 개뿐이어야 한다');
      expect(find.text('1건'), findsOneWidget);
    });

    testWidgets('🔴 펼치면 메모 3줄 미리보기 + "메모장 열기"', (t) async {
      final memo = MemoText.encode(const [
        MemoLine(text: '한 줄'),
        MemoLine(text: '두 줄', checked: true),
        MemoLine(text: '세 줄'),
        MemoLine(text: '네 줄'),
        MemoLine(text: '다섯 줄'),
      ]);
      await pumpTallBudget(
        t,
        SavedListsDsScreen(
          openId: 'm',
          lists: [memoList('m', DateTime(2026, 7, 24), memo)],
        ),
      );

      // 세 줄까지만 보여 준다.
      expect(find.text('한 줄'), findsOneWidget);
      expect(find.text('두 줄'), findsOneWidget);
      expect(find.text('세 줄'), findsOneWidget);
      expect(find.text('네 줄'), findsNothing);
      // 나머지는 숫자로 알린다.
      expect(find.text('외 2줄'), findsOneWidget);

      // 🔴 #190 에서 '시장에서 열기' 로 통일됐다.
      expect(find.text('시장에서 열기'), findsOneWidget);
      expect(find.text('메모장 열기'), findsNothing);
      // 메모 리스트에는 '이 리스트로 새로 만들기' 가 없다 (복사할 품목이 없다).
      expect(find.text('이 리스트로 새로 만들기'), findsNothing);
    });

    testWidgets('🔴 품목이 있는 리스트는 그대로 품목 줄을 보여 준다', (t) async {
      await pumpTallBudget(
        t,
        SavedListsDsScreen(openId: 'a', lists: [
          plist('a', DateTime(2026, 7, 24), purpose: '주말 부케', items: [
            pi('장미(레드)', 20, 8000),
          ]),
        ]),
      );
      expect(find.text('장미(레드)'), findsOneWidget);
      expect(find.text('이 리스트로 새로 만들기'), findsOneWidget);
      // 🔴 #190 — 예산 검토로 만든 리스트도 시장에서 열 수 있다.
      expect(find.text('시장에서 열기'), findsOneWidget);
      expect(find.text('메모장 열기'), findsNothing);
    });

    test('🔴 메모 리스트는 금액 계산에서 빠진다 (검산 그대로)', () {
      // 메모 리스트를 섞어도 합계·평균이 안 바뀐다.
      final lists = [
        ...saved(),
        memoList('m', DateTime(2026, 7, 20), '[ ] 한 줄'),
      ];
      final sum = PurchaseListService.summarize(lists);
      expect(sum.count, 4);
      expect(sum.total, 414900);
      expect(sum.average, 138300);
    });
  });

  group('클라우드 동기화 — 다음 작업 (#189)', () {
    test('🔴 "PC↔폰 동기화 확인 필요" 가 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('PC↔폰 동기화 확인 필요'), isTrue);
    });
  });


  // ────────────────────────────────────────────────────────────
  // #190 — 시장 체크 연결
  // ────────────────────────────────────────────────────────────

  group('시장 체크 — 셈 (#190)', () {
    test('🔴 체크 개수는 품목 + 메모 줄을 합친다', () {
      // 품목 3개(1개 체크) + 메모 2줄(1줄 체크) = 2/5
      final l = plist('a', DateTime(2026, 7, 24), items: [
        pi('장미(레드)', 20, 8000)..checked = true,
        pi('거베라', 15, 6000),
        pi('수국', 5, 2400, unit: '개'),
      ], memo: '[x] 화병\n[ ] 리본');

      expect(l.checkTotal, 5);
      expect(l.checkDone, 2);
      expect(l.checkLabel, '2/5');
    });

    test('🔴 품목만 있어도, 메모만 있어도 센다', () {
      final onlyItems = plist('b', DateTime(2026, 7, 24),
          items: [pi('장미', 10, 8000)..checked = true]);
      expect(onlyItems.checkLabel, '1/1');

      final onlyMemo =
          plist('c', DateTime(2026, 7, 24), memo: '[ ] 가\n[ ] 나');
      expect(onlyMemo.checkLabel, '0/2');
    });

    test('🔴 셀 게 없으면 빈 글자다 (0/0 이라고 안 쓴다)', () {
      expect(plist('d', DateTime(2026, 7, 24)).checkLabel, '');
    });

    test('🔴 빈 메모 줄은 세지 않는다', () {
      final l = plist('e', DateTime(2026, 7, 24), memo: '[ ] 가\n[ ] \n[ ] 나');
      expect(l.checkTotal, 2);
    });
  });

  group('저장된 사입 리스트 — 시장에서 열기 (#190)', () {
    testWidgets('🔴 예산 리스트도 "시장에서 열기" 가 있다', (t) async {
      await pumpTallBudget(
        t,
        SavedListsDsScreen(openId: 'a', lists: [
          plist('a', DateTime(2026, 7, 24), purpose: '주말 부케', items: [
            pi('장미(레드)', 20, 8000),
            pi('거베라', 15, 6000),
          ]),
        ]),
      );
      // 🔴 예산 검토로 만든 리스트도 시장에서 체크할 수 있어야 한다.
      expect(find.text('시장에서 열기'), findsOneWidget);
      // 기존 버튼도 그대로.
      expect(find.text('이 리스트로 새로 만들기'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('🔴 메모 리스트도 같은 버튼이다 (이름 통일)', (t) async {
      await pumpTallBudget(
        t,
        SavedListsDsScreen(
          openId: 'm',
          lists: [plist('m', DateTime(2026, 7, 24), memo: '[ ] 화병')],
        ),
      );
      expect(find.text('시장에서 열기'), findsOneWidget);
      expect(find.text('메모장 열기'), findsNothing);
    });

    testWidgets('🔴 카드에 "○/○ 구매" 가 보인다', (t) async {
      await pumpTallBudget(
        t,
        SavedListsDsScreen(openId: 'none', lists: [
          plist('a', DateTime(2026, 7, 24), purpose: '주말 부케', items: [
            pi('장미(레드)', 20, 8000)..checked = true,
            pi('거베라', 15, 6000),
          ], memo: '[ ] 화병'),
        ]),
      );
      // 품목 2(1체크) + 메모 1(0체크) = 1/3
      expect(find.text('1/3 구매'), findsOneWidget);
    });

    testWidgets('🔴 셀 게 없으면 "구매" 줄을 안 그린다', (t) async {
      await pumpTallBudget(
        t,
        SavedListsDsScreen(
          openId: 'none',
          lists: [plist('a', DateTime(2026, 7, 24), purpose: '빈 것')],
        ),
      );
      expect(find.textContaining('구매'), findsNothing);
    });

    test('🔴 그 리스트의 메모장을 연다 (새 메모장이 아니다)', () {
      final src = _read('lib/screens/ds/saved_lists_ds_screen.dart');
      // 🔴 `listId` 를 안 넘기면 임시 작성분이 열려 품목이 안 보인다.
      expect(src.contains('PurchaseMemoDsScreen(listId: e.id)'), isTrue);
    });
  });

  group('저장된 리스트의 메모장 — 사야 할 품목 (#190)', () {
    /// 품목 2개 + 메모 1줄이 든 리스트를 그대로 띄운다.
    Widget memoFor(List<PurchaseItem> items, {String memo = ''}) =>
        PurchaseMemoDsScreen(
          listId: 'x',
          list: plist('x', DateTime(2026, 7, 24),
              purpose: '주말 부케', items: items, memo: memo),
        );

    testWidgets('🔴 품목이 품목명·수량·단위로 보인다', (t) async {
      await pumpTall(
        t,
        memoFor([
          pi('장미(레드)', 20, 8000),
          pi('수국', 5, 2400, unit: '개'),
        ]),
      );

      expect(find.text('사야 할 품목'), findsOneWidget);
      expect(find.text('장미(레드)'), findsOneWidget);
      expect(find.text('20단'), findsOneWidget);
      expect(find.text('수국'), findsOneWidget);
      // 🔴 단위는 영수증 것을 따른다. 늘 '단' 이면 화분도 20단이 된다.
      expect(find.text('5개'), findsOneWidget);
    });

    testWidgets('🔴 체크하면 코랄 ✓ + 가운데줄, 그 품목에 저장된다', (t) async {
      final list = plist('x', DateTime(2026, 7, 24),
          items: [pi('장미(레드)', 20, 8000)]);
      await pumpTall(
          t, PurchaseMemoDsScreen(listId: 'x', list: list));

      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(list.items.first.checked, isFalse);

      await t.tap(find.text('장미(레드)'));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // 🔴 체크는 **그 품목에** 담긴다. 메모 글로 옮겨 적지 않는다.
      expect(list.items.first.checked, isTrue);

      final name = t.widget<Text>(find.text('장미(레드)'));
      expect(name.style!.decoration, TextDecoration.lineThrough);
      expect(name.style!.color, FnDs.sub);

      // 다시 누르면 풀린다.
      await t.tap(find.text('장미(레드)'));
      await t.pump(const Duration(milliseconds: 300));
      expect(list.items.first.checked, isFalse);
    });

    testWidgets('🔴 품목이 없는 메모 리스트는 이 목록을 숨긴다', (t) async {
      await pumpTall(t, memoFor(const [], memo: '[ ] 화병'));
      expect(find.text('사야 할 품목'), findsNothing);
      // 자유 메모는 그대로 보인다.
      expect(find.text('화병'), findsOneWidget);
    });

    testWidgets('🔴 품목 아래에 자유 메모 줄이 이어진다', (t) async {
      await pumpTall(
          t, memoFor([pi('장미(레드)', 20, 8000)], memo: '[ ] 화병도 사기'));
      expect(find.text('사야 할 품목'), findsOneWidget);
      expect(find.text('장미(레드)'), findsOneWidget);
      // 자유 메모는 글칸이라 TextField 로 들어 있다.
      expect(find.text('화병도 사기'), findsOneWidget);
    });

    testWidgets('🔴 탭 개수가 품목 + 메모 줄 합계다', (t) async {
      await pumpTall(
        t,
        memoFor([
          pi('장미(레드)', 20, 8000)..checked = true,
          pi('거베라', 15, 6000),
          pi('수국', 5, 2400, unit: '개'),
        ], memo: '[x] 화병\n[ ] 리본'),
      );
      // 품목 3(1체크) + 메모 2(1체크) = 2/5
      expect(find.text('메모 2/5'), findsOneWidget);
    });

    testWidgets('🔴 품목을 체크하면 탭 숫자도 같이 오른다', (t) async {
      await pumpTall(
          t, memoFor([pi('장미(레드)', 20, 8000), pi('거베라', 15, 6000)]));
      expect(find.text('메모 0/2'), findsOneWidget);

      await t.tap(find.text('장미(레드)'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('메모 1/2'), findsOneWidget);
    });

    test('🔴 품목을 복사하지 않고 리스트 것을 그대로 가리킨다', () {
      // 🔴 복사하면 예산 검토에서 품목을 고쳐도 메모장이 옛 품목을 든다.
      //    사장님 지시(#190): "예산 검토에서 품목을 고치면 여기도 같이 바뀜".
      final src = _read('lib/screens/ds/purchase_memo_ds_screen.dart');
      expect(src.contains('List<PurchaseItem> get _items => _list?.items'),
          isTrue);
      expect(src.contains('_items = _list!.items.map('), isFalse);
    });

    test('🔴 새 메모장(임시 작성분) 길은 그대로다', () {
      final src = _read('lib/screens/ds/purchase_memo_ds_screen.dart');
      expect(src.contains('svc.memoDraft()'), isTrue);
      expect(src.contains('clearMemoDraft()'), isTrue);
      // 품목이 없으면 머리를 숨기므로 빈 메모장 모양은 안 바뀐다.
      expect(src.contains('bool get _showItems => _items.isNotEmpty;'), isTrue);
    });
  });

  group('저장된 사입 리스트 — 입구 (#190)', () {
    test('🔴 가이드 카드와 홈 칩이 저장된 사입 리스트로 간다', () {
      final guide = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(guide.contains("'saved' => const SavedListsDsScreen()"), isTrue);

      // 🔴 홈 바로가기 칩 '사입 리스트' — 전에는 가이드 목록으로 떨어졌다.
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains("case 'list':"), isTrue);
      expect(home.contains('const SavedListsDsScreen()'), isTrue);
    });

    test('🔴 사입 리스트 진행 상태가 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('시장 체크 연결'), isTrue);
    });
  });

  group('저장된 사입 리스트 — 소스 계약 (#187)', () {
    String savedSrc() => _read('lib/screens/ds/saved_lists_ds_screen.dart');

    test('🔴 1단계 저장 구조를 그대로 쓴다 (새로 만들지 않았다)', () {
      final src = savedSrc();
      expect(src.contains('PurchaseListService'), isTrue);
      expect(src.contains('PurchaseList'), isTrue);
      expect(src.contains('Hive.openBox'), isFalse);
      expect(src.contains('@HiveType'), isFalse);
    });

    test('🔴 셈을 화면에서 하지 않고 서비스에 모았다', () {
      final src = savedSrc();
      expect(src.contains('PurchaseListService.summarize('), isTrue);
      // 화면에서 또 나누면 합계와 평균이 어긋난다.
      expect(src.contains('/ lists.length'), isFalse);
    });

    test('🔴 예산 검토에서 저장하면 이 화면으로 온다', () {
      final guide = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(guide.contains('SavedListsDsScreen(openId: list.id)'), isTrue);
      // 가이드 목록의 '저장된 사입 리스트' 도 연결됐다.
      expect(guide.contains("'saved' => const SavedListsDsScreen()"), isTrue);
    });

    test('🔴 "이 리스트로 새로 만들기" 는 날짜를 내일로, 단가를 다시 잡는다', () {
      final src = savedSrc();
      expect(src.contains('.duplicate('), isTrue);
      expect(src.contains('book.lookup('), isTrue);
      expect(src.contains('GuideBudgetDsScreen(initial: copy)'), isTrue);
      // 단위가 섞인 품목은 건너뛴다.
      expect(src.contains('if (e.mixedUnit) continue;'), isTrue);
    });

    test('🔴 삭제는 바로 하지 않고 확인을 받는다', () {
      expect(savedSrc().contains('showFnAlert('), isTrue);
    });

    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final src = savedSrc();
      expect(src.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(src.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 원가 계산기 입력칸은 건드리지 않았다', () {
      // 🔴 큰 칸은 예산 검토만 쓴다. 사장님 지시(#187):
      //    "다른 화면 디자인은 건드리지 마."
      final guide = _read('lib/screens/ds/insight_ds_screens.dart');
      final cost = guide.substring(
        guide.indexOf('class GuideCostDsScreen'),
        guide.indexOf('class GuideBudgetDsScreen'),
      );
      expect(cost.contains('FnBigItemLineRow'), isFalse);
      expect(cost.contains('FnBigField'), isFalse);
      // 예산 검토 쪽에는 들어가 있다.
      final budget = guide.substring(guide.indexOf('class _BudgetItemsCard'));
      expect(budget.contains('FnBigItemLineRow'), isTrue);
    });

    test('🔴 사입 메모장 연동은 다음 작업으로 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('저장된 사입 리스트'), isTrue);
      expect(doc.contains('메모장 연동'), isTrue);
    });
  });
}
