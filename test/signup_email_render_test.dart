import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_signup_tokens.dart';
import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/signup_email_ds_screen.dart';

/// 🔴 #155 — 회원가입 이메일 단계 화면 회귀 방지.
///
/// 사장님 시안 4장(473x1024)을 실측해 만든 화면이다. 이 테스트는
/// **실측값(리터럴)** 과 비교한다. 토큰끼리 비교하면 토큰을 잘못 바꿔도
/// 통과해 버리기 때문이다(#148 에서 실제로 당했다).
void main() {
  const screen = Size(375, 812);

  Future<void> pump(WidgetTester tester, {String? initialEmail}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: SignupEmailDsScreen(initialEmail: initialEmail),
        ),
      ),
    );
    await tester.pump();
  }

  /// 코랄로 칠해진 버튼 컨테이너를 찾는다.
  Finder coralBox() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        return d.color == const Color(0xFFFF6D78);
      });

  Finder greyBox() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        return d.color == const Color(0xFFE5E5E5);
      });

  group('#155 토큰 — 시안 실측값과 일치한다', () {
    test('🔴 배경/코랄은 기존 홈 토큰과 같은 값이다 (실측 일치)', () {
      // 네 장 모두 배경 최빈색 #FEF9F5, 코랄 #FF6D78 로 측정됐다.
      expect(FnSignup.bg, const Color(0xFFFEF9F5));
      expect(FnSignup.coral, const Color(0xFFFF6D78));
    });

    test('🔴 레이아웃 수치가 시안 실측 환산값이다', () {
      // 시안 px ÷ 1.26133 (= 473/375)
      expect(FnSignup.pagePad, 24.0);      // 31px  -> 24.58
      expect(FnSignup.fieldHeight, 47.0);  // 59px  -> 46.78
      expect(FnSignup.buttonHeight, 50.0); // 63px  -> 49.95
      expect(FnSignup.cardHeight, 84.0);   // 106px -> 84.04
      expect(FnSignup.fieldRadius, 8.0);
      expect(FnSignup.buttonRadius, 11.0);
      expect(FnSignup.cardRadius, 18.0);
    });

    test('🔴 비활성 버튼 색이 실측값이다', () {
      expect(FnSignup.disabledFill, const Color(0xFFE5E5E5));
      expect(FnSignup.disabledFg, const Color(0xFF737373));
    });
  });

  group('#155 1번 화면 — 빈 입력', () {
    testWidgets('🔴 헤드라인 두 줄과 안내문이 시안 문구 그대로다', (tester) async {
      await pump(tester);
      expect(find.text('가입할 이메일을\n입력해주세요.'), findsOneWidget);
      expect(find.text('로그인에 사용할 이메일을 입력해주세요.'), findsOneWidget);
      expect(find.text('이메일'), findsOneWidget);
    });

    testWidgets('🔴 플레이스홀더가 보이고 버튼은 회색 `다음` 이다', (tester) async {
      await pump(tester);
      expect(find.text('이메일을 입력해주세요'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(greyBox(), findsOneWidget, reason: '빈 상태인데 버튼이 코랄이다');
      expect(coralBox(), findsNothing);
    });

    testWidgets('🔴 빈 상태에서 버튼을 눌러도 아무 일이 없다', (tester) async {
      await pump(tester);
      await tester.tap(find.text('다음'));
      await tester.pump();
      // 여전히 1번 화면.
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('이메일 형식을 확인해주세요.'), findsNothing);
    });

    testWidgets('🔴 좌우 여백이 24dp 다 (시안 31px)', (tester) async {
      await pump(tester);
      final r = tester.getRect(find.text('가입할 이메일을\n입력해주세요.'));
      expect(r.left, closeTo(24.0, 1.0),
          reason: '좌여백이 ${r.left} 다 — 시안은 24dp');
    });
  });

  group('#155 2번 화면 — 올바른 입력', () {
    testWidgets('🔴 글자를 넣으면 버튼이 코랄로 바뀐다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@example.com');
      await tester.pump();
      expect(coralBox(), findsOneWidget, reason: '입력했는데 버튼이 코랄이 아니다');
      expect(greyBox(), findsNothing);
      expect(find.text('다음'), findsOneWidget);
    });

    testWidgets('🔴 입력한 글자가 화면에 남는다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@example.com');
      await tester.pump();
      expect(find.text('flownote@example.com'), findsOneWidget);
      // 🔴 Flutter 의 TextField 는 힌트 위젯을 트리에서 지우지 않고
      //    투명도만 0 으로 만든다. 그래서 `findsNothing` 이 아니라
      //    **보이지 않는지(opacity 0)** 를 확인해야 한다.
      final hint = find.ancestor(
        of: find.text('이메일을 입력해주세요'),
        matching: find.byType(AnimatedOpacity),
      );
      expect(hint, findsWidgets, reason: '힌트 래퍼를 못 찾았다');
      final op = tester.widgetList<AnimatedOpacity>(hint).first;
      expect(op.opacity, 0.0, reason: '글자를 넣었는데 힌트가 아직 보인다');
    });

    testWidgets('🔴 버튼 높이가 50dp 다 (시안 63px)', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'a@b.com');
      await tester.pump();
      final r = tester.getRect(coralBox());
      expect(r.height, closeTo(50.0, 0.6));
      expect(r.width, closeTo(375 - 48, 1.0), reason: '좌우 24dp 여백이 아니다');
    });
  });

  group('#155 3번 화면 — 형식 오류', () {
    testWidgets('🔴 `flownote@` 를 넣고 누르면 오류문이 뜬다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('이메일 형식을 확인해주세요.'), findsOneWidget);
      expect(find.text('다시 입력하기'), findsOneWidget);
      expect(find.text('다음'), findsNothing);
    });

    testWidgets('🔴 오류 상태에서 입력창 테두리가 코랄이다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      final tf = tester.widget<TextField>(find.byType(TextField));
      final b = tf.decoration!.enabledBorder as OutlineInputBorder;
      expect(b.borderSide.color, const Color(0xFFFF6D78),
          reason: '오류인데 테두리가 회색이다');
    });

    testWidgets('🔴 `다시 입력하기` 를 누르면 입력창이 비워지고 1번으로 돌아간다',
        (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      await tester.tap(find.text('다시 입력하기'));
      await tester.pump();
      // 비워졌으면 힌트가 다시 보여야 한다(opacity 1).
      final hint2 = find.ancestor(
        of: find.text('이메일을 입력해주세요'),
        matching: find.byType(AnimatedOpacity),
      );
      expect(hint2, findsWidgets);
      expect(tester.widgetList<AnimatedOpacity>(hint2).first.opacity, 1.0,
          reason: '입력창이 안 비워졌다');
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('이메일 형식을 확인해주세요.'), findsNothing);
      expect(greyBox(), findsOneWidget, reason: '비웠는데 버튼이 코랄로 남아 있다');
    });

    testWidgets('🔴 글자를 고치면 오류문이 즉시 사라진다', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'flownote@');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('이메일 형식을 확인해주세요.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'flownote@e.com');
      await tester.pump();
      expect(find.text('이메일 형식을 확인해주세요.'), findsNothing);
      expect(find.text('다음'), findsOneWidget);
    });
  });

  group('#155 이메일 형식 판정', () {
    test('🔴 시안 3번의 `flownote@` 는 반드시 거절된다', () {
      expect(SignupEmailDsScreenState.isValidEmail('flownote@'), isFalse);
    });

    test('🔴 올바른 주소는 통과한다', () {
      for (final e in [
        'flownote@example.com',
        'a.b+c@sub.domain.co.kr',
        'x_y@z.io',
      ]) {
        expect(SignupEmailDsScreenState.isValidEmail(e), isTrue, reason: e);
      }
    });

    test('🔴 흔한 오타는 거절한다', () {
      for (final e in [
        '',
        '   ',
        'flownote',
        'flownote@@a.com',
        'flownote@a',
        'flownote@a.',
        'flow note@a.com',
        '@a.com',
      ]) {
        expect(SignupEmailDsScreenState.isValidEmail(e), isFalse, reason: e);
      }
    });
  });

  group('#155 4번 화면 — 이미 가입된 이메일', () {
    testWidgets('🔴 카드와 두 버튼이 시안 문구대로 뜬다', (tester) async {
      await pump(tester);
      final st = tester.state<SignupEmailDsScreenState>(
          find.byType(SignupEmailDsScreen));
      st.showTaken('flownote@example.com');
      await tester.pump();

      expect(find.text('이미 가입된\n이메일이에요.'), findsOneWidget);
      expect(find.text('기존 계정으로 로그인해 서비스를 이용해주세요.'), findsOneWidget);
      expect(find.text('가입된 이메일'), findsOneWidget);
      expect(find.text('flownote@example.com'), findsOneWidget);
      expect(find.text('로그인하기'), findsOneWidget);
      expect(find.text('비밀번호 찾기'), findsOneWidget);
      // 입력창은 더이상 보이지 않는다.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('🔴 비밀번호 찾기는 외곽선(흰 바탕 + 코랄 테두리)이다', (tester) async {
      await pump(tester);
      tester
          .state<SignupEmailDsScreenState>(find.byType(SignupEmailDsScreen))
          .showTaken('flownote@example.com');
      await tester.pump();

      final box = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        if (d.color != const Color(0xFFFFFFFF)) return false;
        final b = d.border;
        return b is Border && b.top.color == const Color(0xFFFF6D78);
      });
      expect(box, findsOneWidget, reason: '외곽선 버튼을 못 찾았다');
    });

    testWidgets('🔴 카드 높이가 84dp 다 (시안 106px)', (tester) async {
      await pump(tester);
      tester
          .state<SignupEmailDsScreenState>(find.byType(SignupEmailDsScreen))
          .showTaken('flownote@example.com');
      await tester.pump();
      final r = tester.getRect(
          find.ancestor(of: find.text('가입된 이메일'), matching: find.byType(Container))
              .first);
      expect(r.height, closeTo(84.0, 0.6));
    });

    testWidgets('🔴 아주 긴 이메일도 카드를 넘치지 않는다', (tester) async {
      await pump(tester);
      tester
          .state<SignupEmailDsScreenState>(find.byType(SignupEmailDsScreen))
          .showTaken('a-very-very-long-address-for-overflow@extremely-long.example.co.kr');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('#155 소스 계약 — 되돌리면 안 되는 것들', () {
    test('🔴 열거 보호 때문에 fetchSignInMethodsForEmail 로 판정하지 않는다', () {
      final code =
          File('lib/screens/ds/signup_email_ds_screen.dart').readAsStringSync();
      // 경고 주석은 남아 있어야 하지만, 실제 호출은 없어야 한다.
      expect(code.contains('await'), isTrue);
      expect(
          RegExp(r'fetchSignInMethodsForEmail\s*\(').hasMatch(code), isFalse,
          reason: '열거 보호가 켜진 프로젝트에서는 항상 빈 배열이라 4번 화면이 안 뜬다');
    });

    test('🔴 가입 화면이 중복 이메일을 pop(true) 로 알린다', () {
      final code =
          File('lib/screens/ds/auth_ds_screens.dart').readAsStringSync();
      expect(code.contains('Navigator.of(context).pop(true)'), isTrue,
          reason: '중복 이메일을 이메일 단계로 돌려보내지 않으면 시안 4번 화면이 안 뜬다');
    });

    test('🔴 진입점이 이메일 단계 화면을 연다', () {
      final splash =
          File('lib/screens/ds/splash_ds_screen.dart').readAsStringSync();
      expect(splash.contains('SignupEmailDsScreen('), isTrue,
          reason: '스플래시 회원가입이 예전 한 판 화면으로 되돌아갔다');
    });
  });
}
