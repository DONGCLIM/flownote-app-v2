import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 요청 #30 회귀 — "로그인은 되는데 다음 화면으로 안 넘어간다".
///
/// ## 진짜 원인
/// 앱의 화면 전환은 루트 `_AppEntry` 하나가 담당한다.
/// ```dart
/// return auth.isLoggedIn ? const MainDsScreen() : const SplashDsScreen();
/// ```
/// 그런데 로그아웃 / 회원가입 / 온보딩 완료 3곳에서
/// `pushAndRemoveUntil(..., (r) => false)` 를 써서 스택을 통째로 비웠다.
/// 이 조건은 **루트까지 제거**하므로 `_AppEntry` 자체가 트리에서 사라진다.
/// → 이후 로그인에 성공해서 `isLoggedIn == true` 가 되어도
///   화면을 바꿔줄 위젯이 없어서 스플래시가 그대로 남는다.
///
/// 이 테스트는 그 네비게이션 규칙을 못으로 박아 둔다.
void main() {
  group('네비게이션 규칙 — 루트(_AppEntry)는 절대 제거되지 않는다', () {
    testWidgets('(r) => false 는 루트까지 제거한다 (금지 패턴 증명)', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Text('ROOT'),
      ));
      expect(find.text('ROOT'), findsOneWidget);

      // 금지 패턴: 루트까지 날아간다.
      nav.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Text('PUSHED')),
        (r) => false,
      );
      await tester.pumpAndSettle();

      expect(find.text('PUSHED'), findsOneWidget);
      // 루트가 사라졌으므로 더 이상 pop 할 곳이 없다 = 복귀 불가.
      expect(nav.currentState!.canPop(), isFalse);
    });

    testWidgets('(r) => r.isFirst 는 루트를 보존한다 (권장 패턴)', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Text('ROOT'),
      ));

      nav.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Text('PUSHED')),
        (r) => r.isFirst,
      );
      await tester.pumpAndSettle();

      expect(find.text('PUSHED'), findsOneWidget);
      // 루트가 남아 있으므로 언제든 되돌아갈 수 있다.
      expect(nav.currentState!.canPop(), isTrue);

      nav.currentState!.popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
      expect(find.text('ROOT'), findsOneWidget);
    });

    testWidgets('popUntil(isFirst) 로 루트의 로그인 상태 화면이 되살아난다',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final loggedIn = ValueNotifier<bool>(false);

      // 루트 = _AppEntry 와 동일 구조 (상태를 보고 화면을 고른다)
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: ValueListenableBuilder<bool>(
          valueListenable: loggedIn,
          builder: (_, v, __) => Text(v ? 'HOME' : 'SPLASH'),
        ),
      ));
      expect(find.text('SPLASH'), findsOneWidget);

      // 로그인 화면을 루트 위에 push (SignInDsScreen 과 동일한 상황)
      nav.currentState!.push(
          MaterialPageRoute(builder: (_) => const Text('SIGN_IN')));
      await tester.pumpAndSettle();
      expect(find.text('SIGN_IN'), findsOneWidget);

      // 로그인 성공: 상태만 바꾸면 화면은 그대로다 (버그 재현)
      loggedIn.value = true;
      await tester.pumpAndSettle();
      expect(find.text('SIGN_IN'), findsOneWidget,
          reason: '루트 위에 얹혀 있으면 상태만 바뀌어도 화면이 안 바뀐다');
      expect(find.text('HOME'), findsNothing);

      // 수정된 동작: 루트까지 pop → 루트가 HOME 을 그린다
      if (nav.currentState!.canPop()) {
        nav.currentState!.popUntil((r) => r.isFirst);
      }
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  _k195GuestLink();
}

// ─────────────────────────────────────────────────────────────────────
//  #195 ⑤ 체험 계정 → 정식 계정 전환 (구글·애플·이메일)
//
//  🔴 여기서는 **코드 계약**을 못으로 박는다. 실제 연결은 Firebase 서버가
//     있어야 해서 테스트에서 돌릴 수 없다. 그래서 "무엇을 부르는가" 를
//     소스로 확인한다 — 이 계약이 깨지면 체험 영수증이 조용히 사라진다.
// ─────────────────────────────────────────────────────────────────────
void _k195GuestLink() {
  String read(String p) => File(p).readAsStringSync();

  group('#195 ⑤ 체험 계정 전환 — 연결(link)이지 로그인이 아니다', () {
    test('🔴 구글·애플·이메일 모두 link 로 붙인다 (signIn 이 아니다)', () {
      final src = read('lib/services/auth_service.dart');
      final g = src.substring(src.indexOf('Future<User> linkGuestWithGoogle'),
          src.indexOf('Future<User> linkGuestWithApple'));
      final a = src.substring(src.indexOf('Future<User> linkGuestWithApple'),
          src.indexOf('Future<User> linkGuestWithEmail'));
      final e = src.substring(src.indexOf('Future<User> linkGuestWithEmail'),
          src.indexOf('Object _linkFailure'));

      // 🔴 `signInWith*` 를 쓰면 uid 가 바뀌어 체험 영수증이 전부 사라진다.
      expect(g, anyOf(contains('linkWithPopup'), contains('linkWithCredential')));
      expect(a, contains('linkWithCredential'));
      expect(e, contains('linkWithCredential'));
      for (final part in [g, a, e]) {
        expect(part, isNot(contains('_auth!.signInWithCredential')));
        expect(part, isNot(contains('signInWithPopup')));
      }
    });

    test('🔴 체험(익명) 계정일 때만 붙인다', () {
      final src = read('lib/services/auth_service.dart');
      // 회원이 실수로 이 길에 들어오면 자기 계정에 엉뚱한 수단이 붙는다.
      expect(src, contains('if (u == null || !u.isAnonymous) return null;'));
      final body = src.substring(src.indexOf('Future<User> linkGuestWithGoogle'),
          src.indexOf('Object _linkFailure'));
      expect('_guestUser'.allMatches(body).length, 3,
          reason: '세 수단 모두 체험 계정인지 먼저 봐야 한다');
    });

    test('🔴 이미 쓰인 계정이면 말없이 로그인하지 않는다', () {
      final src = read('lib/services/auth_service.dart');
      final f = src.substring(src.indexOf('Object _linkFailure'),
          src.indexOf('Future<User> signInWithPendingCredential'));
      // credential-already-in-use 를 그 자리에서 로그인으로 바꿔치기하면
      // uid 가 달라져 체험 영수증이 눈앞에서 사라진 것처럼 보인다.
      expect(f, contains("'credential-already-in-use'"));
      expect(f, contains('AuthLinkConflict'));
      expect(f, isNot(contains('signInWithCredential')));
    });
  });

  group('#195 ⑤ 연결 뒤 절차는 기존 가입과 같다', () {
    test('🔴 users/{uid} 문서 생성과 consent_log 기록을 같은 함수로 한다', () {
      final src = read('lib/providers/auth_provider.dart');
      final body = src.substring(src.indexOf('Future<GuestLinkResult> linkGuestTo'),
          src.indexOf('AuthLinkConflict? _pendingLink'));
      // 🔴 기존 소셜 가입과 **같은** 두 함수를 쓴다. 새로 만들면 동의 항목이
      //    갈라지고, 한쪽만 고치는 사고가 난다.
      expect(body, contains('_hydrate(fbUser)'));
      expect(body, contains('_ensureRequiredConsents(fbUser.uid'));
      // _hydrate 가 users 문서를 만든다 (createIfAbsent).
      final hyd = src.substring(src.indexOf('Future<void> _hydrate'));
      expect(hyd, contains('createIfAbsent'));
      // _ensureRequiredConsents 가 동의 이력을 남긴다.
      final con = src.substring(src.indexOf('Future<void> _ensureRequiredConsents'));
      expect(con, contains('recordConsents'));
    });

    test('🔴 새 동의 항목을 만들지 않았다 (약관·개인정보·마케팅 그대로)', () {
      final src = read('lib/providers/auth_provider.dart');
      final b = src.substring(src.indexOf('UserConsents _buildConsents'));
      expect(b, contains('terms:'));
      expect(b, contains('privacy:'));
      expect(b, contains('marketing:'));
      // 동의 묶음은 이 셋뿐이다.
      final model = read('lib/models/user_model.dart');
      final uc = model.substring(model.indexOf('class UserConsents'),
          model.indexOf('Map<String, dynamic> toMap()', model.indexOf('class UserConsents')));
      expect('ConsentRecord?'.allMatches(uc).length, 3,
          reason: '동의 항목이 늘었다 — 기존 가입 흐름과 어긋난다');
    });

    test('🔴 이메일 가입 화면은 게스트일 때만 연결로 간다', () {
      final src = read('lib/screens/ds/auth_ds_screens.dart');
      final s = src.substring(src.indexOf('Future<void> _submit()'));
      final guard = s.indexOf('if (GuestService.instance.isGuest)');
      final signUp = s.indexOf('await auth.signUp(');
      expect(guard, greaterThan(0));
      expect(signUp, greaterThan(guard),
          reason: '회원은 예전 signUp() 으로 그대로 가야 한다');
      expect(s.substring(guard, signUp), contains('GuestLinkMethod.email'));
    });
  });

  group('#195 ⑤ 이미 가입된 계정 — 여쭙고, 체험 데이터는 보존', () {
    test('🔴 안내창 문구와 버튼이 지시대로다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final a = src.substring(src.indexOf('_askSignInInstead(\n'));
      expect(a, contains('이미 가입된 계정이에요'));
      expect(a, contains('이 계정으로 로그인할까요?'));
      expect(a, contains("confirmLabel: '로그인'"));
      expect(a, contains("cancelLabel: '취소'"));
    });

    test('🔴 로그인을 고르셔도 체험 데이터를 지우지 않는다', () {
      final prov = read('lib/providers/auth_provider.dart');
      final s = prov.substring(prov.indexOf('Future<bool> signInWithConflicted'));
      final end = s.indexOf('\n  }\n');
      // 🔴 여기서 지우면 다음 작업(합치기)에서 되살릴 것이 없다.
      expect(s.substring(0, end), isNot(contains('clearAfterSignUp')));

      final sheet = read('lib/widgets/fn_signup_sheet.dart');
      final ask = sheet.substring(sheet.indexOf('_askSignInInstead(\n'));
      expect(ask, isNot(contains('clearAfterSignUp')));
    });

    test('🔴 가입 성공일 때만 체험 카운터를 치운다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final f = src.substring(src.indexOf('Future<void> fnLinkGuestAccount'));
      final ok = f.indexOf('case GuestLinkResult.ok:');
      final conflict = f.indexOf('case GuestLinkResult.conflict:');
      final clear = f.indexOf('clearAfterSignUp');
      expect(ok, greaterThan(0));
      expect(clear, greaterThan(ok));
      expect(clear, lessThan(conflict), reason: '성공 갈래 안에서만 치워야 한다');
    });
  });

  group('#195 ⑤ 카카오는 이번에 붙이지 않는다', () {
    test('🔴 카카오 연결 함수를 만들지 않았다', () {
      final src = read('lib/services/auth_service.dart');
      // 카카오는 커스텀 토큰이라 uid 가 바뀐다. 붙이면 영수증이 사라진다.
      expect(src, isNot(contains('linkGuestWithKakao')));
    });

    test('🔴 카카오 가입 버튼은 기존 로그인 화면으로 간다', () {
      for (final f in [
        'lib/widgets/fn_signup_sheet.dart',
        'lib/screens/ds/profile_ds_screen.dart',
      ]) {
        final src = read(f);
        // 🔴 `indexOf('카카오로')` 로 찾으면 **주석**이 먼저 걸린다.
        //    실제 버튼은 `label:` 이 붙어 있다.
        final i = src.indexOf("label: '카카오로");
        expect(i, greaterThan(0), reason: f);
        // 버튼 바로 아래 onTap 이 로그인 화면으로 간다.
        //
        // 🔴 두 화면이 부르는 모양이 다르다. 바텀시트는 시트를 먼저 닫아야
        //    해서 `_toSignIn`(그 안에서 `fnOpenSignIn`)을 거치고, 프로필은
        //    닫을 시트가 없어 곧바로 부른다. 둘 다 같은 곳으로 간다.
        expect(src.substring(i, i + 160),
            anyOf(contains('fnOpenSignIn'), contains('_toSignIn')),
            reason: f);
        // 연결(link)로 가면 안 된다 — uid 가 바뀌어 영수증이 사라진다.
        expect(src.substring(i, i + 160), isNot(contains('fnLinkGuestAccount')),
            reason: f);
      }
    });

    test('🔴 바텀시트의 _toSignIn 은 결국 로그인 화면으로 간다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final t = src.substring(src.indexOf('void _toSignIn(BuildContext context)'));
      expect(t.substring(0, t.indexOf('\n  }\n')), contains('fnOpenSignIn'));
    });

    test('🔴 "이미 가입하셨나요? 로그인" 도 기존 로그인 화면이다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final i = src.indexOf('이미 가입하셨나요? 로그인');
      expect(i, greaterThan(0));
      expect(src, contains('fnOpenSignIn'));
      // 기존 로그인 화면 = 카카오까지 들어 있는 스플래시.
      expect(src, contains('SplashDsScreen'));
    });
  });

  group('#195 ⑤ 회원 흐름은 그대로다', () {
    test('🔴 기존 가입·로그인 함수를 고치지 않았다', () {
      final src = read('lib/providers/auth_provider.dart');
      for (final f in [
        'Future<bool> signUp({',
        'Future<bool> signIn({',
        'Future<bool> signInWithGoogle({',
        'Future<bool> signInWithApple({',
        'Future<bool> signInWithKakao({',
      ]) {
        expect(src, contains(f), reason: '$f 가 사라졌다');
      }
      // 🔴 기존 로그인 함수 안에 게스트 분기가 들어가면 회원이 위험하다.
      final g = src.substring(src.indexOf('Future<bool> signInWithGoogle({'),
          src.indexOf('Future<bool> signInWithApple({'));
      expect(g, isNot(contains('GuestService')));
      expect(g, isNot(contains('isAnonymous')));
    });

    test('🔴 가입 완료 안내가 바탕화면 설치로 이어진다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final a = src.substring(src.indexOf('Future<void> _afterSignUp'));
      expect(a, contains('가입 완료! 찍어둔 영수증이 저장됐어요'));
      expect(a, contains('AddToHomeSheet.open'));
    });

    test('🔴 아이폰 체험 설치 안내 문구는 게스트에게만 다르다', () {
      final src = read('lib/screens/ds/add_to_home_sheet.dart');
      expect(src, contains('가입한 뒤 설치하면 영수증이 그대로 보여요'));
      // 회원 문구는 그대로 남아 있다.
      expect(src, contains('한 번 설치하면 앱처럼 바로 열려요.'));
      expect(src, contains('GuestService.instance.isGuest'));
    });
  });
}
