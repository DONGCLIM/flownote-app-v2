import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_fit.dart';
import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/intro_ds_screen.dart';
import 'package:flow_note/screens/ds/splash_ds_screen.dart';

/// 🔴 #132 — 세 환경에서 비율이 제각각이던 문제.
///
/// 사장님 지적:
///   "모바일에서는 스크롤을 내려야 전체를 다 볼 수 있다.
///    홈화면 추가해서 앱처럼 쓸 때는 전체가 다 보인다.
///    PC로 보면 그냥 전부 확대인데 비율이 다 제각각이다."
///
/// 원인은 화면 크기가 아니라 **쓸 수 있는 높이**였다.
/// 로그인 콘텐츠 자연 높이 817dp 에 대해
///   폰 브라우저 744 (주소창+하단바가 ~100dp 먹음) -> 73dp 부족
///   홈화면 앱   844 -> 들어감
///   PC         900 -> 들어감 + 가로가 1392px 까지 늘어남
///
/// 요구사항: "스크롤 없이도 전체가 한눈에, 화면 안에는 딱 맞게,
///            기능은 모두 그대로, 앱 이미지 크기만 조정"
void main() {
  /// 실제 환경 (가로, 세로) — 주소창/하단바를 뺀 '쓸 수 있는' 크기.
  const envs = <(String, Size)>[
    ('폰 브라우저(주소창)', Size(390, 744)),
    ('폰 브라우저(좁은 기기)', Size(360, 640)),
    ('폰 브라우저(아이폰 SE 가로폭)', Size(375, 667)),
    ('홈화면 앱(전체화면)', Size(390, 844)),
    ('PC', Size(1440, 900)),
    ('PC 와이드', Size(1920, 1080)),
    ('태블릿', Size(768, 1024)),
  ];

  Widget wrapLogin() => ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: SplashDsScreen()),
      );

  group('#132 로그인 — 스크롤 없이 전체가 한눈에', () {
    for (final (name, size) in envs) {
      testWidgets('🔴 $name 에서 스크롤이 생기지 않는다', (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrapLogin());
        await t.pump(const Duration(milliseconds: 500));

        // 세로로 스크롤해야 할 양이 0 이어야 한다. (가로 스크롤러는
        // 무시한다 — 세로로 내려야 보이는지가 쟁점이다)
        var worst = 0.0;
        for (final el in find.byType(Scrollable).evaluate()) {
          final st = el.widget as Scrollable;
          if (st.axis != Axis.vertical) continue;
          final pos = (el as StatefulElement).state as ScrollableState;
          worst = worst > pos.position.maxScrollExtent
              ? worst
              : pos.position.maxScrollExtent;
        }
        expect(worst, lessThanOrEqualTo(0.5),
            reason: '$name: ${worst.toStringAsFixed(1)}dp 만큼 내려야 한다');
      });
    }
  });

  group('#132 PC 에서 가로로 늘어나지 않는다', () {
    for (final (name, size) in [
      ('PC', const Size(1440, 900)),
      ('PC 와이드', const Size(1920, 1080)),
      ('태블릿', const Size(768, 1024)),
    ]) {
      testWidgets('🔴 $name 에서 내용 폭이 시안 폭을 넘지 않는다', (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrapLogin());
        await t.pump(const Duration(milliseconds: 500));

        // 로그인 버튼의 실제 렌더 폭을 본다. 예전에는 화면 폭만큼
        // (1440 에서 1392px) 늘어났다.
        final box = t.renderObject<RenderBox>(
            find.ancestor(
                    of: find.text('로그인'), matching: find.byType(Container))
                .first);
        // 예전에는 1440 화면에서 1392px 까지 늘어났다. 이제는
        // FnFit.phoneMaxWidth(520) 에서 좌우 여백 48 을 뺀 폭이 상한이다.
        expect(box.size.width, lessThanOrEqualTo(FnFit.phoneMaxWidth - 48 + 1),
            reason: '$name: 버튼 폭 ${box.size.width} — 가로로 늘어났다');
        // 그리고 화면 폭보다 훨씬 좁아야 한다(= 가운데 묶였다).
        expect(box.size.width, lessThan(size.width * 0.75),
            reason: '$name: 화면 폭 대비 너무 넓다');
      });
    }
  });

  group('#132 인트로도 같은 폭으로 묶인다', () {
    for (final (name, size) in [
      ('PC', const Size(1440, 900)),
      ('태블릿', const Size(768, 1024)),
    ]) {
      testWidgets('🔴 $name 에서 인트로 폭이 390 을 넘지 않는다', (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(MaterialApp(home: IntroDsScreen(onDone: () {})));
        await t.pump(const Duration(milliseconds: 400));
        final img = t.renderObject<RenderBox>(find.byType(Image).first);
        expect(img.size.width, lessThanOrEqualTo(FnFit.phoneMaxWidth + 1),
            reason: '$name: 일러스트 폭 ${img.size.width} — 늘어났다');
        expect(img.size.width, lessThan(size.width * 0.75),
            reason: '$name: 화면 폭 대비 너무 넓다');
      });
    }
  });

  group('#133 좌우로 쏠리지 않는다', () {
    // 🔴 사장님 지적: "웹앱으로 쓸 때 로그인 화면이 왼쪽으로 쏠려 있다."
    //
    // 원인은 내가 넣은 축소 코드였다. 상자 폭은 w 로 두고 좌상단 기준
    // 으로 줄였더니, 그려지는 폭이 w*배율 로 줄어들면서 남는 자리가
    // **전부 오른쪽 빈칸**이 됐다. 실측(지난 턴 내 스크린샷):
    //   폰 브라우저 좌여백 18 / 우여백 103  -> 85px 왼쪽 쏠림
    //   홈화면 앱   좌여백 21 / 우여백  64  -> 43px 왼쪽 쏠림
    //
    // 고친 뒤에는 축소 후 폭이 화면 폭과 같아져 쏠림이 0 이 된다.
    for (final (name, size) in [
      ('폰 브라우저', Size(390, 744)),
      ('홈화면 앱', Size(390, 844)),
      ('갤럭시 S', Size(412, 800)),
      ('좁은 기기', Size(360, 640)),
      ('PC', Size(1440, 900)),
    ]) {
      testWidgets('🔴 $name 에서 내용이 가운데 온다', (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrapLogin());
        await t.pump(const Duration(milliseconds: 500));

        // 로그인 버튼이 화면 가운데 있어야 한다. 축소 배율이 섞여
        // 있으므로 **화면 좌표**로 환산해서 본다.
        final box = t.renderObject<RenderBox>(
            find.ancestor(
                    of: find.text('로그인'), matching: find.byType(Container))
                .first);
        final tl = box.localToGlobal(Offset.zero);
        final br = box.localToGlobal(Offset(box.size.width, 0));
        final left = tl.dx;
        final right = size.width - br.dx;
        expect((right - left).abs(), lessThan(4.0),
            reason: '$name: 좌여백 ${left.toStringAsFixed(1)} / '
                '우여백 ${right.toStringAsFixed(1)} -> '
                '${(right - left).toStringAsFixed(1)}px 쏠렸다');
      });
    }

    test('🔴 index.html 이 보이는 높이(dvh)로 묶는다', () {
      // 실제 폰 브라우저는 주소창이 보이는 동안 innerHeight 가 큰 값으로
      // 남아, 플러터가 보이는 영역보다 길게 그린다. 100dvh 로 묶어야
      // 스크롤이 사라진다. (홈화면 앱은 주소창이 없어 원래 문제없었다)
      final html = io.File('web/index.html').readAsStringSync();
      expect(html.contains('100dvh'), isTrue,
          reason: 'dvh 로 묶지 않으면 폰 브라우저에서 다시 스크롤된다');
      expect(html.contains('overflow: hidden'), isTrue);
    });

    test('🔴 축소 후 폭이 화면 폭과 같도록 계산한다', () {
      final code = io.File('lib/design/fn_fit.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // 내용을 w/배율 폭으로 그려야 축소 후 폭이 w 가 된다.
      expect(code.contains('w / s'), isTrue,
          reason: '폭 보정이 없으면 다시 왼쪽으로 쏠린다');
    });
  });

  group('#132 휴대폰에서는 폭을 묶지 않는다', () {
    // 🔴 390 으로 묶었다가 412·430 기기에서 좌우 흰 띠가 생겼다.
    //    #129 에서 없앤 문제가 되살아난 것을 테스트가 잡았다.
    for (final (name, size) in [
      ('갤럭시 S', const Size(412, 915)),
      ('픽셀 7', const Size(412, 892)),
      ('아이폰 Pro Max', const Size(430, 932)),
    ]) {
      testWidgets('🔴 $name 에서 인트로가 화면 폭을 꽉 채운다', (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(MaterialApp(home: IntroDsScreen(onDone: () {})));
        await t.pump(const Duration(milliseconds: 400));
        final img = t.renderObject<RenderBox>(find.byType(Image).first);
        expect(img.size.width, closeTo(size.width, 0.5),
            reason: '$name: 그림 폭 ${img.size.width} != 화면 폭 '
                '${size.width} -> 좌우에 흰 띠가 생긴다');
      });
    }
  });

  group('#132 기능은 하나도 사라지지 않았다', () {
    testWidgets('🔴 작은 화면에서도 모든 버튼이 눌린다', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrapLogin());
      await t.pump(const Duration(milliseconds: 500));
      // 축소해도 글자와 버튼은 그대로 있어야 한다.
      expect(find.text('이메일'), findsOneWidget);
      expect(find.text('비밀번호'), findsOneWidget);
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('비밀번호를 잊으셨나요?'), findsOneWidget);
      expect(find.text('회원가입'), findsOneWidget);
      expect(find.text('카카오'), findsOneWidget);
      expect(find.text('네이버'), findsOneWidget);
      expect(find.text('구글'), findsOneWidget);
    });

    testWidgets('🔴 글자 크기 자체는 바뀌지 않는다 (축소만 한다)', (t) async {
      // 환경마다 fontSize 를 다르게 주면 유지보수가 지옥이 된다.
      // FnDesignFit 은 '그린 뒤 통째로 축소' 라서 스타일은 그대로다.
      for (final s in [const Size(390, 744), const Size(1440, 900)]) {
        await t.binding.setSurfaceSize(s);
        await t.pumpWidget(wrapLogin());
        await t.pump(const Duration(milliseconds: 500));
        final txt = t.widget<Text>(find.text('로그인'));
        expect(txt.style?.fontSize, 16,
            reason: '$s 에서 폰트 크기가 바뀌었다');
      }
      addTearDown(() => t.binding.setSurfaceSize(null));
    });
  });

  group('#132 FnDesignFit 자체', () {
    testWidgets('🔴 키보드가 올라오면 축소를 멈추고 스크롤로 바꾼다', (t) async {
      // 키보드가 뜨면 남는 높이가 확 줄어 글씨가 깨알만해진다.
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: 336),
            ),
            child: Scaffold(
              body: FnDesignFit(
                child: Column(
                  children: List.generate(
                      20, (i) => const SizedBox(height: 50, child: Text('x'))),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(SingleChildScrollView), findsWidgets,
          reason: '키보드가 떴는데 스크롤이 없으면 입력칸이 가려진다');
    });

    testWidgets('🔴 내용이 짧으면 확대하지 않는다', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FnDesignFit(
              child: SizedBox(height: 100, child: Text('짧은 내용')),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final tr = t.widgetList<Transform>(find.byType(Transform)).toList();
      for (final x in tr) {
        // 배율이 1 을 넘으면 글씨가 커져 버린다.
        expect(x.transform.getMaxScaleOnAxis(), lessThanOrEqualTo(1.001));
      }
    });
  });
}
