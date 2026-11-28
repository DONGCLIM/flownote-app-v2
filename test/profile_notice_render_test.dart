import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flow_note/design/fn_profile_tokens.dart';
import 'package:flow_note/screens/ds/notice_list_ds_screen.dart';
import 'package:flow_note/screens/ds/notification_settings_ds_screen.dart';
import 'package:flow_note/services/notice_feed.dart';
import 'package:flow_note/services/notification_prefs.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationPrefs.instance.resetForTest();
    NoticeFeed.instance.resetForTest();
  });

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: w,
    ));
    await t.pump(const Duration(milliseconds: 400));
  }

  group('#164 시안 토큰', () {
    test('세 화면 배경은 시안 실측 #FEF9F5 이다', () {
      expect(FnProfile.bg, const Color(0xFFFEF9F5));
    });

    test('코랄은 시안 실측 #FF6D78 이다', () {
      expect(FnProfile.coral, const Color(0xFFFF6D78));
    });

    test('꺼진 토글은 시안 실측 #E5E5E5 이다', () {
      expect(FnProfile.toggleOff, const Color(0xFFE5E5E5));
    });

    test('토글 크기는 시안 실측 43.2x24.9 에 맞춘 44x25 이다', () {
      expect(FnProfile.toggleW, 44.0);
      expect(FnProfile.toggleH, 25.0);
    });

    test('아바타는 시안 실측 98.2dp 이다', () {
      expect(FnProfile.avatar, 98.0);
    });

    test('카드에는 그림자가 있다 (시안 실측 알파 약 6%)', () {
      expect(FnProfile.cardShadow, isNotEmpty);
      expect(FnProfile.cardShadow.first.blurRadius, greaterThan(0));
    });
  });

  group('#164 알림 설정 — 토글이 실제로 켜지고 꺼진다', () {
    testWidgets('시안 문구와 다섯 항목이 모두 보인다', (t) async {
      await pump(t, const NotificationSettingsDsScreen());
      expect(find.text('필요한 알림만 받아보세요'), findsOneWidget);
      expect(find.text('설정은 변경하는 즉시 저장돼요.'), findsOneWidget);
      expect(find.text('서비스 알림'), findsOneWidget);
      expect(find.text('혜택 알림'), findsOneWidget);
      for (final o in NotificationPrefs.options) {
        expect(find.text(o.title), findsOneWidget, reason: o.title);
      }
    });

    testWidgets('🔴 켜진 항목을 누르면 꺼진다', (t) async {
      await pump(t, const NotificationSettingsDsScreen());
      expect(NotificationPrefs.instance.isOn('receipt'), isTrue,
          reason: '영수증 알림은 기본이 켜짐이다');
      await t.tap(find.text('영수증 처리 알림'));
      await t.pump(const Duration(milliseconds: 300));
      expect(NotificationPrefs.instance.isOn('receipt'), isFalse,
          reason: '눌렀는데 안 꺼지면 토글이 죽은 것이다');
    });

    testWidgets('🔴 꺼진 항목을 누르면 켜진다', (t) async {
      await pump(t, const NotificationSettingsDsScreen());
      expect(NotificationPrefs.instance.isOn('event'), isFalse,
          reason: '이벤트 알림은 기본이 꺼짐이다');
      await t.tap(find.text('이벤트 및 혜택'));
      await t.pump(const Duration(milliseconds: 300));
      expect(NotificationPrefs.instance.isOn('event'), isTrue);
    });

    testWidgets('🔴 토글 자체를 눌러도 바뀐다', (t) async {
      await pump(t, const NotificationSettingsDsScreen());
      final before = NotificationPrefs.instance.isOn('report');
      await t.tap(find.byType(FnToggle).at(2));
      await t.pump(const Duration(milliseconds: 300));
      expect(NotificationPrefs.instance.isOn('report'), !before);
    });

    testWidgets('🔴 저장 키를 바꾸면 안 된다 (기존 설정이 날아간다)', (t) async {
      final src = _read('lib/services/notification_prefs.dart');
      expect(src.contains("'notif_pref_\$key'"), isTrue,
          reason: '저장 키 형식을 바꾸면 쓰던 분들 설정이 초기화된다');
      for (final k in ['receipt', 'settle', 'report', 'notice', 'event']) {
        expect(src.contains("key: '$k'"), isTrue, reason: k);
      }
    });
  });

  group('#164 알림목록 — 화면', () {
    testWidgets('시안 다섯 건과 필터 칩 네 개가 보인다', (t) async {
      await pump(t, const NoticeListDsScreen());
      expect(find.text('전체'), findsOneWidget);
      // '알림' 은 필터 칩에도, 배지에도 나온다. 하나만 있으면 오히려 틀린다.
      expect(find.text('알림'), findsWidgets);
      expect(find.text('공지사항'), findsOneWidget);
      expect(find.text('이벤트'), findsWidgets);
      expect(find.text('플로우노트 업데이트 안내'), findsOneWidget);
      expect(find.text('영수증 촬영 오류 해결 안내'), findsOneWidget);
      expect(find.text('26.09.18'), findsNWidgets(5));
    });

    testWidgets('🔴 칩을 누르면 그 분류만 남는다', (t) async {
      await pump(t, const NoticeListDsScreen());
      await t.tap(find.text('공지사항'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('플로우노트 업데이트 안내'), findsOneWidget);
      expect(find.text('영수증 촬영 오류 해결 안내'), findsOneWidget);
      expect(find.text('8월 매출 총 매입을\n확인해보세요.'), findsNothing,
          reason: '공지만 골랐는데 알림이 남으면 필터가 죽은 것이다');
    });

    testWidgets('🔴 누르면 읽음으로 바뀐다', (t) async {
      await pump(t, const NoticeListDsScreen());
      expect(NoticeFeed.instance.isRead('n-2026-09-18-update'), isFalse);
      await t.tap(find.text('플로우노트 업데이트 안내'));
      await t.pump(const Duration(milliseconds: 300));
      expect(NoticeFeed.instance.isRead('n-2026-09-18-update'), isTrue);
    });

    test('🔴 분류 배지가 가로로 늘어나면 안 된다', () {
      final src = _read('lib/screens/ds/notice_list_ds_screen.dart');
      // Container 에 alignment 를 주면 폭 제약이 없을 때 전체로 늘어난다.
      // 렌더를 찍어서 실제로 늘어난 것을 확인하고 Align 으로 감쌌다.
      final i = src.indexOf('Widget _badge(');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 700);
      expect(body.contains('Align('), isTrue,
          reason: 'Align 이 빠지면 배지가 화면 끝까지 늘어난다');
    });

    test('🔴 일반 사용자가 글을 쓸 수 있는 길이 없어야 한다', () {
      final src = _read('lib/services/notice_feed.dart');
      // 읽음 표시 말고 내용을 더하거나 고치는 함수가 있으면 안 된다.
      expect(src.contains('void add('), isFalse);
      expect(src.contains('Future<void> add('), isFalse);
      expect(src.contains('void remove('), isFalse);
      expect(src.contains('set items'), isFalse);
      final list = _read('lib/screens/ds/notice_list_ds_screen.dart');
      expect(list.contains('TextField'), isFalse,
          reason: '목록 화면에 글 입력칸이 있으면 누구나 쓸 수 있게 된다');
    });

    test('🔴 글 id 는 서로 겹치면 안 된다', () {
      final ids = NoticeFeed.instance.items.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'id 가 겹치면 하나를 읽을 때 다른 글도 읽음이 된다');
    });

    test('날짜 표기는 시안대로 26.09.18 이다', () {
      expect(NoticeFeed.instance.items.first.ymd, '26.09.18');
    });
  });

  group('#164 프로필 화면', () {
    test('🔴 종을 누르면 알림목록이 열려야 한다', () {
      final src = _read('lib/screens/ds/main_ds_screen.dart');
      expect(src.contains('NoticeListDsScreen'), isTrue);
      expect(src.contains("Text('알림은 준비 중이에요')"), isFalse,
          reason: '화면이 생겼는데 준비 중 스낵바가 남아 있으면 안 된다');
    });

    test('🔴 종의 빨간 점은 안 읽은 알림이 있을 때만 켜진다', () {
      final src = _read('lib/screens/ds/main_ds_screen.dart');
      expect(src.contains('bellDot: true,'), isFalse,
          reason: '늘 true 면 다 읽어도 점이 사라지지 않는다');
      expect(src.contains('bellDot: NoticeFeed.instance.hasUnread,'), isTrue);
    });

    test('🔴 사장님 정보가 없을 때 시안 예시값을 보여주면 안 된다', () {
      final src = _read('lib/screens/ds/profile_ds_screen.dart');
      expect(src.contains("'플로우노트'"), isFalse,
          reason: '입력 안 한 값을 입력한 것처럼 보여주면 안 된다');
      expect(src.contains('123-45-67890'), isFalse);
      expect(src.contains('김민준'), isFalse);
      expect(src.contains("'상호명을 입력해 주세요'"), isTrue);
    });

    test('🔴 무료 플랜 배지 조건은 purchasedPro 여야 한다', () {
      final src = _read('lib/screens/ds/profile_ds_screen.dart');
      expect(src.contains('!SubscriptionService.instance.purchasedPro'), isTrue,
          reason: 'isPro 는 전면 개방 때문에 늘 true 라 배지가 안 뜬다');
    });

    test('🔴 법/심사상 꼭 있어야 하는 것들을 지우면 안 된다', () {
      final src = _read('lib/screens/ds/profile_ds_screen.dart');
      expect(src.contains('마케팅 정보 수신'), isTrue,
          reason: '선택 동의는 언제든 철회할 수 있어야 한다');
      expect(src.contains('회원 탈퇴'), isTrue, reason: '마켓 심사 필수');
      expect(src.contains('LegalDocKind.terms'), isTrue);
      expect(src.contains('LegalDocKind.privacy'), isTrue);
    });

    test('시안 목록 항목이 모두 있다', () {
      final src = _read('lib/screens/ds/profile_ds_screen.dart');
      for (final s in [
        '계정/서비스 관리',
        '사업자 정보 수정',
        '알림 설정',
        '로그아웃',
        '고객 지원 및 안내',
        '공지사항',
        '제안 및 피드백',
        '이용약관 및 개인정보 처리방침',
      ]) {
        expect(src.contains("'$s'"), isTrue, reason: s);
      }
    });

    test('🔴 프로필 공지사항은 준비 중 스낵바가 아니라 알림목록으로 간다', () {
      final src = _read('lib/screens/ds/profile_ds_screen.dart');
      expect(src.contains("_todo(context, '공지사항')"), isFalse);
      expect(src.contains('NoticeListDsScreen'), isTrue);
    });
  });
}
