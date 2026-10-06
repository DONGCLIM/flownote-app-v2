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
}
