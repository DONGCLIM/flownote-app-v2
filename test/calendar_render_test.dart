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

/// 히트맵 색 4단계 (시안 `HEAT`)
const _heat = [
  Color(0xFFFBE4E7),
  Color(0xFFF5C2C8),
  Color(0xFFEE8E9C),
  Color(0xFFDE6A7C),
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

void main() {
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
    expect(find.text('3건'), findsOneWidget);
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
    expect(find.text('8건'), findsOneWidget);
  });
}
