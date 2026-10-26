// 요청 #141 회귀 — 프로필 화면 + 알림 설정 화면 시안 반영.
//
// ## 프로필 시안 실측 (425x1024, 환산비 0.9176 -> 390 x 939.7dp)
//
//   배경            #FEF9F5
//   무료 플랜 배지   y 127.6dp  204.6 x 26.6dp  #FF6D78
//   아바타 원        98.2 x 99.1dp  대각 #FF787C -> #FFA08E
//   편집 뱃지        20.2 x 20.2dp  #FFD4C4
//   카드1(계정)      y 383.6..601.1dp  구분선 3개 = 항목 4개
//                   (사업자 정보 수정 / 구독 관리 / 알림 설정 / 로그아웃)
//   카드2(고객지원)   y 657.0..822.2dp
//   카드 좌우        19.3~20.2dp
//
// ## 알림 설정 시안 실측 (473x1024, 환산비 0.8245 -> 390 x 844.3dp)
//
//   카드 좌우        19.8dp
//   토글            44.5 x 26.4dp   켜짐 #FF6D78 / 꺼짐 #E5E5E5
//   켜짐 4개(영수증·정산·리포트·공지) / 꺼짐 1개(이벤트)
//
// 🔴 바꾸기 전 상태(= 이 테스트가 막으려는 회귀):
//    - 프로필 상단에 아바타·상호명이 아예 없었다
//    - 목록이 흰 카드 없이 배경 위에 놓여 있었다
//    - 로그아웃이 화면 아래 글자 버튼이었다
//    - '알림 설정' 은 '준비 중이에요' 스낵바였다

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/profile_ds_screen.dart';
import 'package:flow_note/screens/ds/notification_settings_ds_screen.dart';
import 'package:flow_note/services/notification_prefs.dart';

Future<void> _pumpProfile(
  WidgetTester t, {
  Size size = const Size(390, 1200),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: const MaterialApp(home: Scaffold(body: ProfileDsScreen())),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpNotif(
  WidgetTester t, {
  Size size = const Size(390, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    const MaterialApp(home: NotificationSettingsDsScreen()),
  );
  await t.pump(const Duration(milliseconds: 400));
}

/// 해당 글자를 감싸는 Container 배경색 목록.
List<Color> _bgOf(Finder f) => find
    .ancestor(of: f, matching: find.byType(Container))
    .evaluate()
    .map((e) => (e.widget as Container).decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.color)
    .whereType<Color>()
    .toList();

void main() {
  group('#141 프로필 화면', () {
    testWidgets('예외 없이 그려진다', (t) async {
      await _pumpProfile(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('🔴 상단에 아바타(코랄 그라디언트 원)가 있다', (t) async {
      await _pumpProfile(t);
      // #164 에서 Container -> DecoratedBox 로 바뀌었다(Positioned.fill).
      final circles = find
          .byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).gradient != null)
          .evaluate()
          .map((e) =>
              ((e.widget as DecoratedBox).decoration as BoxDecoration).gradient)
          .whereType<LinearGradient>()
          .toList();
      expect(circles, isNotEmpty, reason: '그라디언트 원이 없다');
      // #164 재실측: 대각 #FF6F7C -> #F5AF99
      expect(circles.first.colors, contains(const Color(0xFFFF6F7C)));
      expect(circles.first.colors, contains(const Color(0xFFF5AF99)));
    });

    testWidgets('🔴 아바타 크기가 시안과 같다 (98x99dp)', (t) async {
      await _pumpProfile(t);
      final c = find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle);
      expect(c, findsWidgets);
      final s = t.getSize(c.first);
      // #164 재실측 98.2 정원.
      expect(s.width, closeTo(98, 2), reason: '시안 98.2dp');
      expect(s.height, closeTo(98, 2), reason: '시안 98.2dp');
    });

    testWidgets('🔴 상호명과 부가정보 줄이 보인다', (t) async {
      await _pumpProfile(t);
      // 값이 없을 때 시안 예시값을 그대로 쓰지 않는다 — 안내 문구가 나온다.
      expect(find.text('상호명을 입력해 주세요'), findsOneWidget);
      expect(find.text('사업자 정보를 입력하면 여기에 보여요'), findsOneWidget);
      // 시안 예시값이 새어 나오면 안 된다.
      expect(find.text('플로우노트'), findsNothing);
      expect(find.textContaining('김민준'), findsNothing);
      expect(find.textContaining('123-45-67890'), findsNothing);
    });

    testWidgets('🔴 메뉴가 흰 카드 안에 들어 있다', (t) async {
      await _pumpProfile(t);
      expect(_bgOf(find.text('사업자 정보 수정')),
          contains(const Color(0xFFFFFFFF)),
          reason: '시안 메뉴는 흰 카드 안에 있다');
      expect(_bgOf(find.text('공지사항')), contains(const Color(0xFFFFFFFF)),
          reason: '고객 지원 카드도 흰색이다');
    });

    testWidgets('🔴 로그아웃이 카드 안 메뉴 항목이다', (t) async {
      await _pumpProfile(t);
      final out = find.text('로그아웃');
      expect(out, findsOneWidget, reason: '로그아웃 항목이 없다');
      expect(_bgOf(out), contains(const Color(0xFFFFFFFF)),
          reason: '로그아웃도 흰 카드 안에 있어야 한다');
      // 같은 카드 안에 '알림 설정' 도 있어야 한다 (시안 카드1 = 4항목)
      expect(find.text('알림 설정'), findsOneWidget);
    });

    testWidgets('기능 유지 — 회원 탈퇴·마케팅 동의가 그대로 있다', (t) async {
      await _pumpProfile(t);
      expect(find.text('회원 탈퇴'), findsOneWidget);
      expect(find.textContaining('마케팅'), findsWidgets);
    });

    testWidgets('기능 유지 — 사업자 정보로 가는 길이 살아 있다', (t) async {
      // 🔴 #164 시안에는 접이식 '사업자 정보' 카드가 없다. 대신
      //    '사업자 정보 수정' 한 줄로 들어간다. 정보를 보거나 고칠
      //    길 자체가 사라지면 안 되므로 그 줄의 존재를 확인한다.
      await _pumpProfile(t);
      expect(find.text('사업자 정보 수정'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('🔴 코랄 무료 플랜 배지가 보인다', (t) async {
      await _pumpProfile(t);
      // 🔴 이 검사는 실제 버그를 잡는다.
      // 조건이 `!isPro` 였을 때 `unlockEverything = true` 때문에
      // `isPro` 가 항상 true -> 배지가 영원히 안 보였다.
      // 지금은 `!purchasedPro`(실결제 여부)를 본다.
      final badge = find.text('대표님, 한달 무료 플랜을 이용해보세요!');
      expect(badge, findsOneWidget, reason: '시안의 코랄 배지가 없다');
      expect(_bgOf(badge), contains(const Color(0xFFFF6D78)),
          reason: '시안 배지 색 #FF6D78');
      // 시안 실측 높이 26.6dp (글자 12 + 상하 7 = 26)
      expect(t.getSize(badge.first).height, lessThan(40));
    });

    testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
      await _pumpProfile(t, size: const Size(320, 1200));
      expect(t.takeException(), isNull);
    });

    testWidgets('🔴 좁은 화면(320)에서도 목록 글자가 잘리지 않는다', (t) async {
      // #164 시안에서 '전자세금계산서 연동용' 배지가 사라졌다.
      //    대신 가장 긴 줄이 좁은 화면에서 넘치지 않는지 본다.
      await _pumpProfile(t, size: const Size(320, 1200));
      expect(find.text('이용약관 및 개인정보 처리방침'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('#141 알림 설정 화면', () {
    setUp(() => NotificationPrefs.instance.resetForTest());

    testWidgets('예외 없이 그려지고 시안 문구가 보인다', (t) async {
      await _pumpNotif(t);
      expect(t.takeException(), isNull);
      expect(find.text('알림 설정'), findsOneWidget);
      expect(find.text('필요한 알림만 받아보세요'), findsOneWidget);
      expect(find.text('설정은 변경하는 즉시 저장돼요.'), findsOneWidget);
    });

    testWidgets('🔴 시안 항목 5개와 묶음 2개가 모두 있다', (t) async {
      await _pumpNotif(t);
      for (final s in [
        '서비스 알림',
        '혜택 알림',
        '영수증 처리 알림',
        '정산·신고 알림',
        '경영 리포트',
        '공지사항',
        '이벤트 및 혜택',
      ]) {
        expect(find.text(s), findsOneWidget, reason: '$s 이(가) 없다');
      }
    });

    testWidgets('🔴 기본 상태가 시안과 같다 (4개 켜짐 / 1개 꺼짐)', (t) async {
      await _pumpNotif(t);
      final on = <String>[];
      final off = <String>[];
      for (final o in NotificationPrefs.options) {
        (o.defaultOn ? on : off).add(o.key);
      }
      expect(on.length, 4, reason: '시안에서 켜진 토글은 4개다');
      expect(off, ['event'], reason: '시안에서 꺼진 것은 이벤트 및 혜택뿐이다');
    });

    testWidgets('🔴 토글 색이 시안과 같다 (#FF6D78 / #E5E5E5)', (t) async {
      await _pumpNotif(t);
      final colors = find
          .byType(AnimatedContainer)
          .evaluate()
          .map((e) => (e.widget as AnimatedContainer).decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .map((c) => c.toARGB32())
          .toSet();
      expect(colors, contains(0xFFFF6D78), reason: '켜진 토글 코랄이 없다');
      expect(colors, contains(0xFFE5E5E5), reason: '꺼진 토글 회색이 없다');
    });

    testWidgets('🔴 토글 크기가 시안과 같다 (45x26dp)', (t) async {
      await _pumpNotif(t);
      final s = t.getSize(find.byType(AnimatedContainer).first);
      expect(s.width, closeTo(45, 1.5), reason: '시안 44.5dp');
      expect(s.height, closeTo(26, 1.5), reason: '시안 26.4dp');
    });

    testWidgets('🔴 토글을 누르면 즉시 바뀐다', (t) async {
      await _pumpNotif(t);
      expect(NotificationPrefs.instance.isOn('event'), isFalse);
      await t.tap(find.text('이벤트 및 혜택'));
      await t.pump(const Duration(milliseconds: 250));
      expect(NotificationPrefs.instance.isOn('event'), isTrue,
          reason: '누르면 켜져야 한다');
      await t.tap(find.text('이벤트 및 혜택'));
      await t.pump(const Duration(milliseconds: 250));
      expect(NotificationPrefs.instance.isOn('event'), isFalse,
          reason: '다시 누르면 꺼져야 한다');
    });

    testWidgets('🔴 카드 좌우 여백이 시안 24dp 다', (t) async {
      await _pumpNotif(t, size: const Size(390, 900));
      final card = find.ancestor(
        of: find.text('영수증 처리 알림'),
        matching: find.byWidgetPredicate((w) {
          if (w is! Container) return false;
          final d = w.decoration;
          return d is BoxDecoration && d.color == const Color(0xFFFFFFFF);
        }),
      );
      expect(card, findsWidgets);
      final r = t.getRect(card.first);
      // #164 재실측: 좌 24.1dp (이전 #141 실측 19.8 은 환산비가 틀렸다)
      expect(r.left, closeTo(24, 1.5), reason: '시안 좌 24.1dp');
      // #164 재실측: 우 24.1dp
      expect(390 - r.right, closeTo(24, 1.5), reason: '시안 우 24.1dp');
    });

    testWidgets('좁은 화면(320)에서도 오버플로가 없다', (t) async {
      await _pumpNotif(t, size: const Size(320, 800));
      expect(t.takeException(), isNull);
      expect(find.text('영수증 처리 알림'), findsOneWidget);
    });
  });
}
