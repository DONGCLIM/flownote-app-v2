import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/calendar_ds_screen.dart';

/// 🔴 #102 — 캘린더를 사장님이 준 시안으로 갈아끼웠다.
///
/// 시안(`8fa93f26-…js`, `screen === 'calendar'`)의 히트맵:
/// ```js
/// const maxDay = Math.max.apply(null, [1].concat(... dayTotal(d)));
/// const HEAT = ['#FBE4E7', '#F5C2C8', '#EE8E9C', '#DE6A7C'];
/// const lvl = t/maxDay <= .33 ? 0 : <= .6 ? 1 : <= .85 ? 2 : 3;
/// ```
///
/// 이 테스트가 지키는 것:
///  1. 예외 없이 그려진다 (`takeException() == null`)
///  2. 시안 문구가 실제로 보인다 (총 매입 / 적음 / 많음 / 사진 추가)
///  3. **영수증이 많은 날이 실제로 더 진하게** 칠해진다 — 요청의 핵심
///  4. 히트맵 4색이 다 등장한다 (범례)
///  5. 좁은 화면에서 오버플로가 없다
///  6. 날짜 탭 → 그 날 내역이 나온다

class _FakeReceiptProvider extends ReceiptProvider {
  _FakeReceiptProvider(this._items);
  final List<ReceiptModel> _items;

  @override
  List<ReceiptModel> get allReceipts => _items;
}

/// 히트맵 색 4단계.
///
/// 🔴 #139 시안(317x1024) 범례를 실측해 교체했다. 범례 스와치
/// (y 752.9dp, 각 13dp)를 왼쪽부터 읽은 값이며, 격자 칸 색으로
/// 교차 확인했다 (3일 #FFF1EE / 10일 #FFAC92 / 24일 #FF6D78).
/// 예전 값(#DE6A7C 계열)은 자줏빛이라 앱 코랄 톤과 달랐다.
const _heat = [
  Color(0xFFFEF0ED),
  Color(0xFFFFD4C3),
  Color(0xFFFFAA96),
  Color(0xFFFF6F7A),
];

ReceiptModel _r({
  required String id,
  required DateTime date,
  required String store,
  required double amount,
  List<FlowerItem> items = const [],
}) =>
    ReceiptModel(
      id: id,
      date: date,
      storeName: store,
      items: items,
      totalAmount: amount,
      rawOcrText: 'test',
      createdAt: date,
    );

Widget _wrap(List<ReceiptModel> items,
        {Size size = const Size(402, 874)}) =>
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: ChangeNotifierProvider<ReceiptProvider>.value(
          value: _FakeReceiptProvider(items),
          child: const Scaffold(body: CalendarDsScreen()),
        ),
      ),
    );

/// 화면에 실제로 그려진 날짜 칸의 배경색을 찾는다.
/// 날짜 숫자 텍스트의 조상 중 `Container` 의 `BoxDecoration.color`.
Color? _cellColor(WidgetTester t, String day) {
  final txt = find.text(day);
  if (txt.evaluate().isEmpty) return null;
  final boxes = find
      .ancestor(of: txt, matching: find.byType(Container))
      .evaluate()
      .toList();
  for (final e in boxes) {
    final c = e.widget as Container;
    final d = c.decoration;
    if (d is BoxDecoration && d.borderRadius != null && d.color != null) {
      return d.color;
    }
  }
  return null;
}

/// #139 전용 — 시안 톤앤톤 회귀 검사.
void _k139() {
  group('#139 캘린더 시안 반영', () {
    testWidgets('🔴 월 총매입 카드가 흰 카드다 (분홍 그라디언트 아님)',
        (t) async {
      await t.pumpWidget(_wrap(const []));
      await t.pump(const Duration(milliseconds: 300));

      // '총 매입' 글자를 품은 Container 중 배경이 지정된 것을 찾는다.
      final label = find.textContaining('총 매입');
      expect(label, findsOneWidget, reason: '총 매입 라벨이 없다');
      final boxes = find
          .ancestor(of: label, matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration)
          .whereType<BoxDecoration>()
          .toList();
      final withBg = boxes.where((d) => d.color != null).toList();
      expect(withBg, isNotEmpty, reason: '카드 배경이 없다');
      expect(withBg.first.color, const Color(0xFFFFFFFF),
          reason: '시안 카드는 흰색이다');
      // 예전 그라디언트가 남아 있으면 안 된다
      expect(boxes.any((d) => d.gradient != null), isFalse,
          reason: '분홍 그라디언트가 남아 있다');
    });

    testWidgets('🔴 건수가 코랄 배지로 나온다', (t) async {
      await t.pumpWidget(_wrap(const []));
      await t.pump(const Duration(milliseconds: 300));

      final badge = find.text('총 8건');
      expect(badge, findsOneWidget, reason: '총 N건 배지가 없다');
      // 글자는 흰색
      expect((t.widget<Text>(badge)).style?.color, Colors.white,
          reason: '배지 글자는 흰색이어야 한다');
      // 배경은 시안 코랄
      final bg = find
          .ancestor(of: badge, matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .toList();
      expect(bg, contains(const Color(0xFFFF6D78)),
          reason: '시안 배지 색 #FF6D78 이 없다');
    });

    testWidgets('🔴 캘린더가 흰 카드 안에 들어 있다', (t) async {
      await t.pumpWidget(_wrap(const []));
      await t.pump(const Duration(milliseconds: 300));

      // 요일 '일' 과 범례 '적음' 을 **같은** 흰 Container 가 감싸야 한다.
      final sun = find.text('일');
      final few = find.text('적음');
      expect(sun, findsOneWidget);
      expect(few, findsOneWidget);

      Set<Element> whiteCardsOf(Finder f) => find
          .ancestor(of: f, matching: find.byType(Container))
          .evaluate()
          .where((e) {
            final d = (e.widget as Container).decoration;
            return d is BoxDecoration && d.color == const Color(0xFFFFFFFF);
          })
          .toSet();

      final shared = whiteCardsOf(sun).intersection(whiteCardsOf(few));
      expect(shared, isNotEmpty,
          reason: '요일과 범례를 함께 감싸는 흰 카드가 없다');
    });

    testWidgets('🔴 좌우 여백이 시안 24dp 다', (t) async {
      // 🔴 `_wrap(size:)` 는 MediaQuery 만 바꾼다. 실제 뷰포트는 기본값
      //    (800dp 폭)이라 left 가 -386.0 으로 나왔다. 화면 폭을 재는
      //    검사는 `tester.view.physicalSize` 를 반드시 같이 바꿔야 한다.
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(const [], size: const Size(390, 900)));
      await t.pump(const Duration(milliseconds: 300));

      // 🔴 find.byWidget 은 같은 위젯이 여러 번 쓰이면 엉뚱한 것을
      //    잡는다(실제로 left = -386.0 이 나왔다). 그래서 Finder 를
      //    조상 경로로 직접 만들어 **첫 번째 흰 카드**를 가리킨다.
      final label = find.textContaining('총 매입');
      final card = find.ancestor(
        of: label,
        matching: find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          return d is BoxDecoration && d.color == const Color(0xFFFFFFFF);
        }),
      );
      expect(card, findsWidgets, reason: '흰 카드가 없다');
      final r = t.getRect(card.first);
      expect(r.left, closeTo(24, 1.5), reason: '시안 좌 여백 24.6dp');
      expect(390 - r.right, closeTo(24, 1.5), reason: '시안 우 여백 24.6dp');
    });

    testWidgets('🔴 예전 자줏빛 히트맵 색이 남아 있지 않다', (t) async {
      await t.pumpWidget(_wrap(const []));
      await t.pump(const Duration(milliseconds: 300));

      final used = <int>{};
      for (final e in find.byType(Container).evaluate()) {
        final d = (e.widget as Container).decoration;
        if (d is BoxDecoration && d.color != null) {
          used.add(d.color!.toARGB32());
        }
      }
      for (final old in [0xFFFBE4E7, 0xFFF5C2C8, 0xFFEE8E9C, 0xFFDE6A7C]) {
        expect(used.contains(old), isFalse,
            reason: '예전 히트맵 색 ${old.toRadixString(16)} 이 남아 있다');
      }
      // 새 색 중 적어도 하나는 쓰였다 (데모 데이터에 칠해진 날이 있다)
      expect(
          used.intersection(
              {0xFFFEF0ED, 0xFFFFD4C3, 0xFFFFAA96, 0xFFFF6F7A}),
          isNotEmpty,
          reason: '새 히트맵 색이 하나도 안 쓰였다');
    });
  });
}

void main() {
  _k139();
  // 표시되는 달은 항상 "이번 달" (provider 기본값 = 오늘)
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, d);

  testWidgets('캘린더가 예외 없이 그려지고 시안 문구가 보인다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);

    // 총 매입 카드 (시안: `${year}년 ${month}월 총 매입`)
    expect(find.textContaining('총 매입'), findsOneWidget);
    // 히트맵 범례
    expect(find.text('적음'), findsOneWidget);
    expect(find.text('많음'), findsOneWidget);
    // 요일 머리글
    expect(find.text('일'), findsOneWidget);
    expect(find.text('토'), findsOneWidget);
  });

  testWidgets('영수증 금액이 큰 날이 더 진하게 칠해진다', (t) async {
    // 3일 5만원(연함) / 24일 40만원(가장 진함)
    await t.pumpWidget(_wrap([
      _r(id: 'a', date: day(3), store: '화람원예', amount: 50000),
      _r(id: 'b', date: day(24), store: '대한꽃도매', amount: 400000),
    ]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    final light = _cellColor(t, '3');
    final dark = _cellColor(t, '24');

    expect(light, isNotNull, reason: '3일 칸 배경을 찾지 못했다');
    expect(dark, isNotNull, reason: '24일 칸 배경을 찾지 못했다');

    // 5만/40만 = 0.125 → lvl 0, 40만/40만 = 1.0 → lvl 3
    expect(light, _heat[0]);
    expect(dark, _heat[3]);

    // "진하다" 를 색 밝기로도 확인한다
    expect(dark!.computeLuminance(), lessThan(light!.computeLuminance()),
        reason: '많이 쓴 날이 더 진해야 한다');
  });

  testWidgets('히트맵 4단계가 금액 비율대로 나뉜다', (t) async {
    // maxDay = 100만.  10만(.10→0) / 50만(.50→1) / 80만(.80→2) / 100만(1.0→3)
    await t.pumpWidget(_wrap([
      _r(id: 'a', date: day(2), store: 'A', amount: 100000),
      _r(id: 'b', date: day(5), store: 'B', amount: 500000),
      _r(id: 'c', date: day(9), store: 'C', amount: 800000),
      _r(id: 'd', date: day(12), store: 'D', amount: 1000000),
    ]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    expect(_cellColor(t, '2'), _heat[0]);
    expect(_cellColor(t, '5'), _heat[1]);
    expect(_cellColor(t, '9'), _heat[2]);
    expect(_cellColor(t, '12'), _heat[3]);
  });

  testWidgets('영수증 없는 날은 칠하지 않는다', (t) async {
    await t.pumpWidget(_wrap([
      _r(id: 'a', date: day(10), store: 'A', amount: 100000),
    ]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // 11일에는 영수증이 없다 → 히트 색이 아니어야 한다
    final c = _cellColor(t, '11');
    expect(_heat.contains(c), isFalse,
        reason: '내역 없는 날에 히트 색이 칠해졌다: $c');
  });

  testWidgets('총 매입 금액과 건수가 그 달 영수증과 맞는다', (t) async {
    await t.pumpWidget(_wrap([
      _r(id: 'a', date: day(3), store: 'A', amount: 88000),
      _r(id: 'b', date: day(10), store: 'B', amount: 210000),
      _r(id: 'c', date: day(10), store: 'C', amount: 12000),
    ]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // 88,000 + 210,000 + 12,000 = 310,000
    expect(find.text('₩310,000'), findsWidgets);
    // #139 시안은 코랄 배지에 '총 N건' 으로 쓴다.
    expect(find.text('총 3건'), findsOneWidget);
  });

  testWidgets('날짜를 누르면 그날 내역과 사진 추가 버튼이 나온다', (t) async {
    await t.pumpWidget(_wrap([
      _r(
        id: 'a',
        date: day(7),
        store: '대한꽃도매',
        amount: 256000,
        items: [
          FlowerItem(name: '장미(레드)', quantity: 10, unitPrice: 12000, unit: '단'),
          FlowerItem(name: '거베라', quantity: 5, unitPrice: 8000, unit: '단'),
        ],
      ),
    ]));
    await t.pumpAndSettle();

    await t.tap(find.text('7'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // 시안 행: 업체명 + 품목 요약 + 금액
    expect(find.text('대한꽃도매'), findsOneWidget);
    expect(find.text('장미(레드) · 거베라'), findsOneWidget);
    // 시안 '사진 추가' 버튼
    expect(find.text('사진 추가'), findsOneWidget);
  });

  testWidgets('좁은 화면(320x640)에서도 오버플로가 없다', (t) async {
    await t.pumpWidget(_wrap([
      _r(id: 'a', date: day(15), store: '아주아주긴업체이름주식회사', amount: 1234567),
    ], size: const Size(320, 640)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('데이터가 없으면 시안 데모 숫자를 보여준다', (t) async {
    await t.pumpWidget(_wrap(const []));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    // 시안 byDay 합계 = 1,075,000 / 8건
    expect(find.text('₩1,075,000'), findsOneWidget);
    expect(find.text('총 8건'), findsOneWidget);
  });
}
