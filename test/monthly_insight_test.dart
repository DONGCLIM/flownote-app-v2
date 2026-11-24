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
}
