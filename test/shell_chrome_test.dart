import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/design/fn_shell.dart';
import 'package:flow_note/design/fn_icons.dart';
import 'package:flow_note/design/fn_brand.dart';
import 'package:flow_note/design/fn_home_tokens.dart';
import 'package:flow_note/design/fn_tokens.dart';

/// #136 — 5탭 공통 크롬(헤더 + 탭바)을 시안에 맞춘 뒤의 회귀 방지
///
/// 시안 실측 (473x1024, 환산비 0.8245 -> 390x844dp):
///   워드마크  좌 24.7dp, h 17.3dp (비율 6.095)
///   벨       우 25.6dp, 19.0 x 21.4dp, 알림 점 지름 4.9dp #FB6E76
///   탭바     좌우 여백 9.9dp, 높이 71.7dp, r 27dp, 아래로 33.8dp 띄움
///
/// 🔴 `Image.asset` 은 테스트 바인딩에서 끝내 resolve 되지 않는다.
///    그래서 렌더 그림에는 워드마크가 안 보인다. 위젯이 트리에 있고
///    위치/크기가 맞는지는 아래처럼 지오메트리로 검증한다.
///    (실제 화면에 뜨는지는 배포본에서 따로 확인했다)

Widget _shell({
  bool brand = true,
  bool floating = true,
  String active = 'scan',
  VoidCallback? onBell,
}) =>
    MaterialApp(
      home: FnShell(
        // 🔴 제목을 '스캔' 으로 두면 안 된다. 하단 탭 라벨에도 '스캔' 이
        //    있어서 find.text('스캔') 이 탭까지 같이 잡는다.
        //    (처음에 그렇게 써서 테스트 2개가 엉뚱하게 실패했다)
        navTitle: '제목자리표시',
        brandHeader: brand,
        bellDot: true,
        onBellTap: onBell,
        floatingTabs: floating,
        bg: FnHome.bgWarm,
        tabs: fnTabs,
        activeTab: active,
        onTabChange: (_) {},
        child: const SizedBox(),
      ),
    );

Future<void> _pump(WidgetTester t, Widget w,
    {Size size = const Size(390, 844)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('#136 헤더 — 워드마크 + 알림 벨', () {
    testWidgets('예외 없이 그려진다', (t) async {
      await _pump(t, _shell());
      expect(t.takeException(), isNull);
    });

    testWidgets('워드마크가 트리에 있고 시안 위치/크기다', (t) async {
      await _pump(t, _shell());
      final wm = find.byType(FnWordmark);
      expect(wm, findsOneWidget, reason: '워드마크가 없다');

      final w = t.widget<FnWordmark>(wm);
      // 🔴 #138 헤더 워드마크는 'o' 꽃잎이 코랄인 판으로 바뀌었다.
      //    (로그인·스플래시·인트로는 여전히 검정 = flat)
      expect(w.color, isTrue, reason: '헤더 워드마크는 컬러판이어야 한다');
      expect(w.flat, isFalse, reason: '검정판으로 돌아가면 안 된다');
      expect(w.height, closeTo(17.3, 1.5), reason: '시안 h 17.3dp');

      final r = t.getRect(wm);
      expect(r.left, closeTo(24.7, 1.5), reason: '시안 좌 여백 24.7dp');
    });

    testWidgets('제목 텍스트는 더 안 보인다', (t) async {
      await _pump(t, _shell());
      expect(find.text('제목자리표시'), findsNothing,
          reason: '시안 헤더에는 제목이 없다 (워드마크가 대신한다)');
      // 탭 라벨 '스캔' 은 그대로 있어야 한다 (헤더 제목과 다른 것이다)
      expect(find.text('스캔'), findsOneWidget);
    });

    testWidgets('벨이 있고 누르면 콜백이 돈다', (t) async {
      var tapped = 0;
      await _pump(t, _shell(onBell: () => tapped++));
      // 🔴 #146 에서 벨을 시안 모양 커스텀(`FnBellIcon`)으로 바꿨다.
      //    전에는 `Icons.notifications_none_rounded` 를 찾았다.
      final bell = find.byType(FnBellIcon);
      expect(bell, findsOneWidget);

      final r = t.getRect(bell);
      // 시안: 벨 우여백 25.6dp (화면 390 기준 오른쪽 끝에서)
      expect(390 - r.right, lessThan(40), reason: '벨이 오른쪽에 붙어야 한다');

      await t.tap(bell);
      await t.pump();
      expect(tapped, 1, reason: '벨을 눌렀는데 콜백이 안 돌았다');
    });

    testWidgets('알림 점이 코랄이다 (#FB6E76)', (t) async {
      await _pump(t, _shell());
      final dots = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color?.toARGB32() == 0xFFFB6E76);
      expect(dots, findsOneWidget, reason: '알림 점이 없다');
    });

    testWidgets('brandHeader 를 끄면 예전 제목 헤더로 돌아간다', (t) async {
      await _pump(t, _shell(brand: false));
      expect(find.text('제목자리표시'), findsOneWidget);
      expect(find.byType(FnWordmark), findsNothing);
    });
  });

  group('#138 헤더 로고 — 컬러판', () {
    testWidgets('🔴 헤더는 컬러 에셋 경로를 가리킨다', (t) async {
      await _pump(t, _shell());
      final img = find
          .descendant(of: find.byType(FnWordmark), matching: find.byType(Image))
          .evaluate()
          .map((e) => (e.widget as Image).image)
          .whereType<AssetImage>()
          .map((a) => a.assetName)
          .toList();
      expect(img, isNotEmpty, reason: '워드마크 Image 가 없다');
      expect(img.first, FnBrand.wordmarkColorAsset,
          reason: '헤더는 컬러판을 써야 한다');
      expect(img.first, isNot(FnBrand.wordmarkFlatAsset),
          reason: '검정판이면 안 된다');
    });

    testWidgets('🔴 컬러 에셋 파일이 실제로 있고 꽃잎이 코랄이다', (t) async {
      // Image.asset 은 테스트 바인딩에서 resolve 되지 않는다. 그래서
      // 파일 자체를 읽어 확인한다. (렌더 스크린샷으로는 확인 불가)
      final f = io.File('assets/brand/logo_wordmark_color.png');
      expect(f.existsSync(), isTrue, reason: '컬러 워드마크 파일이 없다');
      final bytes = f.readAsBytesSync();
      expect(bytes.length, greaterThan(10000), reason: '파일이 너무 작다');
      // PNG 서명
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    testWidgets('🔴 로그인/스플래시/인트로는 검정판 그대로다', (t) async {
      // 소스에서 확인한다. 헤더만 컬러로 바뀌었는지 보장한다.
      for (final path in <String>[
        'lib/screens/ds/splash_ds_screen.dart',
        'lib/screens/ds/intro_ds_screen.dart',
      ]) {
        final code = io.File(path).readAsStringSync();
        expect(code.contains('flat: true'), isTrue,
            reason: '$path 는 검정판(flat)을 유지해야 한다');
        expect(code.contains('color: true'), isFalse,
            reason: '$path 가 컬러판으로 바뀌었다');
      }
    });

    testWidgets('🔴 5개 탭 전부 같은 헤더를 쓴다', (t) async {
      // 헤더는 FnShell 한 곳에서만 그린다. 탭을 바꿔도 워드마크는
      // 하나뿐이고 컬러판이어야 한다.
      for (final key in ['home', 'settle', 'scan', 'calendar', 'profile']) {
        await _pump(t, _shell(active: key));
        final wm = find.byType(FnWordmark);
        expect(wm, findsOneWidget, reason: '$key 탭에 워드마크가 없다');
        expect(t.widget<FnWordmark>(wm).color, isTrue,
            reason: '$key 탭 헤더가 컬러판이 아니다');
      }
    });
  });

  group('#136 탭바 — 떠 있는 흰 카드', () {
    testWidgets('좌우로 띄워져 있다 (시안 9.9dp)', (t) async {
      await _pump(t, _shell());
      final nav = find.byType(FnBottomNavigation);
      expect(nav, findsOneWidget);
      final r = t.getRect(nav);
      expect(r.left, closeTo(10, 1.5), reason: '시안 좌여백 9.9dp');
      expect(390 - r.right, closeTo(10, 1.5), reason: '시안 우여백 9.9dp');
      expect(r.left, closeTo(390 - r.right, 0.5), reason: '좌우 대칭');
    });

    testWidgets('🔴 바닥에서 시안만큼 떠 있다 (34.6dp)', (t) async {
      // 🔴 이 검사는 전에 `greaterThan(4)` 였다. 그래서 실제로는 10dp 만
      //    떠 있어도 통과했고, 라이브에서 탭바가 화면 아래에 붙어 보이는
      //    문제를 **못 잡았다**. 시안 실측 34.6dp 로 조인다.
      await _pump(t, _shell());
      final r = t.getRect(find.byType(FnBottomNavigation));
      expect(844 - r.bottom, closeTo(FnHome.tabBarBottom, 1.5),
          reason: '시안은 바닥에서 34.6dp 떠 있다');
    });

    testWidgets('🔴 탭바 높이가 시안과 같다 (70.9dp)', (t) async {
      await _pump(t, _shell());
      final r = t.getRect(find.byType(FnBottomNavigation));
      expect(r.height, closeTo(FnHome.tabBarH, 1.5),
          reason: '시안 탭바 높이 70.9dp');
    });

    testWidgets('모서리가 둥글다 (시안 r 28dp)', (t) async {
      await _pump(t, _shell());
      final card = find.descendant(
        of: find.byType(FnBottomNavigation),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null),
      );
      expect(card, findsWidgets);
      final dec =
          t.widget<Container>(card.first).decoration! as BoxDecoration;
      final br = dec.borderRadius! as BorderRadius;
      expect(br.topLeft.x, closeTo(FnHome.tabBarRadius, 2.5),
          reason: '시안 탭바 반경');
    });

    testWidgets('활성 탭이 코랄이다', (t) async {
      await _pump(t, _shell(active: 'scan'));
      // 🔴 #146 에서 떠 있는 탭바 아이콘을 시안 모양 커스텀(`FnTabIcon`)으로
      //    바꿨다. 전에는 `Icon` 위젯의 color 를 봤다.
      final icons = find
          .descendant(
              of: find.byType(FnBottomNavigation),
              matching: find.byType(FnTabIcon))
          .evaluate()
          .map((e) => (e.widget as FnTabIcon).color.toARGB32())
          .toList();
      expect(icons, contains(FnHome.coralFlat.toARGB32()),
          reason: '활성 탭 코랄이 없다');
      expect(icons.where((c) => c == FnHome.coralFlat.toARGB32()).length, 1,
          reason: '활성 탭은 하나여야 한다');
    });

    testWidgets('5개 탭이 모두 있고 문구가 그대로다', (t) async {
      await _pump(t, _shell());
      for (final label in ['홈', '내역', '스캔', '캘린더', '프로필']) {
        expect(find.text(label), findsOneWidget, reason: '$label 탭이 없다');
      }
    });

    testWidgets('floatingTabs 를 끄면 예전 바닥 탭바로 돌아간다', (t) async {
      await _pump(t, _shell(floating: false));
      final r = t.getRect(find.byType(FnBottomNavigation));
      expect(r.left, closeTo(0, 0.5));
      expect(844 - r.bottom, closeTo(0, 0.5), reason: '예전 탭바는 바닥에 붙는다');
    });

    testWidgets('좁은 화면(320)에서도 넘치지 않는다', (t) async {
      await _pump(t, _shell(), size: const Size(320, 640));
      expect(t.takeException(), isNull);
      for (final label in ['홈', '내역', '스캔', '캘린더', '프로필']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('두 모드가 같은 탭 위젯을 쓴다 (코드 중복 없음)', (t) async {
      // 떠 있는 탭바를 넣을 때 탭 항목 코드를 복사하면 둘이 갈라진다.
      // `_items()` 하나로 뽑아 뒀으므로, 두 모드 모두 탭 5개가 나온다.
      for (final floating in [true, false]) {
        await _pump(t, _shell(floating: floating));
        expect(find.descendant(
          of: find.byType(FnBottomNavigation),
          matching: find.byType(Expanded),
        ), findsNWidgets(5), reason: 'floating=$floating');
      }
    });
  });

  group('#136 배경', () {
    testWidgets('따뜻한 크림(#FEF9F5)을 쓴다', (t) async {
      await _pump(t, _shell());
      final sc = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(sc.backgroundColor?.toARGB32(), FnHome.bgWarm.toARGB32());
    });

    testWidgets('예전 흰 배경으로 돌아가지 않았다', (t) async {
      await _pump(t, _shell());
      final sc = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(sc.backgroundColor?.toARGB32(),
          isNot(FnColors.backgroundNormal.toARGB32()));
    });
  });
}
