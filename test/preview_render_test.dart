// 요청 #144 회귀 — 정산서 미리보기 화면 시안 반영.
//
// 시안(348x1024, 환산비 1.1207 -> 390 x 1147.6dp) 실측:
//
//   배경        #FEF9F5
//   카드1       y 126.6..320.5 (h 193.9)  좌우 24.7..364.2
//   카드2       y 337.3..832.7 (h 495.4)  같은 좌우
//   카드 그림자   Δ[3,17,13,11,7,5,3,2,1,0] = 9dp 번짐
//   구분선      y 678.5  #E6E6E6  (카드2 안에 하나뿐)
//   고른 옵션칸  #FFF1EE + 코랄 테두리
//   안 고른 칸   #FFFFFF + 얕은 그림자
//   버튼        #FF6D78, h 58, x 24.7..363.1
//
// 🔴 바꾸기 전 상태(= 이 테스트가 막으려는 회귀):
//    - 상단 요약 카드가 아예 없었다
//    - 월 선택이 네모 Checkbox 였다 (시안은 동그란 라디오)
//    - '형식(PDF/엑셀)' 선택이 없었다
//    - 버튼 문구가 `선택한 N개월 내보내기` 였다

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/fn_data.dart';
import 'package:flow_note/screens/ds/settle_preview_ds_screen.dart';

const _vendor = FnVendor(
  id: '대한꽃도매',
  name: '대한꽃도매',
  lastDate: '07.24',
  months: {
    '01': 360000,
    '02': 340000,
    '03': 410000,
    '04': 395000,
    '05': 420000,
    '06': 480000,
    '07': 384000,
  },
);

List<ReceiptModel> _receipts(int n) => List.generate(
      n,
      (i) => ReceiptModel(
        id: '$i',
        date: DateTime(2026, 7, 24),
        storeName: '대한꽃도매',
        items: const [],
        totalAmount: 21333,
        rawOcrText: 't',
        createdAt: DateTime(2026, 7, 24),
      ),
    );

Future<void> _pump(
  WidgetTester t, {
  Size size = const Size(390, 1200),
  List<String> selected = const ['07'],
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        home: SettlePreviewDsScreen(
          vendor: _vendor,
          selectedMonths: selected,
          year: '2026',
          receipts: _receipts(18),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

/// 해당 글자를 감싸는 Container/AnimatedContainer 의 BoxDecoration.
List<BoxDecoration> _decosOf(Finder f) => [
      ...find
          .ancestor(of: f, matching: find.byType(Container))
          .evaluate()
          .map((e) => (e.widget as Container).decoration),
      ...find
          .ancestor(of: f, matching: find.byType(AnimatedContainer))
          .evaluate()
          .map((e) => (e.widget as AnimatedContainer).decoration),
    ].whereType<BoxDecoration>().toList();

void main() {
  testWidgets('예외 없이 그려진다', (t) async {
    await _pump(t);
    expect(t.takeException(), isNull);
    expect(find.text('정산서 미리보기'), findsOneWidget);
  });

  testWidgets('🔴 #144 상단 요약 카드가 있다', (t) async {
    await _pump(t);
    // 시안 카드1 — 이름 / 정보 보기 / 선택 기간 합계 / 큰 금액 / 개월·건수
    expect(find.text('대한꽃도매'), findsOneWidget);
    expect(find.text('정보 보기'), findsOneWidget);
    expect(find.text('선택 기간 합계'), findsOneWidget);
    expect(find.text('1개월 · 영수증 18건'), findsOneWidget);
    // 7월만 골랐으므로 합계는 384,000원. 카드1과 카드2 합계 두 군데.
    expect(find.text('384,000원'), findsWidgets);
  });

  testWidgets('🔴 #144 카드가 흰색 + 큰 그림자다', (t) async {
    await _pump(t);
    final decos = _decosOf(find.text('선택 기간 합계'))
        .where((d) => d.color == const Color(0xFFFFFFFF))
        .toList();
    expect(decos, isNotEmpty, reason: '요약 카드가 흰색이 아니다');
    final shadows =
        decos.expand((d) => d.boxShadow ?? const <BoxShadow>[]).toList();
    expect(shadows, isNotEmpty, reason: '카드에 그림자가 없다');
    // 시안 Δ[3,17,13,11,7,5,3,2,1,0] = 9dp 번짐.
    final maxBlur =
        shadows.map((e) => e.blurRadius).reduce((a, b) => a > b ? a : b);
    expect(maxBlur, greaterThanOrEqualTo(10.0), reason: '그림자가 너무 얕다');
  });

  testWidgets('🔴 #144 월 선택이 네모 체크박스가 아니다', (t) async {
    await _pump(t);
    // 시안은 동그란 라디오다. Material Checkbox 가 남아 있으면 안 된다.
    expect(find.byType(Checkbox), findsNothing,
        reason: '예전 네모 Checkbox 가 남아 있다');
    // 동그란 라디오가 월 수만큼 있다 (7개월 + 형식 2칸).
    final circles = find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(circles, findsWidgets);
  });

  testWidgets('🔴 #144 고른 달은 코랄로 표시된다', (t) async {
    await _pump(t);
    // 7월만 골라져 있다.
    final sel = t.widget<Text>(find.text('7월'));
    expect(sel.style!.color, const Color(0xFFFF6D78),
        reason: '고른 달 글자가 코랄이 아니다');
    final unsel = t.widget<Text>(find.text('6월'));
    expect(unsel.style!.color, isNot(const Color(0xFFFF6D78)),
        reason: '안 고른 달까지 코랄이다');
  });

  testWidgets('🔴 #144 형식(PDF/엑셀) 선택이 있다', (t) async {
    await _pump(t);
    expect(find.text('형식'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('엑셀 (.xlsx)'), findsOneWidget);
    expect(find.text('범용 문서 형식'), findsOneWidget);
    expect(find.text('데이터 편집 가능'), findsOneWidget);
  });

  testWidgets('🔴 #144 고른 형식 칸은 #FFF1EE, 안 고른 칸은 흰색', (t) async {
    await _pump(t);
    // 🔴 `_decosOf(...).first` 를 쓰면 안 된다. 글자의 조상에는 바깥
    //    카드/배경 Container 도 섞여 있어서 엉뚱한 흰색을 집는다.
    //    (#142 에서 같은 함정을 한 번 밟았다)
    //    칸 본체 = 글자를 감싸는 **가장 가까운** AnimatedContainer 다.
    Color bgOf(String label) {
      final d = find
          .ancestor(of: find.text(label), matching: find.byType(AnimatedContainer))
          .evaluate()
          .map((e) => (e.widget as AnimatedContainer).decoration)
          .whereType<BoxDecoration>()
          .where((e) => e.color != null && e.shape != BoxShape.circle)
          .toList();
      expect(d, isNotEmpty, reason: '$label 칸 배경을 못 찾았다');
      return d.first.color!;
    }

    // 기본은 PDF 가 골라져 있다.
    expect(bgOf('범용 문서 형식'), const Color(0xFFFFF1EE),
        reason: '시안 고른 칸은 #FFF1EE 다');
    expect(bgOf('데이터 편집 가능'), const Color(0xFFFFFFFF),
        reason: '시안 안 고른 칸은 흰색이다');

    // 눌러 바꾸면 색이 뒤바뀐다.
    await t.tap(find.text('엑셀 (.xlsx)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(bgOf('데이터 편집 가능'), const Color(0xFFFFF1EE));
    expect(bgOf('범용 문서 형식'), const Color(0xFFFFFFFF));
  });

  testWidgets('🔴 #144 저장 방식은 두 달 이상일 때만 나온다', (t) async {
    await _pump(t);
    // 한 달만 고르면 통합/분리가 같은 결과라 뜻이 없다.
    expect(find.text('저장 방식'), findsNothing);

    await t.tap(find.text('6월'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('저장 방식'), findsOneWidget);
    expect(find.text('전체 통합'), findsOneWidget);
    expect(find.text('월별 분리'), findsOneWidget);
    expect(find.text('1개의 파일로 저장'), findsOneWidget);
    expect(find.text('월마다 각각 저장'), findsOneWidget);
  });

  testWidgets('🔴 #144 내보내기 버튼이 코랄 알약이다', (t) async {
    await _pump(t);
    final btn = find.text('내보내기');
    expect(btn, findsOneWidget, reason: '시안 버튼 문구는 `내보내기` 다');
    // 예전 문구가 남아 있으면 안 된다.
    expect(find.textContaining('개월 내보내기'), findsNothing);
    final d = _decosOf(btn).where((e) => e.color != null).toList();
    expect(d.first.color, const Color(0xFFFF6D78));
    // 시안 실측 높이 58dp (y 1068..1126).
    final box = find
        .ancestor(of: btn, matching: find.byType(Container))
        .first;
    expect(t.getSize(box).height, closeTo(58, 2));
  });

  testWidgets('🔴 #144 합계가 코랄로 강조된다', (t) async {
    await _pump(t);
    final totals = t
        .widgetList<Text>(find.text('384,000원'))
        .map((e) => e.style?.color)
        .toList();
    expect(totals, contains(const Color(0xFFFF6D78)),
        reason: '시안 합계 금액은 코랄이다');
  });

  testWidgets('기능 유지 — 월을 누르면 합계가 바뀐다', (t) async {
    await _pump(t);
    expect(find.text('1개월 · 영수증 18건'), findsOneWidget);
    await t.tap(find.text('6월'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('2개월 · 영수증 18건'), findsOneWidget);
    // 384,000 + 480,000 = 864,000
    expect(find.text('864,000원'), findsWidgets);
  });

  testWidgets('기능 유지 — 전체 선택/해제가 동작한다', (t) async {
    await _pump(t);
    expect(find.text('전체 선택'), findsOneWidget);
    await t.tap(find.text('전체 선택'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('전체 해제'), findsOneWidget);
    expect(find.text('7개월 · 영수증 18건'), findsOneWidget);
    await t.tap(find.text('전체 해제'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('0개월 · 영수증 18건'), findsOneWidget);
  });

  testWidgets('🔴 #144 엑셀을 고르고 누르면 거짓 성공 대신 안내가 뜬다', (t) async {
    await _pump(t);
    await t.tap(find.text('엑셀 (.xlsx)'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('내보내기'));
    await t.pump(const Duration(milliseconds: 400));
    // 🔴 엑셀 생성기가 없다. 조용히 PDF 를 뱉으면 사장님은 엑셀을
    //    받은 줄 알고 세무사에게 보낸다.
    expect(find.textContaining('엑셀 내보내기는 아직 준비 중'), findsOneWidget);
  });

  testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
    await _pump(t, size: const Size(320, 1200));
    expect(t.takeException(), isNull);
  });
}
