import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_signup_tokens.dart';
import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/signup_parts.dart';
import 'package:flow_note/screens/ds/signup_password_ds_screen.dart';

/// 🔴 #156 — 비밀번호 설정 · 휴대폰 인증 · 가입 완료 화면 회귀 방지.
///
/// 시안 5장을 실측해 만든 화면들이다. 단정은 **리터럴 실측값**과 비교한다.
void main() {
  Future<void> pumpPw(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          home: SignupPasswordDsScreen(email: 'flownote@example.com'),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpAny(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: MaterialApp(home: w),
      ),
    );
    await tester.pump();
  }

  Finder boxOf(Color c) => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.color == c;
      });

  Finder coral() => boxOf(const Color(0xFFFF6D78));
  Finder grey() => boxOf(const Color(0xFFE5E5E5));

  group('#156 비밀번호 규칙', () {
    test('🔴 시안 3번의 6자(영문+숫자 미달)는 거절된다', () {
      expect(SignupPasswordDsScreenState.isValidPassword('abc123'), isFalse);
    });

    test('🔴 영문과 숫자를 모두 포함한 8~16자만 통과한다', () {
      expect(SignupPasswordDsScreenState.isValidPassword('flow1234'), isTrue);
      expect(SignupPasswordDsScreenState.isValidPassword('Fl0wnote2026'), isTrue);
      // 16자 경계
      expect(
          SignupPasswordDsScreenState.isValidPassword('abcdefgh12345678'), isTrue);
    });

    test('🔴 영문만 / 숫자만 / 길이 밖은 거절한다', () {
      for (final p in [
        'abcdefgh',          // 숫자 없음
        '12345678',          // 영문 없음
        'abc1234',           // 7자
        'abcdefghi123456789' // 18자
      ]) {
        expect(SignupPasswordDsScreenState.isValidPassword(p), isFalse,
            reason: p);
      }
    });
  });

  group('#156 비밀번호 화면 — 시안 1번 (비었음)', () {
    testWidgets('🔴 제목·부제·두 라벨이 시안 문구 그대로다', (tester) async {
      await pumpPw(tester);
      expect(find.text('사용할 비밀번호를\n설정해주세요.'), findsOneWidget);
      expect(find.text('영문과 숫자를 포함한 8~16자'), findsOneWidget);
      expect(find.text('비밀번호'), findsOneWidget);
      expect(find.text('비밀번호 확인'), findsOneWidget);
    });

    testWidgets('🔴 입력칸이 두 개고 둘 다 가려져 있다', (tester) async {
      await pumpPw(tester);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.length, 2);
      for (final f in fields) {
        expect(f.obscureText, isTrue, reason: '비밀번호가 그대로 보인다');
      }
    });

    testWidgets('🔴 버튼이 회색 `다음` 이고 눌러도 넘어가지 않는다', (tester) async {
      await pumpPw(tester);
      expect(find.text('다음'), findsOneWidget);
      expect(grey(), findsOneWidget);
      expect(coral(), findsNothing);
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('사용할 비밀번호를\n설정해주세요.'), findsOneWidget);
    });
  });

  group('#156 비밀번호 화면 — 시안 2번 (채워짐)', () {
    testWidgets('🔴 두 칸을 채우면 버튼이 코랄이 된다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'flow1234');
      await tester.enterText(f.at(1), 'flow1234');
      await tester.pump();
      expect(coral(), findsOneWidget);
      expect(grey(), findsNothing);
    });

    testWidgets('🔴 한 칸만 채우면 아직 회색이다', (tester) async {
      await pumpPw(tester);
      await tester.enterText(find.byType(TextField).at(0), 'flow1234');
      await tester.pump();
      expect(grey(), findsOneWidget, reason: '확인 칸이 비었는데 활성화됐다');
    });
  });

  group('#156 비밀번호 화면 — 시안 3번 (오류)', () {
    testWidgets('🔴 규칙 위반 + 불일치면 오류문 두 개가 동시에 뜬다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'abc123');     // 6자
      await tester.enterText(f.at(1), 'flow1234');   // 불일치
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();

      expect(find.text('영문과 숫자를 포함한 8~16자로 입력해주세요.'), findsOneWidget);
      expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
      expect(find.text('다시 입력하기'), findsOneWidget);
    });

    testWidgets('🔴 오류일 때 두 입력창 테두리가 코랄이다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'abc123');
      await tester.enterText(f.at(1), 'flow1234');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();

      for (final tf in tester.widgetList<TextField>(f)) {
        final b = tf.decoration!.enabledBorder as OutlineInputBorder;
        expect(b.borderSide.color, const Color(0xFFFF6D78));
      }
    });

    testWidgets('🔴 `다시 입력하기` 는 두 칸을 모두 비운다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'abc123');
      await tester.enterText(f.at(1), 'flow1234');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      await tester.tap(find.text('다시 입력하기'));
      await tester.pump();

      for (final tf in tester.widgetList<TextField>(f)) {
        expect(tf.controller!.text, isEmpty);
      }
      expect(find.text('다음'), findsOneWidget);
      expect(find.text('영문과 숫자를 포함한 8~16자로 입력해주세요.'), findsNothing);
      expect(grey(), findsOneWidget);
    });

    testWidgets('🔴 일치하지만 규칙 위반이면 두 번째 오류는 안 뜬다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'abc123');
      await tester.enterText(f.at(1), 'abc123');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('영문과 숫자를 포함한 8~16자로 입력해주세요.'), findsOneWidget);
      expect(find.text('비밀번호가 일치하지 않습니다.'), findsNothing);
    });

    testWidgets('🔴 고치면 오류가 즉시 사라진다', (tester) async {
      await pumpPw(tester);
      final f = find.byType(TextField);
      await tester.enterText(f.at(0), 'abc123');
      await tester.enterText(f.at(1), 'x');
      await tester.pump();
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
      await tester.enterText(f.at(0), 'flow1234');
      await tester.pump();
      expect(find.text('비밀번호가 일치하지 않습니다.'), findsNothing);
      expect(find.text('다음'), findsOneWidget);
    });
  });

  group('#156 휴대폰 인증 화면', () {
    testWidgets('🔴 시안 문구 그대로 뜨고 버튼이 코랄이다', (tester) async {
      await pumpAny(
        tester,
        const SignupVerifyDsScreen(
            email: 'a@b.com', password: 'flow1234'),
      );
      expect(find.text('휴대폰 인증을\n진행해주세요.'), findsOneWidget);
      expect(find.text('원활한 서비스 이용을 위해\n본인확인이 필요해요.'), findsOneWidget);
      expect(find.text('휴대폰 인증하기'), findsOneWidget);
      expect(coral(), findsOneWidget);
    });

    testWidgets('🔴 입력칸이 없다 (시안에 없음)', (tester) async {
      await pumpAny(
        tester,
        const SignupVerifyDsScreen(email: 'a@b.com', password: 'flow1234'),
      );
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('#156 가입 완료 화면', () {
    testWidgets('🔴 워드마크 + 가운데 정렬 문구 + 버튼 두 개', (tester) async {
      await pumpAny(tester, const SignupDoneDsScreen(email: 'a@b.com'));
      expect(find.text('회원가입이\n완료되었어요.'), findsOneWidget);
      expect(find.text('로그인하고 영수증 정리를 시작해보세요.'), findsOneWidget);
      expect(find.text('로그인하기'), findsOneWidget);
      expect(find.text('사업자등록증 등록하러 가기'), findsOneWidget);
    });

    testWidgets('🔴 완료 문구는 가운데 정렬이다 (시안 실측)', (tester) async {
      await pumpAny(tester, const SignupDoneDsScreen(email: 'a@b.com'));
      final t = tester.widget<Text>(find.text('회원가입이\n완료되었어요.'));
      expect(t.textAlign, TextAlign.center);
    });

    testWidgets('🔴 두 번째 버튼은 코랄과 다른 색이다 (사장님 요청)', (tester) async {
      await pumpAny(tester, const SignupDoneDsScreen(email: 'a@b.com'));
      // 첫 버튼 = 코랄 채움, 둘째 = 연한 코랄 배경.
      expect(coral(), findsOneWidget, reason: '코랄 버튼이 1개가 아니다');
      expect(boxOf(const Color(0x14FF6D78)), findsOneWidget,
          reason: '보조 버튼이 코랄과 같은 색이 됐다');
    });

    testWidgets('🔴 두 번째 버튼 글자는 코랄 계열이고 흰색이 아니다', (tester) async {
      await pumpAny(tester, const SignupDoneDsScreen(email: 'a@b.com'));
      final t = tester.widget<Text>(find.text('사업자등록증 등록하러 가기'));
      expect(t.style!.color, const Color(0xFFE85C68));
      expect(t.style!.color, isNot(Colors.white));
    });
  });

  group('#156 공용 조각 · 토큰', () {
    test('🔴 보조 버튼 색이 실측 토큰 그대로다', () {
      expect(FnSignup.secondaryFill, const Color(0x14FF6D78));
      expect(FnSignup.secondaryFg, const Color(0xFFE85C68));
    });

    test('🔴 완료 화면 워드마크 높이가 시안값(41px->32.5dp)이다', () {
      expect(FnSignup.doneWordmarkHeight, 32.0);
    });

    testWidgets('🔴 세 가지 버튼 모양이 서로 다르게 그려진다', (tester) async {
      await pumpAny(
        tester,
        const Scaffold(
          body: Column(children: [
            SignupButton(label: 'P', onTap: _noop),
            SignupButton(
                label: 'O', style: SignupButtonStyle.outlined, onTap: _noop),
            SignupButton(
                label: 'S', style: SignupButtonStyle.secondary, onTap: _noop),
          ]),
        ),
      );
      expect(coral(), findsOneWidget);
      expect(boxOf(const Color(0xFFFFFFFF)), findsOneWidget);
      expect(boxOf(const Color(0x14FF6D78)), findsOneWidget);
    });
  });

  group('#156 소스 계약', () {
    test('🔴 이메일 단계가 새 비밀번호 화면으로 넘긴다', () {
      final c = File('lib/screens/ds/signup_email_ds_screen.dart')
          .readAsStringSync();
      expect(c.contains('SignupPasswordDsScreen('), isTrue,
          reason: '이메일 다음이 예전 한 판 화면으로 되돌아갔다');
    });

    test('🔴 가입 직전 약관 동의를 반드시 받는다 (법적 필수)', () {
      final c = File('lib/screens/ds/signup_password_ds_screen.dart')
          .readAsStringSync();
      expect(c.contains('agreeTerms: true'), isTrue);
      expect(c.contains('showFnAlert'), isTrue,
          reason: '동의를 안 받고 계정을 만들면 안 된다');
    });

    test('🔴 가짜 인증으로 통과시키지 않는다', () {
      final c = File('lib/screens/ds/signup_password_ds_screen.dart')
          .readAsStringSync();
      // 인증 수단이 붙기 전까지 '인증됨' 상태를 저장하지 않는다.
      expect(c.contains('isPhoneVerified = true'), isFalse);
      expect(c.contains('phoneVerified: true'), isFalse);
    });
  });
}

void _noop() {}
