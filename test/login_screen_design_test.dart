import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/splash_ds_screen.dart';

/// 🔴 #125 — 로그인 화면을 시안대로 **앱 화면으로** 다시 만들었다.
///
/// 사장님 지시: "기능들은 그대로 가져가되 PNG를 그대로 쓰는게 아니라
/// 앱 화면으로 만들어서 반영. 로그인 기능들은 모두 그대로."
///
/// 그래서 이 테스트는 두 가지를 본다.
///   1. 시안 요소가 화면에 실제로 그려지는가
///   2. **기존 기능이 하나도 빠지지 않았는가** (이게 더 중요하다)
void main() {
  Future<void> pumpLogin(WidgetTester t,
      {Size size = const Size(390, 844)}) async {
    await t.binding.setSurfaceSize(size);
    await t.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: SplashDsScreen()),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  group('#125 시안 요소가 그려진다', () {
    testWidgets('🔴 라벨·입력칸·버튼 문구가 시안과 같다', (t) async {
      await pumpLogin(t);
      expect(find.text('이메일'), findsOneWidget);
      expect(find.text('비밀번호'), findsOneWidget);
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('비밀번호를 잊으셨나요?'), findsOneWidget);
      expect(find.text('아직 회원이 아니신가요? '), findsOneWidget);
      expect(find.text('회원가입'), findsOneWidget);
      expect(find.text('SNS 계정으로 간편 시작해볼까요?'), findsOneWidget);
    });

    testWidgets('🔴 입력칸 placeholder 가 시안과 같다', (t) async {
      await pumpLogin(t);
      expect(find.text('shop@flownote.kr'), findsOneWidget);
      expect(find.text('비밀번호 입력'), findsOneWidget);
    });

    testWidgets('🔴 SNS 버튼 3개가 브랜드 색으로 그려진다', (t) async {
      await pumpLogin(t);
      // 시안은 버튼 전체가 브랜드 색이다. (예전엔 흰 카드 + 작은 동그라미)
      expect(find.text('카카오'), findsOneWidget);
      expect(find.text('네이버'), findsOneWidget);
      expect(find.text('구글'), findsOneWidget);

      Color? bgOf(String label) {
        final box = t.widget<Container>(
          find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      expect(bgOf('카카오'), const Color(0xFFFEE500));
      expect(bgOf('네이버'), const Color(0xFF03C75A));
      expect(bgOf('구글'), Colors.white);
    });

    testWidgets('로그인 버튼이 시안 색·높이다', (t) async {
      await pumpLogin(t);
      final box = t.widget<Container>(
        find.ancestor(of: find.text('로그인'), matching: find.byType(Container)).first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, const Color(0xFFFD717A));
      expect(box.constraints?.maxHeight ?? 0, 62.0);
    });

    testWidgets('배경이 시안 크림색이다', (t) async {
      await pumpLogin(t);
      final sc = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(sc.backgroundColor, const Color(0xFFFEF9F5));
    });

    testWidgets('🔴 넓은 화면에서도 글자 크기가 그대로다', (t) async {
      // 앱 화면으로 그리므로 PNG 처럼 늘어나지 않는다. (#123 교훈)
      await pumpLogin(t, size: const Size(1024, 700));
      final wide = t.widget<Text>(find.text('로그인'));
      await pumpLogin(t, size: const Size(390, 844));
      final phone = t.widget<Text>(find.text('로그인'));
      expect(wide.style!.fontSize, phone.style!.fontSize);
    });
  });

  group('#125 기능이 하나도 빠지지 않았다', () {
    /// 화면 코드에서 주석을 걷어낸 본문.
    String code() {
      return io.File('lib/screens/ds/splash_ds_screen.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('///'))
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    }

    test('🔴 이메일 로그인 · 회원가입이 남아 있다', () {
      final c = code();
      expect(c.contains('auth.signIn('), isTrue);
      expect(c.contains('SignUpDsScreen'), isTrue);
    });

    test('🔴 SNS 로그인 3종이 남아 있다', () {
      final c = code();
      expect(c.contains('signInWithKakao'), isTrue);
      expect(c.contains('signInWithGoogle'), isTrue);
      expect(c.contains('signInWithApple'), isTrue);
    });

    test('🔴 애플 버튼은 iOS 에서만 보인다 (App Store 4.8)', () {
      final c = code();
      expect(c.contains('isAppleSignInSupported'), isTrue);
    });

    test('🔴 카카오 키 미설정 안내가 남아 있다', () {
      final c = code();
      expect(c.contains('KakaoConfig.isConfigured'), isTrue);
      expect(c.contains('KakaoConfig.isWebKeyMissing'), isTrue);
    });

    test('🔴 네이버 준비 중 안내가 남아 있다', () {
      expect(code().contains("showFnComingSoon(context, '네이버')"), isTrue);
    });

    test('🔴 서버 미연결 배너·차단이 남아 있다', () {
      final c = code();
      expect(c.contains('AuthUnavailableBanner()'), isTrue);
      expect(c.contains('AuthUnavailableBanner.blocked'), isTrue);
    });

    test('🔴 카카오 리다이렉트 실패 사유 표시가 남아 있다', () {
      expect(code().contains('addPostFrameCallback'), isTrue);
    });

    test('🔴 약관·개인정보 링크가 남아 있다', () {
      final c = code();
      expect(c.contains('LegalDocKind.terms'), isTrue);
      expect(c.contains('LegalDocKind.privacy'), isTrue);
    });

    test('🔴 홈 화면에 추가 안내가 남아 있다', () {
      final c = code();
      expect(c.contains('pwaState().shouldGuide'), isTrue);
      expect(c.contains('AddToHomeSheet.open'), isTrue);
    });

    test('🔴 로그인 성공 후 홈 복귀 안전장치가 남아 있다', () {
      expect(code().contains('_leaveAfterSuccess'), isTrue);
    });

    test('🔴 비밀번호 재설정이 새로 연결됐다', () {
      // 시안이 자리를 만들어 줬고, provider 에는 이미 기능이 있었다.
      expect(code().contains('sendPasswordReset'), isTrue);
    });

    test('PNG 를 깔지 않는다 (앱 화면으로 그린다)', () {
      final c = code();
      expect(c.contains('assets/onboarding/'), isFalse,
          reason: '로그인 화면은 시안 PNG 를 깔지 않는다');
    });
  });

  group('#125 입력 검증', () {
    testWidgets('🔴 빈칸으로 로그인하면 안내가 뜬다', (t) async {
      await pumpLogin(t);
      await t.tap(find.text('로그인'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('이메일과 비밀번호'), findsOneWidget);
    });

    testWidgets('🔴 이메일 없이 비밀번호 찾기를 누르면 안내가 뜬다', (t) async {
      await pumpLogin(t);
      await t.tap(find.text('비밀번호를 잊으셨나요?'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('이메일을 먼저 입력'), findsOneWidget);
    });
  });
}
