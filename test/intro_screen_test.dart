import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/intro_ds_screen.dart';

/// 🔴 #124 — 로그인 앞 인트로를 **앱 화면으로** 만들었다.
///
/// 사장님 지시:
///  - 스플래시는 잠깐 띄워지는 이미지
///  - 1~3번은 PNG 통째로가 아니라 **앱 화면으로 제작**
///  - 건너뛰기 · 다음이 실제로 눌려 넘어갈 것
///  - **일회성이 아니라 계속** 띄울 것
///
/// ## 테스트 환경 주의
/// `Image.asset` 이 테스트 바인딩에서 영원히 미해결이라
/// `pumpAndSettle()` 은 멈춘다. `pump(Duration)` 을 쓴다.
void main() {
  /// 페이지 전환 애니메이션(280ms)을 끝까지 돌린다.
  Future<void> settleAnim(WidgetTester t) async {
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpIntro(WidgetTester t,
      {VoidCallback? onDone, Size size = const Size(390, 844)}) async {
    await t.binding.setSurfaceSize(size);
    await t.pumpWidget(MaterialApp(
      home: IntroDsScreen(onDone: onDone ?? () {}),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  group('#124 에셋', () {
    test('🔴 일러스트 3장이 실제 파일이다', () {
      // #126: 스플래시는 더 이상 그림이 아니다. 앱 화면으로 그린다.
      final paths = IntroSlide.all.map((e) => e.art).toList();
      expect(paths.length, 3);
      for (final a in paths) {
        expect(io.File(a).existsSync(), isTrue, reason: '$a 가 없다');
        expect(io.File(a).lengthSync(), greaterThan(20000), reason: '$a 가 너무 작다');
      }
    });

    test('🔴 일러스트는 글자가 없는 그림 영역이다', () {
      // 전체 목업(471x980)이 아니라 일러스트(471x624)만 담겨야 한다.
      // 전체를 넣으면 글자가 두 겹으로 보인다.
      expect(IntroSlide.artRatio, closeTo(471 / 624, 0.0001));
      for (final s in IntroSlide.all) {
        expect(s.art, contains('/art_'));
      }
    });

    test('pubspec 이 assets/onboarding/ 을 싣고 나간다', () {
      final y = io.File('pubspec.yaml').readAsStringSync();
      expect(y.contains('assets/onboarding/'), isTrue);
    });
  });

  group('#124 문구 (시안 1:1)', () {
    test('🔴 제목이 시안과 글자까지 같다', () {
      expect(IntroSlide.all[0].title, '쌓이는 영수증,\n촬영으로 간편하게');
      expect(IntroSlide.all[1].title, '우리 가게 지출을\n한눈에 확인해요');
      expect(IntroSlide.all[2].title, '쌓인 기록으로\n다음 사입도 똑똑하게');
    });

    test('🔴 본문이 시안과 글자까지 같다', () {
      expect(IntroSlide.all[0].body,
          '꽃 사입 내역을 일일이 적지 않아도\n품목과 금액을 읽어 정리해 드려요.');
      expect(IntroSlide.all[1].body,
          '월별 지출부터 품목별 비중까지\n복잡한 사입 내역을 쉽게 파악해요.');
      expect(IntroSlide.all[2].body,
          '우리 가게에 맞는 사입 가이드로\n다음 꽃시장 방문을 준비해요.');
    });
  });

  group('#124 앱 화면으로 그린다', () {
    testWidgets('🔴 제목·본문이 실제 Text 위젯으로 보인다', (t) async {
      await pumpIntro(t);
      expect(find.text('쌓이는 영수증,\n촬영으로 간편하게'), findsOneWidget);
      expect(find.text('꽃 사입 내역을 일일이 적지 않아도\n품목과 금액을 읽어 정리해 드려요.'),
          findsOneWidget);
    });

    testWidgets('🔴 건너뛰기·다음이 실제 글자로 있다', (t) async {
      await pumpIntro(t);
      expect(find.text('건너뛰기'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('시작하기'), findsNothing);
    });

    testWidgets('인디케이터 점이 장 수만큼 있다', (t) async {
      await pumpIntro(t);
      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('🔴 넓은 화면에서도 글자가 안 늘어난다 (#123 회귀)', (t) async {
      // 글자를 위젯으로 그리므로 화면이 넓어도 크기가 변하지 않는다.
      await pumpIntro(t, size: const Size(1024, 500));
      final small = t.widget<Text>(find.text('건너뛰기'));
      await pumpIntro(t, size: const Size(390, 844));
      final phone = t.widget<Text>(find.text('건너뛰기'));
      expect(small.style!.fontSize, phone.style!.fontSize);
    });
  });

  group('#124 버튼이 실제로 넘어간다', () {
    testWidgets('🔴 다음을 누르면 2번 장으로 간다', (t) async {
      await pumpIntro(t);
      await t.tap(find.text('다음'));
      await settleAnim(t);
      expect(find.text('우리 가게 지출을\n한눈에 확인해요'), findsOneWidget);
    });

    testWidgets('🔴 마지막 장에서만 시작하기로 바뀐다', (t) async {
      await pumpIntro(t);
      await t.tap(find.text('다음'));
      await settleAnim(t);
      await t.tap(find.text('다음'));
      await settleAnim(t);
      expect(find.text('쌓인 기록으로\n다음 사입도 똑똑하게'), findsOneWidget);
      expect(find.text('시작하기'), findsOneWidget);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('🔴 건너뛰기를 누르면 끝난다', (t) async {
      var done = false;
      await pumpIntro(t, onDone: () => done = true);
      await t.tap(find.text('건너뛰기'));
      await settleAnim(t);
      expect(done, isTrue);
    });

    testWidgets('🔴 시작하기를 누르면 끝난다', (t) async {
      var done = false;
      await pumpIntro(t, onDone: () => done = true);
      await t.tap(find.text('다음'));
      await settleAnim(t);
      await t.tap(find.text('다음'));
      await settleAnim(t);
      await t.tap(find.text('시작하기'));
      await settleAnim(t);
      expect(done, isTrue);
    });

    testWidgets('스와이프로도 넘어간다', (t) async {
      await pumpIntro(t);
      await t.fling(find.byType(PageView), const Offset(-350, 0), 1200);
      await settleAnim(t);
      expect(find.text('우리 가게 지출을\n한눈에 확인해요'), findsOneWidget);
    });
  });

  group('#124 일회성이 아니다', () {
    test('🔴 봤는지 저장하는 코드가 없다', () {
      // 사장님 지시: "일회성 말고 계속 띄워질 수 있도록"
      final intro = io.File('lib/screens/ds/intro_ds_screen.dart')
          .readAsStringSync();
      final main = io.File('lib/main.dart').readAsStringSync();
      expect(intro.contains('SharedPreferences'), isFalse);
      expect(intro.contains('IntroPrefs'), isFalse);
      expect(main.contains('IntroPrefs'), isFalse);
      expect(main.contains('intro_seen'), isFalse);
    });
  });

  group('#126 스플래시는 앱 화면이다', () {
    testWidgets('🔴 그림이 아니라 로고·워드마크·태그라인 위젯이다', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: IntroSplash()),
      ));
      await t.pump(const Duration(milliseconds: 700));

      // 태그라인이 실제 글자로 있어야 한다. (그림이면 못 찾는다)
      expect(find.text('꽃은 아름답게, 정산은 정확하게 플로우노트'), findsOneWidget);
      // 로고 + 워드마크 = Image 2개. (시안 PNG 한 장이 아니다)
      expect(find.byType(Image), findsNWidgets(2));
      // 넘기는 화면이 아니므로 버튼이 없다.
      expect(find.text('건너뛰기'), findsNothing);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('🔴 떠오르는 애니메이션이 끝나면 완전히 보인다', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: IntroSplash()),
      ));
      // 시작 직후엔 아직 흐리다
      await t.pump(const Duration(milliseconds: 16));
      final early = t.widget<Opacity>(find.byType(Opacity).first).opacity;
      // 애니메이션(620ms)이 끝나면 또렷하다
      await t.pump(const Duration(milliseconds: 700));
      final late_ = t.widget<Opacity>(find.byType(Opacity).first).opacity;
      expect(early, lessThan(1.0));
      expect(late_, 1.0);
    });

    testWidgets('🔴 넓은 화면에서도 글자 크기가 그대로다', (t) async {
      // 위젯으로 그리므로 PNG 처럼 늘어나지 않는다.
      await t.binding.setSurfaceSize(const Size(1024, 700));
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: IntroSplash()),
      ));
      await t.pump(const Duration(milliseconds: 700));
      final wide = t.widget<Text>(
          find.text('꽃은 아름답게, 정산은 정확하게 플로우노트'));

      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: IntroSplash()),
      ));
      await t.pump(const Duration(milliseconds: 700));
      final phone = t.widget<Text>(
          find.text('꽃은 아름답게, 정산은 정확하게 플로우노트'));

      expect(wide.style!.fontSize, phone.style!.fontSize);
    });

    test('🔴 스플래시 PNG 를 더 이상 쓰지 않는다', () {
      final code = io.File('lib/screens/ds/intro_ds_screen.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('splash.png'), isFalse);
      expect(io.File('assets/onboarding/splash.png').existsSync(), isFalse,
          reason: '쓰지 않는 그림은 앱 용량만 차지한다');
    });

    test('🔴 main.dart 가 스플래시를 잠깐 띄운다', () {
      final main = io.File('lib/main.dart').readAsStringSync();
      expect(main.contains('IntroSplash'), isTrue);
      expect(main.contains('milliseconds: 1400'), isTrue,
          reason: '잠깐 비춰지는 시간이 지정되어 있어야 한다');
    });
  });

  group('#126 일러스트가 잘리지 않는다', () {
    testWidgets('🔴 contain 이라 한 픽셀도 안 잘린다', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(MaterialApp(home: IntroDsScreen(onDone: () {})));
      await t.pump(const Duration(milliseconds: 300));
      final img = t.widget<Image>(find.byType(Image).first);
      expect(img.fit, BoxFit.contain,
          reason: 'cover 면 태블릿에서 40% 가까이 잘린다');
    });

    testWidgets('태블릿에서도 그림 비율이 유지된다', (t) async {
      await t.binding.setSurfaceSize(const Size(768, 1024));
      await t.pumpWidget(MaterialApp(home: IntroDsScreen(onDone: () {})));
      await t.pump(const Duration(milliseconds: 300));
      final img = t.widget<Image>(find.byType(Image).first);
      expect(img.fit, BoxFit.contain);
    });
  });
}
