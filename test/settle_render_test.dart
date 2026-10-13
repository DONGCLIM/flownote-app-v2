// 요청 #140 회귀 — 내역(구매 내역) 화면 시안 반영.
//
// 시안(399x1024, 환산비 0.9774) 실측값:
//
//   총매입 카드   y 127.1..293.2dp (h 166)   흰색 #FFFFFF
//   카드 좌우     24.4dp (좌우 대칭)
//   코랄 배지     y 245.3..273.7dp (h 28)    #FF6D78
//   토글          y 310.8..351.9dp (h 41)    두 칸 각 168~170dp
//                 왼쪽=업체별(흰), 오른쪽=날짜별(코랄)
//
// 🔴 바꾸기 전 상태(= 이 테스트가 막으려는 회귀):
//    - 총매입이 카드 없이 좌측 정렬, 건수가 회색 글자
//    - 토글이 회색 홈통 안 세그먼트, 순서가 날짜별/업체별 (반대)
//    - 본문 좌우 여백 16dp

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/screens/ds/settle_ds_screen.dart';
import 'package:flow_note/screens/ds/settle_views_ds.dart';

ReceiptModel _r(String id, DateTime d, String store, double amt) =>
    ReceiptModel(
      id: id,
      date: d,
      storeName: store,
      items: [FlowerItem(name: '장미', quantity: 1, unitPrice: amt, unit: '단')],
      totalAmount: amt,
      rawOcrText: 't',
      createdAt: d,
    );

class _Fake extends ReceiptProvider {
  _Fake(this._items);
  final List<ReceiptModel> _items;
  @override
  List<ReceiptModel> get allReceipts => _items;
}

Future<void> _pump(
  WidgetTester t, {
  Size size = const Size(390, 1100),
  List<ReceiptModel>? items,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<ReceiptProvider>.value(
      value: _Fake(items ??
          [
            _r('1', DateTime(2026, 7, 24), '대한꽃도매', 256000),
            _r('2', DateTime(2026, 7, 24), '그린플러스', 98000),
            _r('3', DateTime(2026, 7, 22), '화람원예', 184000),
          ]),
      child: const MaterialApp(home: Scaffold(body: SettleDsScreen())),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

/// 해당 글자를 감싸는 Container 들의 배경색 목록.
List<Color> _bgOf(WidgetTester t, Finder f) => find
    .ancestor(of: f, matching: find.byType(Container))
    .evaluate()
    .map((e) => (e.widget as Container).decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.color)
    .whereType<Color>()
    .toList();

void main() {
  testWidgets('예외 없이 그려진다', (t) async {
    await _pump(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('🔴 총매입이 흰 카드 안에 들어 있다', (t) async {
    await _pump(t);
    final label = find.textContaining('총 매입');
    expect(label, findsWidgets, reason: '총 매입 라벨이 없다');
    expect(_bgOf(t, label.first), contains(kSettleWhite),
        reason: '시안 총매입 카드는 흰색이다');
  });

  testWidgets('🔴 건수가 코랄 배지로 나온다', (t) async {
    await _pump(t);
    final badge = find.textContaining('총 매입 건수');
    expect(badge, findsOneWidget, reason: '총 매입 건수 배지가 없다');
    expect(t.widget<Text>(badge).style?.color, Colors.white,
        reason: '배지 글자는 흰색이어야 한다');
    expect(_bgOf(t, badge), contains(kSettleCoral),
        reason: '시안 배지 색 #FF6D78 이 없다');
  });

  testWidgets('🔴 토글이 업체별(왼쪽) · 날짜별(오른쪽) 순서다', (t) async {
    await _pump(t);
    final v = find.text('업체별');
    final d = find.text('날짜별');
    expect(v, findsOneWidget);
    expect(d, findsOneWidget);
    expect(t.getCenter(v).dx, lessThan(t.getCenter(d).dx),
        reason: '시안은 업체별이 왼쪽이다');
  });

  testWidgets('🔴 활성 토글이 코랄 채움 + 흰 글자다', (t) async {
    await _pump(t);
    // 기본 보기는 날짜별이다.
    final active = find.text('날짜별');
    expect(t.widget<Text>(active).style?.color, Colors.white,
        reason: '활성 토글 글자는 흰색');
    expect(_bgOf(t, active), contains(kSettleCoral),
        reason: '활성 토글은 코랄 채움');

    // 비활성은 흰 채움이고 글자가 흰색이 아니다.
    final idle = find.text('업체별');
    expect(t.widget<Text>(idle).style?.color, isNot(Colors.white));
    expect(_bgOf(t, idle), contains(kSettleWhite),
        reason: '비활성 토글은 흰 채움');
  });

  testWidgets('🔴 회색 홈통(fillNormal)이 토글에 남아 있지 않다', (t) async {
    await _pump(t);
    final around = _bgOf(t, find.text('날짜별'));
    expect(around.map((c) => c.toARGB32()), isNot(contains(0x1470737C)),
        reason: '예전 회색 홈통이 남아 있다');
  });

  testWidgets('🔴 토글 높이가 시안 41dp 다', (t) async {
    await _pump(t);
    final box = find
        .ancestor(
            of: find.text('날짜별'), matching: find.byType(AnimatedContainer))
        .first;
    expect(t.getSize(box).height, closeTo(kSettleToggleH, 1.0),
        reason: '시안 토글 높이 41.1dp');
  });

  testWidgets('🔴 좌우 여백이 시안 24dp 다', (t) async {
    await _pump(t, size: const Size(390, 1100));
    final card = find.ancestor(
      of: find.textContaining('총 매입').first,
      matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.color == kSettleWhite;
      }),
    );
    expect(card, findsWidgets);
    final r = t.getRect(card.first);
    expect(r.left, closeTo(kSettlePagePad, 1.5), reason: '시안 좌 여백 24.4dp');
    expect(390 - r.right, closeTo(kSettlePagePad, 1.5),
        reason: '시안 우 여백 24.4dp');
  });

  testWidgets('🔴 검색창 위에 거래처 검색 라벨이 있다', (t) async {
    await _pump(t);
    expect(find.text('거래처 검색'), findsOneWidget,
        reason: '시안 라벨이 없다');
  });

  testWidgets('기능 유지 — 토글을 누르면 업체별 보기로 바뀐다', (t) async {
    await _pump(t);
    await t.tap(find.text('업체별'));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    // 업체별로 바뀌면 활성 글자가 업체별로 넘어간다.
    expect(t.widget<Text>(find.text('업체별')).style?.color, Colors.white);
  });

  testWidgets('기능 유지 — 검색창·필터 칩이 그대로 있다', (t) async {
    await _pump(t);
    expect(find.text('거래처명 검색'), findsOneWidget);
    for (final chip in ['가나다순', '과세 구분', '전송 상태', '종합소득세용(5월)']) {
      expect(find.textContaining(chip), findsWidgets, reason: '$chip 칩이 없다');
    }
  });

  testWidgets('기능 유지 — 영수증이 없으면 빈 안내가 나온다', (t) async {
    await _pump(t, items: const []);
    expect(find.textContaining('아직 매입 내역이 없어요'), findsOneWidget);
  });

  testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
    await _pump(t, size: const Size(320, 900));
    expect(t.takeException(), isNull);
    expect(find.text('날짜별'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════
  //  #142 — 카드별 그림자 / 칩 색 / 금액 표기
  // ══════════════════════════════════════════════════════════════

  /// 해당 글자를 감싸는 Container/DecoratedBox 의 BoxDecoration 목록.
  List<BoxDecoration> decosOf(Finder f) => [
        ...find
            .ancestor(of: f, matching: find.byType(Container))
            .evaluate()
            .map((e) => (e.widget as Container).decoration),
        ...find
            .ancestor(of: f, matching: find.byType(DecoratedBox))
            .evaluate()
            .map((e) => (e.widget as DecoratedBox).decoration),
        ...find
            .ancestor(of: f, matching: find.byType(AnimatedContainer))
            .evaluate()
            .map((e) => (e.widget as AnimatedContainer).decoration),
      ].whereType<BoxDecoration>().toList();

  testWidgets('🔴 #142 총매입 카드에 큰 그림자가 있다', (t) async {
    await _pump(t);
    final decos = decosOf(find.text('총 매입 건수 3건'));
    final withShadow =
        decos.where((d) => (d.boxShadow ?? const []).isNotEmpty).toList();
    expect(withShadow, isNotEmpty, reason: '총매입 카드에 그림자가 없다');
    // 시안 번짐 9dp — 가장 큰 blurRadius 가 충분히 커야 한다.
    final maxBlur = withShadow
        .expand((d) => d.boxShadow!)
        .map((s) => s.blurRadius)
        .reduce((a, b) => a > b ? a : b);
    expect(maxBlur, greaterThanOrEqualTo(10.0),
        reason: '시안은 9dp 번지는 부드러운 그림자다');
  });

  testWidgets('🔴 #142 영수증 카드 그림자는 총매입보다 작다', (t) async {
    await _pump(t);
    double maxBlurOf(Finder f) {
      final sh = decosOf(f)
          .expand((d) => d.boxShadow ?? const <BoxShadow>[])
          .map((s) => s.blurRadius)
          .toList();
      return sh.isEmpty ? 0 : sh.reduce((a, b) => a > b ? a : b);
    }

    final big = maxBlurOf(find.text('총 매입 건수 3건'));
    final small = maxBlurOf(find.text('대한꽃도매'));
    expect(small, greaterThan(0.0), reason: '영수증 카드에 그림자가 없다');
    // 🔴 이것이 사장님이 말한 "카드마다 다르다" 의 핵심이다.
    //    시안 실측: 총매입 9dp 번짐 vs 영수증 3dp 번짐.
    expect(small, lessThan(big),
        reason: '영수증 카드 그림자가 총매입 카드와 같거나 더 크다');
  });

  testWidgets('🔴 #142 영수증 카드는 흰색이다', (t) async {
    await _pump(t);
    final colors = decosOf(find.text('대한꽃도매'))
        .map((d) => d.color)
        .whereType<Color>()
        .toList();
    expect(colors, contains(const Color(0xFFFFFFFF)),
        reason: '시안 영수증 카드 내부는 #FFFFFF 다 (예전엔 분홍빛 #FFF9F7)');
  });

  testWidgets('🔴 #142 필터칩 — 꺼진 칩은 흰색, 켠 칩은 검정', (t) async {
    await _pump(t);
    // 처음엔 '종합소득세용(5월)' 이 꺼져 있다.
    // 🔴 `decosOf(...).first` 를 쓰면 안 된다. 칩 글자의 조상에는
    //    바깥 카드/배경 Container 도 섞여 있어서 엉뚱한 흰색을 집는다.
    //    칩 본체(`SettleFilterChip` 바로 아래 AnimatedContainer)만 본다.
    Color chipBg(String label) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(SettleFilterChip),
      );
      expect(chip, findsOneWidget, reason: '$label 칩을 못 찾았다');
      final d = find
          .descendant(of: chip, matching: find.byType(AnimatedContainer))
          .evaluate()
          .map((e) => (e.widget as AnimatedContainer).decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(d, isNotEmpty, reason: '$label 칩 배경을 못 찾았다');
      return d.first.color!;
    }

    expect(chipBg('종합소득세용(5월)'), const Color(0xFFFFFFFF),
        reason: '시안 비활성 칩은 흰색이다');

    // 누르면 검정으로 바뀐다 (시안 활성 칩 = #171717).
    await t.tap(find.text('종합소득세용(5월)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(chipBg('종합소득세용(5월)'), const Color(0xFF171717),
        reason: '시안 활성 칩은 검정 채움 + 흰 글자다');
  });

  testWidgets('🔴 #142 금액이 `숫자원` 표기다 (₩ 기호 아님)', (t) async {
    await _pump(t);
    // 시안: 1,184,000원 / 256,000원 — 앞에 ₩ 를 붙이지 않는다.
    expect(find.text('256,000원'), findsOneWidget);
    expect(find.textContaining('₩'), findsNothing,
        reason: '시안 내역 화면에는 ₩ 기호가 없다');
  });

  testWidgets('🔴 #142 검색창이 완전한 흰색이다', (t) async {
    await _pump(t);
    final bar = find.byType(SettleSearchBar);
    expect(bar, findsOneWidget);
    final box = find
        .descendant(of: bar, matching: find.byType(Container))
        .evaluate()
        .map((e) => (e.widget as Container).decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(box.first.color, const Color(0xFFFFFFFF),
        reason: '공용 검색창의 반투명 회색이 아니라 흰색이어야 한다');
    expect(box.first.boxShadow, isNotEmpty, reason: '검색창에도 얕은 그림자가 있다');
  });

  testWidgets('기능 유지 — #142 바꾼 뒤에도 검색이 동작한다', (t) async {
    await _pump(t);
    await t.enterText(find.byType(TextField), '그린');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('그린플러스'), findsOneWidget);
    expect(find.text('대한꽃도매'), findsNothing, reason: '검색이 걸러내지 못했다');
  });
}
