import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/services/monthly_insight.dart';
import 'package:flow_note/theme/fn_ds.dart';

String _read(String p) => File(p).readAsStringSync();

/// 월별 인사이트 — 사장님이 주신 **검산값**으로 셈을 확인한다. (#180 · #181)
///
/// ```
///   이전 달 1개월  7,140원 → 8,000원, 90단 ⇒ +12.0%, 절감 77,000원
///   이전 달 2개월  240만·264만 → 평균 252만, 기준 달 305만 ⇒ +21.0%
///   이전 달 없음   첫 달 리포트 — 절감 여지 없음
/// ```
void main() {
  // 오늘을 8월로 고정한다. 지난달(7월)에 영수증이 있으면 7월이 기준 달이다.
  final now = DateTime(2026, 8, 10);

  FlowerItem rose(int qty, double price) =>
      FlowerItem(name: '장미(레드)', quantity: qty, unitPrice: price, unit: '단');

  FlowerItem wrap(int qty, double price) =>
      FlowerItem(name: '포장지', quantity: qty, unitPrice: price, unit: '롤');

  ReceiptModel r(
    String id,
    DateTime date,
    List<FlowerItem> items, {
    required double total,
  }) =>
      ReceiptModel(
        id: id,
        date: date,
        storeName: '양재',
        rawOcrText: '',
        createdAt: date,
        totalAmount: total,
        items: items,
      );

  /// 🔴 검산 ① — 비교할 달이 **한 달뿐**일 때.
  ///
  /// 6월 장미 가중 평균 = (100단×7,000 + 50단×7,420) ÷ 150단
  ///                    = 1,071,000 ÷ 150 = **7,140원**
  /// 7월 장미 = 90단 × 8,000원
  List<ReceiptModel> oneMonth() => [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 3050000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
      ];

  /// 🔴 검산 ② — 비교할 달이 **두 달**일 때.
  ///
  /// 매입 평균 = (2,400,000 + 2,640,000) ÷ 2 = **2,520,000원**
  /// 기준 달 매입 = 3,050,000원 ⇒ +21.0%
  List<ReceiptModel> twoMonths() => [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 3050000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
        r('m5', DateTime(2026, 5, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2640000),
      ];

  /// 🔴 검산 ③ — 비교할 이전 달이 **없을** 때. 첫 달 리포트가 된다.
  List<ReceiptModel> firstOnly() => [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000), wrap(2, 55000)],
            total: 830000),
      ];

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

  /// 🔴 ListView 라 화면 밖 카드는 아예 안 그려진다. 길게 잡아야 한다.
  Future<void> pump(WidgetTester t, Widget w) =>
      pumpAt(t, w, const Size(390, 2400));

  group('월별 인사이트 — 검산 (사장님이 주신 값)', () {
    test('🔴 ① 이전 달 1개월: 7,140원 → 8,000원, 90단 ⇒ +12.0% · 절감 77,000원', () {
      final rep = MonthlyInsight.build(oneMonth(), now: now)!;
      expect(rep.compareMonths, 1);
      expect(rep.compareNote, '지난달과 비교했어요');

      final card = rep.cards.firstWhere((c) => c.kind == InsightKind.unitPrice);
      // 비율은 원래 값으로 갖고 있다가 보여줄 때만 다듬는다.
      expect(card.ratio, closeTo(860 / 7140, 1e-12));
      expect(card.deltaText, '+12.0%');

      // 절감 여지 = (8,000 − 7,140) × 90 = 77,400 → 1,000원 내림 = 77,000
      expect(card.saving, closeTo(77400, 1e-9));
      expect(InsightFmt.wonFloor(card.saving), '77,000원');

      // 🔴 단가는 원 단위 그대로 보여준다. 내리거나 올리지 않는다.
      expect(card.fromTo, '7,140원 → 8,000원');
      // 설명도 '지난달' 로 말해야 한다. 없는 3개월을 말하면 거짓말이 된다.
      expect(card.body.startsWith('지난달보다 12.0%'), isTrue);
    });

    test('🔴 ② 이전 달 2개월: 평균 2,520,000원 → 3,050,000원 ⇒ +21.0%', () {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      expect(rep.compareMonths, 2);
      expect(rep.compareNote, '지난 2개월 평균과 비교했어요');

      final card = rep.cards.firstWhere((c) => c.kind == InsightKind.spending);
      expect(card.ratio, closeTo(530000 / 2520000, 1e-12));
      expect(card.deltaText, '+21.0%');
      expect(card.title, '이번 달 지출 증가');
      // 지출 카드에는 절감 여지를 매기지 않는다. (사장님 지시)
      expect(card.saving, 0);
      // 오른쪽 문구는 비교 기간에 맞춘다.
      expect(card.fromTo, '지난 2개월 평균 252만원');
    });

    test('🔴 ③ 이전 달 없음: 첫 달 리포트 · 절감 여지 없음', () {
      final rep = MonthlyInsight.build(firstOnly(), now: now)!;
      expect(rep.isFirstMonth, isTrue);
      expect(rep.compareMonths, 0);
      expect(rep.totalSaving, 0);
      expect(rep.countOf(InsightKind.mix), 1);
      expect(rep.countOf(InsightKind.top), 1);
      // 비교 카드는 하나도 없어야 한다.
      expect(rep.countOf(InsightKind.unitPrice), 0);
      expect(rep.countOf(InsightKind.spending), 0);
      expect(rep.headTitle, '7월 리포트');
    });

    test('설명 문장이 배지와 같은 비율을 쓴다', () {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      final price = rep.cards.firstWhere((c) => c.kind == InsightKind.unitPrice);
      // 배지가 +12.0% 인데 글에 다른 숫자가 적히면 안 된다.
      expect(price.body.contains('12.0%'), isTrue);
      expect(price.body.endsWith('시즌 영향일 수 있어요.'), isTrue);
    });

    test('기준 달은 지난달이고 머리글 숫자가 맞다', () {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      expect(rep.month.year, 2026);
      expect(rep.month.month, 7);
      expect(rep.receiptCount, 1);
      expect(rep.monthTotal, 3050000);
      // 절감 여지 합계도 1,000원 내림.
      expect(InsightFmt.wonFloor(rep.totalSaving), '77,000원');
    });
  });

  group('월별 인사이트 — 기준 달 고르기 (#181)', () {
    test('🔴 지난달이 비어 있으면 이번 달(진행 중)을 본다', () {
      final rs = [
        r('cur', DateTime(2026, 8, 3), [rose(10, 8000)], total: 300000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.month.month, 8);
      expect(rep.inProgress, isTrue);
      // 달이 끝나지도 않았는데 지난달과 견주면 늘 "덜 썼다" 가 된다.
      expect(rep.isFirstMonth, isTrue);
      expect(rep.periodNote, '8월 1~10일 기준');
    });

    test('지난달에 영수증이 있으면 이번 달이 있어도 지난달을 본다', () {
      final rs = [
        ...oneMonth(),
        r('cur', DateTime(2026, 8, 3), [rose(10, 9000)], total: 300000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.month.month, 7);
      expect(rep.inProgress, isFalse);
      expect(rep.periodNote, isNull);
    });

    test('🔴 영수증이 하나도 없으면 리포트를 만들지 않는다', () {
      expect(MonthlyInsight.build(const [], now: now), isNull);
      // 넉 달보다 더 지난 영수증뿐이어도 마찬가지다.
      final old = [
        r('old', DateTime(2026, 1, 5), [rose(10, 7000)], total: 300000),
      ];
      expect(MonthlyInsight.build(old, now: now), isNull);
    });

    test('🔴 비교 3개월 중 빈 달이 있어도 리포트를 만든다 (규칙 바뀜 #181)', () {
      // 예전에는 빈 달이 있으면 아예 안 만들었다. 이제는 빈 달을 빼고 센다.
      // 5월을 뺐으니 비교는 4·6월 두 달, 평균은 ÷2 다.
      final rs = [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 3050000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
        r('m4', DateTime(2026, 4, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2640000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.compareMonths, 2);
      final spend = rep.cards.firstWhere((c) => c.kind == InsightKind.spending);
      expect(spend.deltaText, '+21.0%');
    });

    test('넉 달보다 더 지난 달은 비교에 넣지 않는다', () {
      final rs = [
        ...oneMonth(),
        // 3월은 기준 달(7월)에서 네 달 전이라 창 밖이다.
        r('m3', DateTime(2026, 3, 12), [rose(50, 7000)], total: 9000000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.compareMonths, 1);
    });
  });

  group('월별 인사이트 — 셈 규칙', () {
    test('🔴 단위가 다르면 섞지 않는다', () {
      // 같은 '장미(레드)' 라도 단과 송이는 다른 물건이다. 섞으면 평균이
      // 무너져 늘 급등으로 잡힌다.
      final rs = [
        r('base', DateTime(2026, 7, 10), [
          rose(90, 8000),
          FlowerItem(
              name: '장미(레드)', quantity: 10, unitPrice: 800, unit: '송이'),
        ], total: 3050000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      final card = rep.cards.firstWhere((c) => c.kind == InsightKind.unitPrice);
      // 송이가 섞였다면 평균이 내려가 비율이 달라진다.
      expect(card.deltaText, '+12.0%');
    });

    test('🔴 오인식으로 보이는 단가는 뺀다 (3배 이상 / 1/3 이하)', () {
      final rs = [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 3050000),
        // 71,400원 — 0 을 하나 더 읽은 것으로 본다.
        r('m6', DateTime(2026, 6, 12),
            [rose(100, 7000), rose(50, 7420), rose(1, 71400)],
            total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      final card = rep.cards.firstWhere((c) => c.kind == InsightKind.unitPrice);
      // 잘못 읽은 줄을 뺐으므로 검산값 그대로여야 한다.
      expect(card.deltaText, '+12.0%');
      expect(InsightFmt.wonFloor(card.saving), '77,000원');
    });

    test('🔴 비교가 두 달 이상이면 한 번만 산 품목은 카드로 만들지 않는다', () {
      final rs = [
        r('base', DateTime(2026, 7, 10),
            [FlowerItem(name: '작약', quantity: 10, unitPrice: 9000, unit: '단')],
            total: 2600000),
        r('m6', DateTime(2026, 6, 12),
            [FlowerItem(name: '작약', quantity: 10, unitPrice: 5000, unit: '단')],
            total: 2400000),
        r('m5', DateTime(2026, 5, 12), [rose(50, 7000)], total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      // 작약은 비교 기간에 1회뿐이라 우연일 수 있다.
      expect(rep.compareMonths, 2);
      expect(rep.countOf(InsightKind.unitPrice), 0);
    });

    test('🔴 비교가 한 달뿐이면 한 번 산 품목도 카드로 만든다 (#181)', () {
      // 한 달뿐인데 두 번을 요구하면 막 시작한 사장님껜 늘 빈 화면이 된다.
      final rs = [
        r('base', DateTime(2026, 7, 10),
            [FlowerItem(name: '작약', quantity: 10, unitPrice: 9000, unit: '단')],
            total: 2600000),
        r('m6', DateTime(2026, 6, 12),
            [FlowerItem(name: '작약', quantity: 10, unitPrice: 5000, unit: '단')],
            total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.compareMonths, 1);
      expect(rep.countOf(InsightKind.unitPrice), 1);
    });

    test('10% 미만이면 단가 카드를 만들지 않는다', () {
      final rs = [
        r('base', DateTime(2026, 7, 10), [rose(90, 7500)], total: 2600000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.countOf(InsightKind.unitPrice), 0);
    });

    test('15% 미만이면 지출 카드를 만들지 않는다', () {
      final rs = [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 2600000),
        r('m6', DateTime(2026, 6, 12), [rose(100, 7000), rose(50, 7420)],
            total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.countOf(InsightKind.spending), 0);
    });

    test('단가 카드는 절감 여지가 큰 순으로 최대 3개', () {
      FlowerItem f(String n, int q, double p) =>
          FlowerItem(name: n, quantity: q, unitPrice: p, unit: '단');
      // 네 품목이 다 올랐다. 가장 많이 아낄 수 있는 셋만 남아야 한다.
      final base = <FlowerItem>[
        f('가', 100, 2000), f('나', 100, 3000),
        f('다', 100, 4000), f('라', 100, 5000),
      ];
      final old = <FlowerItem>[
        f('가', 100, 1000), f('나', 100, 1500),
        f('다', 100, 2000), f('라', 100, 2500),
      ];
      final rs = [
        r('base', DateTime(2026, 7, 10), base, total: 1400000),
        r('m6', DateTime(2026, 6, 12), old, total: 2520000),
        r('m5', DateTime(2026, 5, 12), old, total: 2520000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      expect(rep.countOf(InsightKind.unitPrice), 3);
      expect(rep.cards.first.title.startsWith('라'), isTrue,
          reason: '가장 많이 아낄 수 있는 품목이 맨 위여야 한다');
    });

    test('🔴 한 영수증에 같은 품목이 두 줄이어도 한 번 산 것으로 센다', () {
      // 줄을 나눠 적었다고 "자주 산 품목" 이 되면 안 된다.
      final rs = [
        r('base', DateTime(2026, 7, 10), [rose(90, 8000)], total: 3050000),
        r('m6', DateTime(2026, 6, 12), [rose(50, 7000), rose(50, 7000)],
            total: 2400000),
        r('m5', DateTime(2026, 5, 12), [rose(50, 7000)], total: 2400000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      // 6월·5월 각각 1회 = 2회라 카드가 만들어진다.
      expect(rep.countOf(InsightKind.unitPrice), 1);
    });

    test('다듬기: % 는 반올림, 절감 여지는 1,000원 내림, 만원은 반올림', () {
      expect(InsightFmt.pct(0.120448), '12.0%');
      expect(InsightFmt.pct(0.210317), '21.0%');
      expect(InsightFmt.pct(0.1256), '12.6%');
      expect(InsightFmt.wonFloor(77400), '77,000원');
      expect(InsightFmt.wonFloor(999), '0원');
      expect(InsightFmt.won(7140), '7,140원');
      expect(InsightFmt.manwon(2520000), '252만원');
      expect(InsightFmt.manwon(5000), '5,000원');
    });
  });

  group('월별 인사이트 — 첫 달 리포트 (#181)', () {
    test('🔴 품목 비중 카드가 절화·부자재 비율을 말한다', () {
      // 장미 90단×8,000 = 720,000 / 포장지 2롤×55,000 = 110,000
      // 합계 830,000 → 절화 86.7% · 부자재 13.3%
      final rep = MonthlyInsight.build(firstOnly(), now: now)!;
      final mix = rep.cards.firstWhere((c) => c.kind == InsightKind.mix);
      expect(mix.badge, '비중');
      expect(mix.title, '이번 달 매입 구성');
      expect(mix.headline, '절화 86.7%');
      expect(mix.fromTo, '부자재 13.3%');
      // 절감 여지는 매기지 않는다.
      expect(mix.saving, 0);
    });

    test('🔴 많이 산 품목 카드가 금액 순으로 평균 단가·수량을 말한다', () {
      final rep = MonthlyInsight.build(firstOnly(), now: now)!;
      final top = rep.cards.firstWhere((c) => c.kind == InsightKind.top);
      expect(top.badge, '품목');
      expect(top.title, '많이 산 품목');
      expect(top.lines.first, '장미(레드) 90단 · 평균 8,000원');
      expect(top.lines[1], '포장지 2롤 · 평균 55,000원');
      expect(top.saving, 0);
    });

    test('품목 이름으로 품목군을 나눈다', () {
      expect(MonthlyInsight.groupOf('장미(레드)'), ItemGroup.cutFlower);
      expect(MonthlyInsight.groupOf('포장지'), ItemGroup.supply);
      expect(MonthlyInsight.groupOf('다육 화분'), ItemGroup.plant);
      expect(MonthlyInsight.groupOf('배송비'), ItemGroup.etc);
    });
  });

  group('월별 인사이트 — 화면', () {
    testWidgets('머리글과 카드가 시안대로다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));

      expect(find.text('월별 인사이트'), findsOneWidget);
      expect(find.text('2026년 7월 점검 결과'), findsOneWidget);
      expect(find.text('살펴볼 항목 2건'), findsOneWidget);
      expect(find.text('절감 여지 77,000원'), findsWidgets);
      expect(find.text('영수증 1매 · 매입 3,050,000원'), findsOneWidget);
      expect(find.text('지난 2개월 평균과 비교했어요'), findsOneWidget);

      expect(find.text('장미(레드) 단가 급등'), findsOneWidget);
      expect(find.text('+12.0%'), findsOneWidget);
      expect(find.text('7,140원 → 8,000원'), findsOneWidget);
      expect(find.text('이번 달 지출 증가'), findsOneWidget);
      expect(find.text('+21.0%'), findsOneWidget);
      expect(find.text('지난 2개월 평균 252만원'), findsOneWidget);

      expect(find.text('내 영수증 데이터를 기반으로 계산해요'), findsOneWidget);
    });

    testWidgets('🔴 칩 개수가 자동이고 0개 칩은 숨긴다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      expect(find.text('전체 2'), findsOneWidget);
      expect(find.text('단가 1'), findsOneWidget);
      expect(find.text('지출 1'), findsOneWidget);

      // 지출 카드가 없는 경우엔 '지출' 칩 자체가 없어야 한다.
      final onlyPrice = MonthlyInsightReport(
        month: DateTime(2026, 7),
        receiptCount: 1,
        monthTotal: 2600000,
        compareMonths: 2,
        cards:
            rep.cards.where((c) => c.kind == InsightKind.unitPrice).toList(),
      );
      await pump(t, InsightsDsScreen(report: onlyPrice));
      expect(find.text('전체 1'), findsOneWidget);
      expect(find.text('단가 1'), findsOneWidget);
      expect(find.textContaining('지출'), findsNothing);
    });

    testWidgets('칩을 누르면 그 종류만 남는다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      expect(find.text('이번 달 지출 증가'), findsOneWidget);

      await t.tap(find.text('단가 1'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('장미(레드) 단가 급등'), findsOneWidget);
      expect(find.text('이번 달 지출 증가'), findsNothing);
    });

    testWidgets('🔴 영수증이 없으면 안내와 스캔 버튼을 보여 준다', (t) async {
      await pump(t, const InsightsDsScreen(report: null));
      expect(find.text('영수증을 찍으면 이번 달 리포트를 만들어 드려요'), findsOneWidget);
      expect(find.text('영수증 스캔하기'), findsOneWidget);
    });

    testWidgets('🔴 살펴볼 항목이 없으면 그렇다고 말해 준다', (t) async {
      final empty = MonthlyInsightReport(
        month: DateTime(2026, 7),
        receiptCount: 5,
        monthTotal: 2400000,
        compareMonths: 3,
        cards: const [],
      );
      await pump(t, InsightsDsScreen(report: empty));
      expect(find.text('이번 달은 살펴볼 항목이 없어요. 잘 관리하고 계세요!'), findsOneWidget);
      expect(find.text('절감 여지 0원'), findsOneWidget);
    });

    testWidgets('🔴 첫 달 리포트는 같은 코랄 카드에 매입을 크게 적는다', (t) async {
      final rep = MonthlyInsight.build(firstOnly(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));

      expect(find.text('7월 리포트'), findsOneWidget);
      expect(find.text('매입 830,000원'), findsOneWidget);
      expect(find.text('영수증 1매 · 7월 한 달 분석이에요'), findsOneWidget);
      // 비교하지 않았으니 비교 문구가 있으면 안 된다.
      expect(find.textContaining('비교했어요'), findsNothing);

      // 카드 두 장.
      expect(find.text('이번 달 매입 구성'), findsOneWidget);
      expect(find.text('절화 86.7%'), findsOneWidget);
      expect(find.text('부자재 13.3%'), findsOneWidget);
      expect(find.text('많이 산 품목'), findsOneWidget);
      expect(find.text('장미(레드) 90단 · 평균 8,000원'), findsOneWidget);

      // 절감 여지는 어디에도 없다.
      expect(find.textContaining('절감 여지'), findsNothing);
      expect(find.text('다음 달 영수증이 쌓이면 지난달과 비교해 드려요'), findsOneWidget);
    });

    testWidgets('🔴 진행 중인 이번 달은 며칠까지인지 적는다', (t) async {
      final rs = [
        r('cur', DateTime(2026, 8, 3), [rose(10, 8000)], total: 300000),
      ];
      final rep = MonthlyInsight.build(rs, now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      expect(find.text('8월 1~10일 기준'), findsOneWidget);
    });

    testWidgets('🔴 지출 카드에는 절감 여지 줄이 없다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      await t.tap(find.text('지출 1'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('절감 여지'), findsOneWidget);
    });

    testWidgets('🔴 단가 카드에만 시세 흐름 바로가기가 있다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      // 단가 카드 한 장뿐이라 줄도 하나.
      expect(find.text('시세 흐름 보기'), findsOneWidget);

      // 지출만 남기면 바로가기 줄이 사라진다.
      await t.tap(find.text('지출 1'));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('시세 흐름 보기'), findsNothing);
    });

    testWidgets('🔴 카드가 기준 꾸밈(모서리 18·그림자·테두리 없음)을 쓴다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      final box = t.widget<Container>(find
          .ancestor(
            of: find.text('장미(레드) 단가 급등'),
            matching: find.byType(Container),
          )
          .first);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, FnDs.card);
      expect(deco.border, isNull,
          reason: '그림자와 테두리를 같이 쓰면 가장자리가 두 번 보인다');
      expect(deco.boxShadow, FnDs.cardShadow);
    });

    testWidgets('🔴 화면 좌우 여백이 기준(24)과 같다', (t) async {
      final rep = MonthlyInsight.build(twoMonths(), now: now)!;
      await pump(t, InsightsDsScreen(report: rep));
      final lv = t.widget<ListView>(find.byType(ListView).first);
      final pad = lv.padding! as EdgeInsets;
      expect(pad.left, FnDs.pagePad);
      expect(pad.right, FnDs.pagePad);
    });
  });

  group('월별 인사이트 — 소스 계약', () {
    String screenPart() {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      return src.substring(
        src.indexOf('class InsightsDsScreen'),
        src.indexOf('// compare'),
      );
    }

    test('🔴 셈을 화면에서 하지 않고 한 파일에 모았다', () {
      final part = screenPart();
      expect(part.contains('MonthlyInsight.build('), isTrue);
      // 화면에서 또 나누면 배지와 설명의 숫자가 어긋난다.
      expect(part.contains('/ cmp'), isFalse);
    });

    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final part = screenPart();
      expect(part.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(part.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 단가 카드 바로가기가 계절 시세 화면으로 간다', () {
      final part = screenPart();
      expect(part.contains('SeasonDsScreen()'), isTrue);
      // 갈 화면이 없는 바로가기는 아직 그리지 않는다.
      for (final gone in ['단가 비교하기', '품목 분석 보기', '지출 추이 보기']) {
        expect(part.contains(gone), isFalse, reason: '$gone 링크가 아직 있다');
      }
    });

    test('🔴 홈 버튼이 이 화면으로 가고, 달도 리포트와 같다', () {
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('InsightsDsScreen()'), isTrue);
      expect(home.contains('맞춤 사입 리포트 보기'), isTrue);
      // 버튼 글자의 달과 리포트의 기준 달이 같아야 한다.
      expect(home.contains('MonthlyInsight.baseMonth('), isTrue);
    });

    test('🔴 아직 안 만든 카드가 문서에 적혀 있다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('월별 인사이트'), isTrue);
      for (final key in ['거래처', '부자재']) {
        expect(doc.contains(key), isTrue, reason: '$key 카드가 문서에 없다');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // 품목별 지출 분석 (#184)
  // ═══════════════════════════════════════════════════════════════════

  FlowerItem f(String name, int qty, double price, {String unit = '단'}) =>
      FlowerItem(name: name, quantity: qty, unitPrice: price, unit: unit);

  /// 🔴 사장님이 주신 검산값 그대로.
  ///
  /// ```
  ///   절화   2,074,000원  = 720,000 + 430,000 + 380,000 + 300,000 + 244,000
  ///   부자재   610,000원
  ///   화분     244,000원
  ///   기타     122,000원
  ///   ───────────────────
  ///   합계   3,050,000원  → 68.0% / 20.0% / 8.0% / 4.0%
  /// ```
  List<ReceiptModel> spend7() => [
        r('s7', DateTime(2026, 7, 10), [
          f('장미(레드)', 90, 8000), // 720,000
          f('거베라', 86, 5000), // 430,000
          f('카네이션', 76, 5000), // 380,000
          f('국화', 80, 3750), // 300,000
          f('튤립', 20, 7000), // 140,000
          f('프리지아', 26, 4000), // 104,000  → 기타 절화 244,000
          f('포장지', 10, 61000, unit: '롤'), // 610,000 부자재
          f('고무나무 화분', 4, 61000, unit: '개'), // 244,000 화분·식물
          f('배송비', 2, 61000, unit: '건'), // 122,000 기타
        ], total: 3050000),
      ];

  /// 6월 — 비교용. 장미는 5만원을 훌쩍 넘고, 수국만 3만원이다.
  List<ReceiptModel> spend6() => [
        r('s6', DateTime(2026, 6, 10), [
          f('장미(레드)', 70, 8000), // 560,000
          f('거베라', 80, 5500), // 440,000
          f('수국', 10, 3000), // 30,000  ← 5만원 미만
          f('포장지', 8, 60000, unit: '롤'), // 480,000
        ], total: 1510000),
      ];

  /// 달을 넘기는 화살표. ListView **안쪽**에 있는 것만 고른다.
  ///
  /// 🔴 FnShell 의 뒤로가기 화살표도 `chevron_left_rounded` 다. 그냥
  ///    `find.byIcon` 을 쓰면 둘이 잡혀 `tap()` 이 못 고른다.
  Finder monthArrow(IconData icon) => find.descendant(
        of: find.byType(ListView),
        matching: find.byIcon(icon),
      );

  group('품목별 지출 분석 — 검산 (사장님이 주신 값)', () {
    test('🔴 품목군 네 조각이 3,050,000원이고 68 / 20 / 8 / 4% 다', () {
      final rep = ItemSpend.build(spend7(), month: DateTime(2026, 7), now: now);

      expect(rep.total, 3050000);
      expect(rep.slices.length, 4);

      expect(rep.slices[0].group, ItemGroup.cutFlower);
      expect(rep.slices[0].amount, 2074000);
      expect(InsightFmt.pct(rep.slices[0].share), '68.0%');

      expect(rep.slices[1].group, ItemGroup.supply);
      expect(rep.slices[1].amount, 610000);
      expect(InsightFmt.pct(rep.slices[1].share), '20.0%');

      expect(rep.slices[2].group, ItemGroup.plant);
      expect(rep.slices[2].amount, 244000);
      expect(InsightFmt.pct(rep.slices[2].share), '8.0%');

      expect(rep.slices[3].group, ItemGroup.etc);
      expect(rep.slices[3].amount, 122000);
      expect(InsightFmt.pct(rep.slices[3].share), '4.0%');

      // 네 조각의 합이 총 지출과 **정확히** 같아야 한다.
      final sum = rep.slices.fold<double>(0, (s, e) => s + e.amount);
      expect(sum, rep.total);
    });

    test('🔴 장미(레드) 720,000원 ÷ 절화 2,074,000원 = 34.7%', () {
      final rep = ItemSpend.build(spend7(), month: DateTime(2026, 7), now: now);
      expect(rep.cutFlowerTotal, 2074000);
      expect(rep.rows.first.name, '장미(레드)');
      expect(rep.rows.first.amount, 720000);
      expect(InsightFmt.pct(720000 / rep.cutFlowerTotal), '34.7%');
      expect(rep.notes.first, '장미(레드)에 가장 많이 썼어요. 절화 지출의 34.7%인 720,000원이에요.');
    });

    test('🔴 지난달 3만원 → 이번 달 9만원인 품목은 % 를 적지 않는다', () {
      // 7월에 수국 90,000원(30단×3,000). 6월 수국은 30,000원뿐이다.
      final july = [
        r('j', DateTime(2026, 7, 10), [f('수국', 30, 3000)], total: 90000),
      ];
      final rep = ItemSpend.build(
        [...july, ...spend6()],
        month: DateTime(2026, 7),
        now: now,
      );
      final row = rep.rows.firstWhere((e) => e.name == '수국');
      expect(row.amount, 90000);
      // 5만원 미만이라 비율을 내지 않는다. 신규도 아니다(6월에 있었다).
      expect(row.delta, isNull);
      expect(row.isNew, isFalse);
      expect(row.deltaText, '');
      // 늘어난 품목 문장에도 나오면 안 된다.
      expect(rep.notes.any((e) => e.contains('수국 매입은')), isFalse);
    });

    test('🔴 "기타 절화" 는 늘어난/줄어든 품목 문장에 나오지 않는다', () {
      final rep = ItemSpend.build(
        [...spend7(), ...spend6()],
        month: DateTime(2026, 7),
        now: now,
      );
      // 묶음 줄 자체는 있다.
      expect(rep.rows.last.name, '기타 절화');
      expect(rep.rows.last.isOther, isTrue);
      expect(rep.rows.last.amount, 244000);
      // 그런데 문장에는 없다.
      for (final note in rep.notes) {
        expect(note.contains('기타 절화 매입은'), isFalse,
            reason: '묶음이 늘고 준 품목 문장에 나왔다: $note');
      }
      // 실제 품목으로 말해야 한다. 장미 560,000 → 720,000 = +28.6%
      expect(rep.notes.any((e) => e == '장미(레드) 매입은 전월 대비 28.6% 늘었어요.'),
          isTrue, reason: rep.notes.join(' / '));
    });
  });

  group('품목별 지출 분석 — 셈 규칙', () {
    test('🔴 이름은 띄어쓰기·괄호·대소문자만 무시하고 묶는다', () {
      expect(ItemSpend.nameKey('장미 (레드)'), ItemSpend.nameKey('장미(레드)'));
      expect(ItemSpend.nameKey('Rose Red'), ItemSpend.nameKey('rosered'));
      // 🔴 `장미` 와 `장미(레드)` 는 **다른 품목**이다. 묶으면 안 된다.
      expect(ItemSpend.nameKey('장미'), isNot(ItemSpend.nameKey('장미(레드)')));
    });

    test('🔴 단위가 섞이면 수량을 적지 않는다', () {
      final rs = [
        r('a', DateTime(2026, 7, 3), [f('장미', 10, 8000)], total: 80000),
        r('b', DateTime(2026, 7, 4), [f('장미', 20, 900, unit: '송이')],
            total: 18000),
      ];
      final rep = ItemSpend.build(rs, month: DateTime(2026, 7), now: now);
      final row = rep.rows.first;
      expect(row.amount, 98000);
      expect(row.hasQty, isFalse);
      expect(row.qtyText, '');
    });

    test('단위가 같으면 수량을 합쳐 적는다', () {
      final rs = [
        r('a', DateTime(2026, 7, 3), [f('장미', 10, 8000)], total: 80000),
        r('b', DateTime(2026, 7, 4), [f('장미', 20, 8000)], total: 160000),
      ];
      final rep = ItemSpend.build(rs, month: DateTime(2026, 7), now: now);
      expect(rep.rows.first.qtyText, '30단');
    });

    test('🔴 절화 다섯 가지가 넘으면 네 개만 따로, 나머지는 묶는다', () {
      final rep = ItemSpend.build(spend7(), month: DateTime(2026, 7), now: now);
      expect(rep.rows.length, 5);
      expect(rep.rows.map((e) => e.name).toList(),
          ['장미(레드)', '거베라', '카네이션', '국화', '기타 절화']);
      // 묶음은 튤립 140,000 + 프리지아 104,000.
      expect(rep.rows.last.amount, 244000);
    });

    test('🔴 비교할 달에 영수증이 없으면 % 와 비교 문구를 숨긴다', () {
      final rep = ItemSpend.build(spend7(), month: DateTime(2026, 7), now: now);
      expect(rep.hasCompare, isFalse);
      expect(rep.cutFlowerDelta, isNull);
      expect(rep.cutFlowerHead, '7월 2,074,000원');
      for (final row in rep.rows) {
        expect(row.deltaText, '');
      }
      // 첫 번째 문장 + 안내만.
      expect(rep.notes.length, 2);
      expect(rep.notes.last, MonthlyInsightReport.firstMonthNote);
    });

    test('🔴 지난 달이 있으면 머리줄에 전월 대비를 적는다', () {
      final rep = ItemSpend.build(
        [...spend7(), ...spend6()],
        month: DateTime(2026, 7),
        now: now,
      );
      // 절화 1,030,000 → 2,074,000 = +101.4%
      expect(rep.hasCompare, isTrue);
      expect(rep.cutFlowerHead, '7월 2,074,000원 · 지난달 대비 +101.4%');
    });

    test('🔴 진행 중인 이번 달은 지난달 "같은 기간"과 견준다', () {
      // 오늘이 7월 15일. 7월은 진행 중이다.
      final today = DateTime(2026, 7, 15);
      final rs = [
        r('now', DateTime(2026, 7, 5), [f('장미', 10, 10000)], total: 100000),
        // 6월 5일 — 같은 기간 안.
        r('p1', DateTime(2026, 6, 5), [f('장미', 10, 8000)], total: 80000),
        // 6월 25일 — 같은 기간 밖이라 빼야 한다.
        r('p2', DateTime(2026, 6, 25), [f('장미', 100, 8000)], total: 800000),
      ];
      final rep = ItemSpend.build(rs, now: today);
      expect(rep.inProgress, isTrue);
      expect(rep.periodNote, '7월 1~15일 기준');
      expect(rep.compareLabel, '지난달 같은 기간');
      // 80,000 → 100,000 = +25.0%. 6월 25일 것이 섞였다면 전혀 다른 값이 된다.
      expect(rep.cutFlowerHead, '7월 100,000원 · 지난달 같은 기간 대비 +25.0%');
    });

    test('🔴 절화 비중 문장은 %p 를 소수 첫째 자리로 적는다', () {
      final rep = ItemSpend.build(
        [...spend7(), ...spend6()],
        month: DateTime(2026, 7),
        now: now,
      );
      // 7월 68.0% / 6월 1,030,000 ÷ 1,510,000 = 68.2% ⇒ 0.2%p 줄었다.
      expect(rep.notes.last, '전체 지출에서 절화 비중은 68.0%로, 전월 대비 0.2%p 줄었어요.');
    });

    test('면세·과세 표시가 품목군마다 정해져 있다', () {
      final rep = ItemSpend.build(spend7(), month: DateTime(2026, 7), now: now);
      expect(rep.slices[0].sub, '면세 · 68.0%');
      expect(rep.slices[1].sub, '과세 · 20.0%');
      expect(rep.slices[2].sub, '면세/과세 · 8.0%');
      expect(rep.slices[3].sub, '과세 · 4.0%');
    });
  });

  group('품목별 지출 분석 — 화면', () {
    testWidgets('🔴 시안 순서대로 세 카드가 보인다', (t) async {
      await pump(
        t,
        ItemSpendDsScreen(
          receipts: [...spend7(), ...spend6()],
          now: DateTime(2026, 8, 10),
        ),
      );
      // 8월이 이번 달이니 처음에는 8월(영수증 없음)이다. 7월로 넘긴다.
      await t.tap(monthArrow(Icons.chevron_left_rounded));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('품목별 지출 분석'), findsOneWidget);
      expect(find.text('2026년 7월'), findsOneWidget);
      expect(find.text('총 지출'), findsOneWidget);
      expect(find.text('305만원'), findsOneWidget);

      expect(find.text('절화(꽃)'), findsOneWidget);
      expect(find.text('면세 · 68.0%'), findsOneWidget);
      expect(find.text('2,074,000원'), findsWidgets);
      expect(find.text('610,000원'), findsOneWidget);
      expect(find.text('244,000원'), findsWidgets);
      expect(find.text('122,000원'), findsOneWidget);

      expect(find.text('절화(꽃) 품목별 매입'), findsOneWidget);
      expect(find.text('7월 2,074,000원 · 지난달 대비 +101.4%'), findsOneWidget);
      expect(find.text('장미(레드)'), findsOneWidget);
      expect(find.text('720,000원'), findsOneWidget);
      expect(find.text('90단 · +28.6%'), findsOneWidget);
      expect(find.text('기타 절화'), findsOneWidget);

      expect(find.text('데이터 분석'), findsOneWidget);
      expect(find.text('장미(레드)에 가장 많이 썼어요. 절화 지출의 34.7%인 720,000원이에요.'),
          findsOneWidget);
      expect(find.text(ItemSpendReport.taxNote), findsOneWidget);
    });

    testWidgets('🔴 ‹ › 로 달을 옮긴다. 아직 오지 않은 달로는 못 간다', (t) async {
      await pump(
        t,
        ItemSpendDsScreen(
          receipts: [...spend7(), ...spend6()],
          now: DateTime(2026, 8, 10),
        ),
      );
      expect(find.text('2026년 8월'), findsOneWidget);

      await t.tap(monthArrow(Icons.chevron_left_rounded));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2026년 7월'), findsOneWidget);

      await t.tap(monthArrow(Icons.chevron_right_rounded));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2026년 8월'), findsOneWidget);

      // 8월이 이번 달이라 더는 못 간다.
      await t.tap(monthArrow(Icons.chevron_right_rounded));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2026년 8월'), findsOneWidget);
      expect(find.text('2026년 9월'), findsNothing);
    });

    testWidgets('🔴 그 달 영수증이 없으면 안내와 스캔 버튼을 보여 준다', (t) async {
      await pump(
        t,
        ItemSpendDsScreen(receipts: const [], now: DateTime(2026, 8, 10)),
      );
      expect(find.text(ItemSpendReport.emptyNote), findsOneWidget);
      expect(find.text('영수증 스캔하기'), findsOneWidget);
      // 빈 달에는 아래 두 카드를 그리지 않는다.
      expect(find.text('절화(꽃) 품목별 매입'), findsNothing);
      expect(find.text('데이터 분석'), findsNothing);
    });

    testWidgets('🔴 비교할 달이 없으면 첫 문장과 안내만 보여 준다', (t) async {
      await pump(
        t,
        ItemSpendDsScreen(receipts: spend7(), now: DateTime(2026, 8, 10)),
      );
      await t.tap(monthArrow(Icons.chevron_left_rounded));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('7월 2,074,000원'), findsOneWidget);
      expect(find.text(MonthlyInsightReport.firstMonthNote), findsOneWidget);
      expect(find.textContaining('전월 대비'), findsNothing);
    });

    testWidgets('🔴 카드가 기준 꾸밈(모서리 18·좌우 여백 24)을 쓴다', (t) async {
      await pump(
        t,
        ItemSpendDsScreen(receipts: spend7(), now: DateTime(2026, 7, 31)),
      );
      final list = t.widget<ListView>(find.byType(ListView).first);
      expect(list.padding,
          const EdgeInsets.fromLTRB(FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl));

      final deco = t
          .widgetList<Container>(find.byType(Container))
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()
          .where((e) => e.borderRadius == BorderRadius.circular(FnDs.cardRadius))
          .toList();
      expect(deco, isNotEmpty);
      expect(deco.first.color, FnDs.card);
      expect(deco.first.border, isNull);
    });
  });

  group('품목별 지출 분석 — 소스 계약', () {
    String itemPart() {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      return src.substring(src.indexOf('class ItemSpendDsScreen'));
    }

    test('🔴 셈을 화면에서 하지 않고 서비스에 모았다', () {
      final part = itemPart();
      expect(part.contains('ItemSpend.build('), isTrue);
      // 화면에서 또 나누면 도넛과 문장의 % 가 어긋난다.
      expect(part.contains('/ total'), isFalse);
      expect(part.contains('InsightFmt.pct('), isFalse);
    });

    test('🔴 품목군 분류를 다시 짜지 않고 monthly_insight 것을 쓴다', () {
      final svc = _read('lib/services/monthly_insight.dart');
      expect(svc.contains('class ItemSpend'), isTrue);
      // groupOf 는 한 곳에만 있어야 한다.
      expect('ItemGroup groupOf('.allMatches(svc).length, 1);
      expect(svc.contains('MonthlyInsight.groupOf('), isTrue);
    });

    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final part = itemPart();
      expect(part.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(part.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 홈의 품목 비중 카드가 이 화면으로 간다', () {
      final home = _read('lib/screens/ds/home_ds_screen.dart');
      expect(home.contains('ItemSpendDsScreen()'), isTrue);
      expect(home.contains('상세 분석 보기'), isTrue);
    });

    test('🔴 데이터 분석 문장을 AI 로 만들지 않는다', () {
      final svc = _read('lib/services/monthly_insight.dart');
      final part = svc.substring(svc.indexOf('class ItemSpend {'));
      for (final banned in ['Gemini', 'http', 'prompt']) {
        expect(part.contains(banned), isFalse, reason: '$banned 가 들어 있다');
      }
    });
  });
}
