import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_brand.dart';
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

      // 🔴 #128 시안 실측값으로 갱신. 브랜드 공식색이 아니라 시안을 따른다.
      expect(bgOf('카카오'), const Color(0xFFFDE500));
      expect(bgOf('네이버'), const Color(0xFF02A94D));
      expect(bgOf('구글'), Colors.white);
    });

    testWidgets('로그인 버튼이 시안 색·높이다', (t) async {
      await pumpLogin(t);
      final box = t.widget<Container>(
        find.ancestor(of: find.text('로그인'), matching: find.byType(Container)).first,
      );
      final d = box.decoration as BoxDecoration;
      // 🔴 #128 실측 #FF6D78, 높이 58.5dp (예전 FD717A / 62 는 눈대중)
      expect(d.color, const Color(0xFFFF6D78));
      expect(box.constraints?.maxHeight ?? 0, 58.5);
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
  group('#128 시안 색·로고 재측정', () {
    // 🔴 사장님 지적: "로그인 디자인이랑 컬러가 다르다".
    //
    // 시안(473x1024)을 다시 픽셀로 재서 틀린 값을 바로잡았다.
    // 시안 폭 473 -> 390dp 환산비 0.8245 이고, 1024*0.8245 = 844 이므로
    // 시안은 아이폰 14 크기로 그려진 것이다.

    String code() => io.File('lib/screens/ds/splash_ds_screen.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('🔴 로그인 버튼색이 시안 실측값 #FF6D78 이다', () {
      // 예전 값 #FD717A 는 눈대중이었다.
      expect(code().contains('0xFFFF6D78'), isTrue);
      expect(code().contains('0xFFFD717A'), isFalse,
          reason: '틀린 예전 버튼색이 남아 있다');
    });

    test('🔴 SNS 색이 시안 실측값이다', () {
      final c = code();
      expect(c.contains('0xFFFDE500'), isTrue, reason: '카카오 실측 FDE500');
      expect(c.contains('0xFF02A94D'), isTrue, reason: '네이버 실측 02A94D');
    });

    test('🔴 입력칸 채움이 순백이다', () {
      expect(code().contains('0xFFFFFFFF'), isTrue);
      expect(code().contains('0xFFFBFBFB'), isFalse,
          reason: '회색빛 예전 채움색이 남아 있다');
    });

    test('🔴 로고가 판 없는 코랄 책(FnBookMark)이다', () {
      final c = code();
      expect(c.contains('FnBookMark'), isTrue);
      // FnAppMark 는 '코랄 판 + 흰 책' 이라 시안과 색이 반대다.
      expect(c.contains('FnAppMark'), isFalse,
          reason: '정사각 앱아이콘이 로그인 화면에 남아 있다');
    });

    test('🔴 스플래시도 같은 로고를 쓴다', () {
      final c = io.File('lib/screens/ds/intro_ds_screen.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(c.contains('FnBookMark'), isTrue);
      expect(c.contains('FnAppMark'), isFalse);
    });

    test('🔴 새 심볼 에셋이 실제로 있고 정사각이 아니다', () {
      final f = io.File('assets/brand/logo_symbol_flat.png');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(5000));
      expect(io.File('assets/brand/logo_symbol_mark.png').existsSync(), isTrue);
      // 시안 실측 1.1512 — 정사각(1.0)이 아니다.
      expect(FnBrand.symbolFlatRatio, closeTo(1.1512, 0.01));
    });

    testWidgets('🔴 로그인 화면이 새 심볼을 그린다', (t) async {
      await pumpLogin(t);
      final imgs = t
          .widgetList<Image>(find.byType(Image))
          .map((w) => (w.image as AssetImage).assetName)
          .toList();
      expect(imgs, contains(FnBrand.symbolMarkAsset));
      // 🔴 워드마크도 '전부 검정' 판으로 바뀌었다 (시안 코랄 픽셀 0개).
      expect(imgs, contains(FnBrand.wordmarkFlatAsset));
      expect(imgs.contains(FnBrand.wordmarkAsset), isFalse,
          reason: 'o 가 코랄인 예전 워드마크가 남아 있다');
      expect(imgs.contains(FnBrand.symbolAsset), isFalse);
      expect(imgs.contains(FnBrand.symbolGlowAsset), isFalse);
    });
  });

}
