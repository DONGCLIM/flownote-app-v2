import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/insight_ds_screens.dart';
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
}
