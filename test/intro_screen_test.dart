import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow_note/screens/ds/intro_ds_screen.dart';

/// 🔴 #121/#122 — 로그인 앞 인트로.
///
/// 사장님 지시대로 **시안 PNG 를 통째로** 쓴다. 제목·본문·버튼 글자·
/// 인디케이터가 모두 그림 안에 있으므로, 글자를 `find.text` 로 찾을
/// 수 없다. 대신 이렇게 잠근다.
///
///  1. 그림 파일이 실제로 있고 pubspec 으로 묶여 나가는지
///  2. 상태바가 잘려 있는지 (진짜 상태바와 겹치면 안 된다)
///  3. 그림 위 투명 버튼이 눌리고 페이지가 넘어가는지
///  4. 마지막 장에서 버튼 뜻이 '시작하기' 로 바뀌는지 (Semantics 로 확인)
///
/// ## 테스트 환경 주의
/// `Image.asset` 이 테스트 바인딩에서 **영원히 미해결**이라
/// `pumpAndSettle()` 을 쓰면 끝나지 않는다. `pump(Duration)` 을 쓴다.
void main() {
  /// nextPage 애니메이션(260ms)을 끝까지 돌린다.
  Future<void> settleAnim(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpIntro(WidgetTester t, {VoidCallback? onDone}) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(MaterialApp(
      home: IntroDsScreen(onDone: onDone ?? () {}),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  group('#122 시안 그림을 그대로 쓴다', () {
    test('🔴 슬라이드 3장 + 스플래시 1장이 모두 실제 파일이다', () {
      final paths = [IntroSlide.splashImage, ...IntroSlide.all.map((e) => e.image)];
      expect(paths.length, 4);
      for (final a in paths) {
        expect(io.File(a).existsSync(), isTrue, reason: '$a 가 없다');
        // 빈 파일이면 화면이 비어 보인다.
        expect(io.File(a).lengthSync(), greaterThan(20000), reason: '$a 가 너무 작다');
      }
    });

    test('🔴 pubspec 이 assets/onboarding/ 을 싣고 나간다', () {
      final y = io.File('pubspec.yaml').readAsStringSync();
      expect(y.contains('assets/onboarding/'), isTrue);
    });

    test('🔴 상태바를 잘라낸 크기다 (471 x 980)', () {
      // 원본은 471x1024. 상태바 44px 를 떼어 980 이 되어야 한다.
      // 그래야 기기의 진짜 상태바와 두 겹으로 겹치지 않는다.
      expect(IntroSlide.ratio, closeTo(471 / 980, 0.0001));
    });

    test('코드로 글자를 다시 그리지 않는다', () {
      // 시안 글자는 그림 안에 있다. 화면이 Text 위젯으로 제목을 또
      // 그리면 두 겹으로 보인다. 그래서 `Text(` 자체가 없어야 한다.
      //
      // 단, `semantics:` 문구는 그림 속 글자를 화면 낭독기에 읽어
      // 주려고 둔 것이라 남아 있는 게 맞다. (화면에 그려지지 않는다)
      final code = io.File('lib/screens/ds/intro_ds_screen.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('///'))
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('Text('), isFalse,
          reason: '제목·본문은 그림 안에 있다. Text 위젯으로 또 그리면 두 겹이 된다');
      expect(code.contains('TextStyle'), isFalse);
      expect(code.contains('Pretendard'), isFalse);
    });
  });

  group('#122 그림 위 투명 버튼', () {
    testWidgets('🔴 첫 장에는 건너뛰기와 다음 버튼이 있다', (t) async {
      await pumpIntro(t);
      expect(find.bySemanticsLabel('건너뛰기'), findsOneWidget);
      expect(find.bySemanticsLabel('다음'), findsOneWidget);
      expect(find.bySemanticsLabel('시작하기'), findsNothing);
    });

    testWidgets('🔴 다음을 누르면 장이 넘어간다', (t) async {
      await pumpIntro(t);
      await t.tap(find.bySemanticsLabel('다음'));
      await settleAnim(t);
      // 2번 장도 아직 '다음'
      expect(find.bySemanticsLabel('다음'), findsOneWidget);

      await t.tap(find.bySemanticsLabel('다음'));
      await settleAnim(t);
      // 3번 장에서 '시작하기' 로 바뀐다
      expect(find.bySemanticsLabel('시작하기'), findsOneWidget);
      expect(find.bySemanticsLabel('다음'), findsNothing);
    });

    testWidgets('🔴 건너뛰기를 누르면 바로 끝난다', (t) async {
      var done = false;
      await pumpIntro(t, onDone: () => done = true);
      await t.tap(find.bySemanticsLabel('건너뛰기'));
      await settleAnim(t);
      expect(done, isTrue, reason: '건너뛰기는 로그인으로 보내야 한다');
    });

    testWidgets('🔴 마지막에서 시작하기를 누르면 끝난다', (t) async {
      var done = false;
      await pumpIntro(t, onDone: () => done = true);
      await t.tap(find.bySemanticsLabel('다음'));
      await settleAnim(t);
      await t.tap(find.bySemanticsLabel('다음'));
      await settleAnim(t);
      await t.tap(find.bySemanticsLabel('시작하기'));
      await settleAnim(t);
      expect(done, isTrue);
    });

    testWidgets('그림이 3장 다 PageView 로 걸려 있다', (t) async {
      await pumpIntro(t);
      final pv = t.widget<PageView>(find.byType(PageView));
      expect(pv.childrenDelegate.estimatedChildCount, 3);
    });
  });

  group('#122 0번 로고 화면', () {
    testWidgets('🔴 버튼이 없다 (넘기는 화면이 아니라 스플래시)', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: IntroSplash()),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('건너뛰기'), findsNothing);
      expect(find.bySemanticsLabel('다음'), findsNothing);
      // 그림은 깔려 있어야 한다.
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
