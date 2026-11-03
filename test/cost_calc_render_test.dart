import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/theme/fn_ds.dart';

String _read(String p) => File(p).readAsStringSync();

/// 원가 계산기 화면 — 시안 1:1 확인.
///
/// 🔴 지금은 **화면만** 있고 기능은 없다. 그래서 "계산이 맞는지"가 아니라
///    "시안대로 그려지는지"만 본다. 실제 계산이 붙으면 값 테스트를 따로 넣는다.
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
      pumpAt(t, w, const Size(390, 3600));

  group('원가 계산기 — 시안 문구', () {
    testWidgets('제목과 안내문이 시안대로다', (t) async {
      await pump(t, const GuideCostDsScreen());
      expect(find.text('원가 계산기'), findsOneWidget);
      expect(
        find.text('최근 영수증의 매입 단가에\n'
            '로스율과 직접비를 더해 판매가와 마진율을 계산해요.'),
        findsOneWidget,
      );
    });

    testWidgets('상품 구성 칩 다섯 개가 사장님 지정대로다', (t) async {
      await pump(t, const GuideCostDsScreen());
      // 🔴 칩 줄은 가로 ListView 라 화면을 넘어가는 칩은 그려지지 않는다.
      //    마지막 '직접입력' 을 보려면 밀어야 한다.
      for (final s in ['꽃다발', '꽃바구니', '화병꽂이']) {
        expect(find.text(s), findsOneWidget, reason: '$s 칩이 없다');
      }
      await t.drag(find.text('꽃다발'), const Offset(-220, 0));
      await t.pump(const Duration(milliseconds: 200));
      for (final s in ['플라워박스', '직접입력']) {
        expect(find.text(s), findsOneWidget, reason: '$s 칩이 없다');
      }
    });

    testWidgets('상품 구성 카드의 품목 세 개가 시안 그대로다', (t) async {
      await pump(t, const GuideCostDsScreen());
      expect(find.text('상품 구성'), findsOneWidget);
      expect(find.text('3개 품목 · 111,000원'), findsOneWidget);
      for (final s in [
        '장미(레드)', '10단', '8,000원', '80,000원',
        '거베라', '5단', '6,000원', '30,000원',
        '포장지', '2장', '500원', '1,000원',
      ]) {
        expect(find.text(s), findsWidgets, reason: '$s 가 없다');
      }
      expect(find.text('품목명'), findsNWidgets(3));
      expect(find.text('직전 영수증 단가 기준'), findsNWidgets(3));
      expect(find.text('항목 추가'), findsOneWidget);
    });

    testWidgets('작업비·로스율·판매 배수가 시안대로다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(find.text('작업비 · 부대비용'), findsOneWidget);
      expect(find.text('3,000원'), findsWidgets);
      expect(find.text('로스율'), findsOneWidget);
      expect(find.text('8%'), findsOneWidget);
      expect(find.text('판매 배수'), findsOneWidget);
      for (final s in ['×2', '×2.5', '×3']) {
        expect(find.text(s), findsOneWidget, reason: '$s 배수가 없다');
      }
    });

    testWidgets('원가 구성 다섯 줄이 시안 그대로다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(find.text('원가 구성'), findsOneWidget);
      for (final s in [
        '꽃', '110,000원',
        '부자재', '1,000원',
        '로스', '8,880원',
        '작업비',
        '총 원가', '122,880원',
      ]) {
        expect(find.text(s), findsWidgets, reason: '$s 가 없다');
      }
    });

    testWidgets('권장 판매가 카드가 시안대로다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(find.text('권장 판매가'), findsOneWidget);
      expect(find.text('307,200원'), findsNWidgets(2));
      expect(find.text('총 원가 × 2.5배 · 100원 단위 반올림'), findsOneWidget);
      expect(find.text('마진율'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('대당 이익'), findsOneWidget);
      expect(find.text('184,320원'), findsOneWidget);
    });

    testWidgets('가격대 제안 세 줄이 시안 그대로다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(find.text('가격대 제안'), findsOneWidget);
      for (final s in [
        '기본 ×2', '마진 50%', '245,800원',
        '추천 ×2.5', '마진 60%',
        '프리미엄 ×3.2', '마진 69%', '393,200원',
      ]) {
        expect(find.text(s), findsOneWidget, reason: '$s 가 없다');
      }
    });

    testWidgets('맨 아래 안내 두 줄이 있다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(
        find.text('동일 구성으로 최근 30일간 12건 판매했고,\n'
            '평균 판매가는 318,500원이었어요.'),
        findsOneWidget,
      );
    });
  });

  group('원가 계산기 — 색과 치수', () {
    testWidgets('🔴 권장 판매가가 코랄이다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      final big = t.widgetList<Text>(find.text('307,200원')).first;
      expect(big.style!.color, FnDs.coral);
    });

    testWidgets('🔴 가격대 제안은 추천 줄만 코랄이다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      Color c(String s) => t.widget<Text>(find.text(s)).style!.color!;
      expect(c('245,800원'), FnDs.title);
      expect(c('393,200원'), FnDs.title);
      // 추천(307,200원)은 권장 판매가와 글자가 같아 두 개다. 마지막이 제안 줄.
      final tiers = t.widgetList<Text>(find.text('307,200원')).last;
      expect(tiers.style!.color, FnDs.coral);
    });

    testWidgets('🔴 처음에 꽃다발과 ×2.5 가 켜져 있다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      expect(t.widget<Text>(find.text('꽃다발')).style!.color, FnDs.onCoral);
      expect(t.widget<Text>(find.text('꽃바구니')).style!.color, FnDs.sub);
      expect(t.widget<Text>(find.text('×2.5')).style!.color, FnDs.onCoral);
      expect(t.widget<Text>(find.text('×2')).style!.color, FnDs.sub);
    });

    testWidgets('🔴 다른 칩을 누르면 그쪽이 켜진다', (t) async {
      await pump(t, const GuideCostDsScreen());
      await t.tap(find.text('꽃바구니'));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<Text>(find.text('꽃바구니')).style!.color, FnDs.onCoral);
      expect(t.widget<Text>(find.text('꽃다발')).style!.color, FnDs.sub);
    });

    testWidgets('🔴 직접입력은 칠해지기만 하고 이름 칸은 아직 없다', (t) async {
      await pump(t, const GuideCostDsScreen());
      // 칩 줄을 끝까지 밀어야 '직접입력' 이 화면에 들어온다.
      await t.drag(find.text('꽃다발'), const Offset(-220, 0));
      await t.pump(const Duration(milliseconds: 200));

      await t.tap(find.text('직접입력'));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<Text>(find.text('직접입력')).style!.color, FnDs.onCoral);
      // 이름을 적는 칸은 사장님 지시로 아직 만들지 않았다.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('🔴 판매 배수를 누르면 그쪽이 켜진다', (t) async {
      await pumpTall(t, const GuideCostDsScreen());
      await t.tap(find.text('×3'));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<Text>(find.text('×3')).style!.color, FnDs.onCoral);
      expect(t.widget<Text>(find.text('×2.5')).style!.color, FnDs.sub);
    });

    testWidgets('🔴 화면 좌우 여백이 기준(24)과 같다', (t) async {
      await pump(t, const GuideCostDsScreen());
      // 바깥 ListView 가 화면 목록이다. 칩 줄도 ListView 라 first 로 집는다.
      final lv = t.widget<ListView>(find.byType(ListView).first);
      final pad = lv.padding! as EdgeInsets;
      expect(pad.left, FnDs.pagePad);
      expect(pad.right, FnDs.pagePad);
    });

    testWidgets('입력칸 높이가 기준(48)과 같다', (t) async {
      await pump(t, const GuideCostDsScreen());
      final box = t.widget<Container>(find.ancestor(
        of: find.text('장미(레드)'),
        matching: find.byType(Container),
      ).first);
      expect(box.constraints?.maxHeight ?? 0, FnDs.inputH);
    });

    testWidgets('카드가 테두리 없이 그림자만 쓴다', (t) async {
      await pump(t, const GuideCostDsScreen());
      final box = t.widget<Container>(find.ancestor(
        of: find.text('상품 구성'),
        matching: find.byType(Container),
      ).last);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, FnDs.card);
      expect(deco.border, isNull);
      expect(deco.boxShadow, isNotNull);
    });
  });

  group('원가 계산기 — 소스 계약', () {
    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final part = src.substring(src.indexOf('/// 원가 계산기 — 사장님 시안'),
          src.indexOf('/// 예산 검토'));
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

    test('🔴 예시값이라는 사실이 코드에 적혀 있어야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final part = src.substring(src.indexOf('/// 원가 계산기 — 사장님 시안'),
          src.indexOf('/// 예산 검토'));
      expect(part.contains('예시값'), isTrue);
    });

    test('🔴 나중에 붙일 기능 목록이 문서에 있어야 한다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('## 원가 계산기'), isTrue);
      for (final key in ['로스율', '판매 배수', '상품 구성']) {
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
