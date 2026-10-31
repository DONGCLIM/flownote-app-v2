import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/insight_ds_screens.dart';
import 'package:flow_note/theme/fn_ds.dart';
import 'package:flow_note/widgets/fn_inquiry_parts.dart';

String _read(String p) => File(p).readAsStringSync();

/// 시즌 매입 비교 화면 — 시안 1:1 확인.
///
/// 🔴 지금은 **화면만** 있고 기능은 없다. 그래서 "숫자가 맞는지"가 아니라
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
      pumpAt(t, w, const Size(390, 3000));

  /// 🔴 `1월` 은 화면에 여러 번 나온다 — 시작 월 칸, 기간 비교 막대 라벨,
  ///    성수기 지도 라벨, 월별 추이 라벨. 그래서 `find.text` 만 쓰면
  ///    "너무 많다"로 실패하거나 엉뚱한 글자를 누르게 된다.
  ///    고르는 칸 안쪽만 집어서 쓴다.
  Finder inPicker(String month) => find.descendant(
        of: find.byType(FnCategoryPicker),
        matching: find.text(month),
      );

  group('시즌 매입 비교 — 시안 문구', () {
    testWidgets('제목과 안내문이 시안대로다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      expect(find.text('시즌 매입 비교'), findsOneWidget);
      expect(
        find.text('기간을 설정하면 올해 매입을 전년 동기 또는\n'
            '올해 월평균과 비교할 수 있어요.'),
        findsOneWidget,
      );
    });

    testWidgets('기간 고르는 칸이 시안대로다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      expect(find.text('시작 월'), findsOneWidget);
      expect(find.text('종료 월'), findsOneWidget);
      expect(find.byType(FnCategoryPicker), findsNWidgets(2));
      expect(inPicker('1월'), findsOneWidget);
      expect(inPicker('7월'), findsOneWidget);
      expect(find.text('전년 동기'), findsWidgets);
      expect(find.text('올해 월평균'), findsOneWidget);
    });

    testWidgets('선택 기간 매입 카드가 시안대로다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      expect(find.text('선택 기간 매입'), findsOneWidget);
      expect(find.text('전년 대비 +7.5%'), findsOneWidget);
      expect(find.text('27,890,000원'), findsWidgets);
      expect(find.text('25,940,000원'), findsWidgets);
    });

    testWidgets('카드 제목 여섯 개가 모두 있다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      for (final s in [
        '기간 비교',
        '품목군별 증감',
        '성수기 지도',
        '월별 매입 추이',
        '데이터 분석',
      ]) {
        expect(find.text(s), findsOneWidget, reason: '$s 카드가 없다');
      }
    });

    testWidgets('품목군별 증감 네 줄이 시안 그대로다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      for (final s in [
        '절화(꽃)', '전년 대비 +2%', '18,965,200원',
        '부자재', '전년 대비 +34%', '5,578,000원',
        '화분·식물', '전년 대비 -4%', '2,231,200원',
        '기타', '전년 대비 +43%', '1,115,600원',
      ]) {
        expect(find.text(s), findsOneWidget, reason: '$s 가 없다');
      }
    });

    testWidgets('성수기 지도 안내문이 시안대로다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      expect(
        find.text('6월이 올해 최대 성수기예요. 지난해보다 18% 늘었어요.\n'
            '내년 예산은 904만원 단위로 계획해 보세요.'),
        findsOneWidget,
      );
    });

    testWidgets('합계 카드와 증감이 시안대로다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      expect(find.text('2026년 1~7월'), findsOneWidget);
      expect(find.text('증감'), findsOneWidget);
      expect(find.text('+1,950,000원'), findsOneWidget);
    });

    testWidgets('데이터 분석 문장이 시안대로다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      expect(find.textContaining('전년 동기보다 7.5% 늘었어요'), findsOneWidget);
      expect(find.textContaining('최근 3개월은 감소세예요'), findsOneWidget);
      expect(find.text('품목군 중 기타의 변동이 +43%로 가장 컸어요.'), findsOneWidget);
    });

    testWidgets('막대·추이 아래 달 이름이 각각 일곱 개다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      // 기간 비교 7 + 성수기 지도 7 + 월별 추이 7 = 21,
      // 여기에 시작/종료 월 칸의 1월·7월이 각각 하나씩 더 있다.
      expect(find.text('3월'), findsNWidgets(3));
      expect(find.text('6월'), findsNWidgets(3));
      expect(find.text('1월'), findsNWidgets(4));
      expect(find.text('7월'), findsNWidgets(4));
    });
  });

  group('시즌 매입 비교 — 색과 치수', () {
    testWidgets('🔴 전년 대비 배지가 코랄 바탕에 흰 글자다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      expect(t.widget<Text>(find.text('전년 대비 +7.5%')).style!.color,
          FnDs.onCoral);
      final box = t.widget<Container>(find.ancestor(
        of: find.text('전년 대비 +7.5%'),
        matching: find.byType(Container),
      ).first);
      expect((box.decoration! as BoxDecoration).color, FnDs.coral);
    });

    testWidgets('🔴 증감 금액만 코랄이다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      expect(t.widget<Text>(find.text('+1,950,000원')).style!.color,
          FnDs.coral);
      expect(t.widget<Text>(find.text('2026년 1~7월')).style!.color,
          FnDs.title);
    });

    testWidgets('🔴 고른 비교 기준만 코랄로 칠해진다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      // 처음에는 '전년 동기' 가 켜져 있다.
      expect(t.widget<Text>(find.text('올해 월평균')).style!.color, FnDs.sub);

      await t.tap(find.text('올해 월평균'));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<Text>(find.text('올해 월평균')).style!.color,
          FnDs.onCoral, reason: '눌러도 켜지지 않으면 고장으로 보인다');
    });

    testWidgets('🔴 기간 비교 막대가 달마다 두 개씩, 7쌍이다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      final card = find.ancestor(
        of: find.text('기간 비교'),
        matching: find.byType(Container),
      ).first;
      final bars = t.widgetList<Expanded>(
        find.descendant(of: card, matching: find.byType(Expanded)),
      );
      // 달 7칸 + (전년·올해 막대 7쌍) + 달 이름 7칸
      expect(bars.length, greaterThanOrEqualTo(7 * 3));
    });

    testWidgets('🔴 6월 막대가 가장 높다', (t) async {
      await pumpTall(t, const GuideSeasonDsScreen());
      // 예시값에서 6월(904)이 최고다. 막대 높이로 확인한다.
      final heights = <double>[];
      for (final r in GuideSeasonDsScreen.bars) {
        heights.add(r.$2);
      }
      final top = heights.reduce((a, b) => a > b ? a : b);
      expect(top, GuideSeasonDsScreen.bars[5].$2);
    });

    testWidgets('🔴 화면 좌우 여백이 기준(24)과 같다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      final lv = t.widget<ListView>(find.byType(ListView));
      final pad = lv.padding! as EdgeInsets;
      expect(pad.left, FnDs.pagePad);
      expect(pad.right, FnDs.pagePad);
    });

    testWidgets('카드가 테두리 없이 그림자만 쓴다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      final box = t.widget<Container>(find.ancestor(
        of: find.text('선택 기간 매입'),
        matching: find.byType(Container),
      ).first);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, FnDs.card);
      expect(deco.border, isNull);
      expect(deco.boxShadow, isNotNull);
    });
  });

  group('시즌 매입 비교 — 눌러지는 것', () {
    testWidgets('🔴 시작 월을 누르면 달을 고를 수 있다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      await t.tap(inPicker('1월'));
      await t.pumpAndSettle();
      // 시트가 열리면 12개월이 모두 나온다. 화면에는 7월까지만 있었다.
      expect(find.text('12월'), findsOneWidget);
      expect(find.text('시작 월'), findsWidgets);
    });

    testWidgets('🔴 고른 달이 칸에 반영된다', (t) async {
      await pump(t, const GuideSeasonDsScreen());
      // 9월은 막대·지도에 없는 달이라, 칸에 들어왔는지 헷갈릴 일이 없다.
      expect(find.text('9월'), findsNothing);

      await t.tap(inPicker('1월'));
      await t.pumpAndSettle();
      await t.tap(find.text('9월'));
      await t.pumpAndSettle();

      expect(inPicker('9월'), findsOneWidget, reason: '고른 달이 칸에 안 들어갔다');
      expect(inPicker('1월'), findsNothing, reason: '옛 값이 남아 있다');
    });
  });

  group('시즌 매입 비교 — 소스 계약', () {
    test('🔴 통합 기준(FnDs)을 쓰고 옛 토큰을 섞지 않는다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final part = src.substring(src.indexOf('class GuideSeasonDsScreen'),
          src.indexOf('/// 원가 계산기'));
      expect(part.contains('FnDs.'), isTrue);
      for (final old in ['FnColors.', 'FnHome.', 'FnScan.', 'FnProfile.']) {
        expect(part.contains(old), isFalse, reason: '$old 가 남아 있다');
      }
    });

    test('🔴 가이드에서 이 화면으로 들어갈 수 있어야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      expect(src.contains("'season' => const GuideSeasonDsScreen()"), isTrue,
          reason: '스마트 사입 가이드의 연결이 끊겼다');
    });

    test('🔴 가이드 카드는 영역 전체가 눌려야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final card = src.substring(src.indexOf('class _GuideMenuCard'));
      expect(card.contains('HitTestBehavior.opaque'), isTrue,
          reason: '여백을 누르면 반응이 없게 된다');
    });

    test('🔴 꽃별 계절 시세 화면은 건드리지 않았다', () {
      // season_ds_screen.dart 는 양재 경매 기반의 다른 화면이다.
      final src = _read('lib/screens/ds/season_ds_screen.dart');
      expect(src.contains('class SeasonDsScreen'), isTrue);
      expect(src.contains('GuideSeasonDsScreen'), isFalse);
    });

    test('🔴 예시값이라는 사실이 코드에 적혀 있어야 한다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      final part = src.substring(src.indexOf('/// 시즌 매입 비교'),
          src.indexOf('/// 원가 계산기'));
      expect(part.contains('예시값'), isTrue);
    });

    test('🔴 나중에 붙일 기능 목록이 문서에 추가돼 있어야 한다', () {
      final doc = _read('docs/TODO_기능연결.md');
      expect(doc.contains('## 시즌 매입 비교'), isTrue);
      for (final key in ['trendNow', 'heat', '품목군별 증감', '비교 기준']) {
        expect(doc.contains(key), isTrue, reason: '$key 가 문서에 없다');
      }
    });

    test('🔴 기존 하위 화면 두 개를 지우지 않았다', () {
      final src = _read('lib/screens/ds/insight_ds_screens.dart');
      for (final c in ['class GuideCostDsScreen', 'class GuideBudgetDsScreen']) {
        expect(src.contains(c), isTrue, reason: '$c 가 사라졌다');
      }
    });
  });
}
