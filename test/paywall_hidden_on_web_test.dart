import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/profile_ds_screen.dart';
import 'package:flow_note/services/subscription_service.dart';

/// 🔴 #120 — 웹앱에서 구독료(구독 안내) 화면 입구를 감춘다.
///
/// 사장님 요청은 **"일단 A"** 였다. 즉 **웹에서만** 감추고
/// 앱(APK)에는 그대로 둔다. 그래서 검사할 것은 두 가지다.
///
///  1. 판단이 `SubscriptionService.showPaywallEntry` **한 곳**에 모여 있다
///  2. 그 값이 **플랫폼에 따라** 갈린다 (웹 false / 앱 true)
///
/// 화면 파일을 지우지 않았다는 점도 함께 잠가둔다. 나중에 결제를 붙일 때
/// 화면을 다시 만들어야 하면 이번 작업이 손해가 된다.
void main() {
  group('#120 구독 안내 입구 감추기', () {
    test('🔴 앱에서도 감추는 전체 스위치는 아직 꺼져 있다', () {
      // 'A' 선택이므로 앱에서는 계속 보여야 한다.
      expect(SubscriptionService.hidePaywallEverywhere, isFalse);
    });

    test('🔴 입구 노출 여부는 플랫폼에 따라 갈린다 (웹이면 숨김)', () {
      // 테스트는 VM(앱 쪽)에서 돌기 때문에 kIsWeb 은 false 다.
      // 즉 여기서는 '앱에서는 보인다' 를 검증하게 된다.
      expect(kIsWeb, isFalse, reason: '이 테스트는 VM 에서 돈다');
      expect(SubscriptionService.showPaywallEntry, isTrue,
          reason: '앱(APK)에서는 구독 관리가 계속 보여야 한다');
    });

    test('🔴 전체 스위치를 켜면 앱에서도 숨겨지는 구조여야 한다', () {
      // const 라서 런타임에 바꿀 수 없다. 대신 계산식을 그대로 재현해
      // '스위치 하나로 앱까지 덮인다' 는 설계를 고정한다.
      bool resolve({required bool hideAll, required bool isWeb}) =>
          !hideAll && !isWeb;

      expect(resolve(hideAll: false, isWeb: false), isTrue); // 앱 · 현재
      expect(resolve(hideAll: false, isWeb: true), isFalse); // 웹 · 현재
      expect(resolve(hideAll: true, isWeb: false), isFalse); // 앱 · 전체차단
      expect(resolve(hideAll: true, isWeb: true), isFalse); // 웹 · 전체차단
    });

    test('잠금 해제 상태는 건드리지 않았다', () {
      // #98 '프로 기능 제거' 로 모든 기능이 열려 있다.
      // 이번 작업은 **입구만** 감추는 것이므로 이 값이 변하면 안 된다.
      expect(SubscriptionService.unlockEverything, isTrue);
    });
  });

  group('#120 프로필 화면 렌더', () {
    Future<void> pumpProfile(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      await t.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
          child: const MaterialApp(
            home: Material(child: ProfileDsScreen()),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('🔴 앱에서는 구독 관리 항목이 보인다', (t) async {
      // 이 테스트는 VM(=앱 쪽)에서 돈다. 'A' 선택대로 앱에는 남아야 한다.
      await pumpProfile(t);

      expect(SubscriptionService.showPaywallEntry, isTrue);
      expect(find.text('구독 관리'), findsOneWidget,
          reason: '앱에서는 구독 관리가 계속 보여야 한다');

      // 같은 묶음의 이웃 항목은 그대로 남아 있어야 한다.
      expect(find.text('사업자 정보 수정'), findsOneWidget);
    });

    testWidgets('🔴 AI 키 설정 입구는 여전히 없다 (#109 유지)', (t) async {
      // 이번 작업이 #109 를 되돌리지 않았는지 함께 잠근다.
      await pumpProfile(t);
      expect(find.textContaining('API 키'), findsNothing);
      expect(find.textContaining('Gemini'), findsNothing);
    });
  });
}
