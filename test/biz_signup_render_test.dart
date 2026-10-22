import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_signup_tokens.dart';
import 'package:flow_note/providers/auth_provider.dart';
import 'package:flow_note/screens/ds/biz_signup_ds_screens.dart';
import 'package:flow_note/screens/ds/signup_parts.dart';
import 'package:flow_note/screens/ds/onboarding_ds_screens.dart' show FnBiz;

/// 🔴 #157 — 사업자등록증 등록 5단계 회귀 방지.
///
/// 단정은 **리터럴 실측값**과 비교한다(토큰끼리 비교하면 토큰을 잘못
/// 바꿔도 통과한다 — #148 에서 실제로 당했다).
void main() {
  Future<void> pump(WidgetTester tester, Widget w) async {
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

  group('#157 1번 — 사업자등록증 안내', () {
    testWidgets('🔴 앱바 제목과 문구가 시안 그대로다', (tester) async {
      await pump(tester, const BizIntroDsScreen());
      expect(find.text('사업자 정보'), findsOneWidget);
      expect(find.text('사업자등록증을\n촬영해주세요'), findsOneWidget);
      expect(find.text('사업자등록증 내용은 자동으로 인식돼요.\n일부 정보는 따로 기재해주세요.'),
          findsOneWidget);
    });

    testWidgets('🔴 버튼 두 개 — 코랄 채움 + 외곽선', (tester) async {
      await pump(tester, const BizIntroDsScreen());
      expect(find.text('사업자등록증 촬영하기'), findsOneWidget);
      expect(find.text('직접 입력할게요'), findsOneWidget);
      // 코랄 채움 1개
      expect(boxOf(const Color(0xFFFF6D78)), findsOneWidget);
      // 외곽선(흰 바탕 + 코랄 테두리) 1개
      final outlined = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.color != const Color(0xFFFFFFFF)) {
          return false;
        }
        final b = d.border;
        return b is Border && b.top.color == const Color(0xFFFF6D78);
      });
      expect(outlined, findsOneWidget);
    });

    testWidgets('🔴 문구가 가운데 정렬이다 (시안 실측)', (tester) async {
      await pump(tester, const BizIntroDsScreen());
      final t = tester.widget<Text>(find.text('사업자등록증을\n촬영해주세요'));
      expect(t.textAlign, TextAlign.center);
    });
  });

  group('#157 2번 — 촬영 (기존 카메라 재사용)', () {
    test('🔴 카메라 화면에 앱바 제목을 넘긴다', () {
      final c = File('lib/screens/ds/biz_signup_ds_screens.dart')
          .readAsStringSync();
      expect(c.contains("navTitle: '사업자등록증 촬영'"), isTrue);
      expect(c.contains("badgeLabel: '사업자등록증'"), isTrue);
      expect(c.contains("frameHint: '사업자등록증을 프레임 안에 맞춰주세요'"), isTrue);
    });

    test('🔴 카메라를 새로 만들지 않고 기존 화면을 쓴다', () {
      final c = File('lib/screens/ds/biz_signup_ds_screens.dart')
          .readAsStringSync();
      expect(c.contains('ScanCameraDsScreen('), isTrue,
          reason: '#148~#154 에서 맞춘 화각을 날리면 안 된다');
      expect(c.contains('CameraPreview('), isFalse,
          reason: '여기서 카메라를 직접 만들면 화각 수정이 또 어긋난다');
    });
  });

  group('#157 3번 — 인식 중', () {
    testWidgets('🔴 제목·부제·진행바가 시안 그대로다', (tester) async {
      await pump(tester, const BizReadingDsScreen());
      expect(find.text('사업자등록증 인식 중'), findsOneWidget);
      expect(find.text('사업자등록증을\n읽고 있어요'), findsOneWidget);
      expect(find.text('상호명, 사업자번호, 대표자와 소재지를\n자동으로 찾고 있어요.'),
          findsOneWidget);
      expect(find.text('인식 진행 중'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('🔴 진행바 색과 두께가 실측값이다', (tester) async {
      await pump(tester, const BizReadingDsScreen());
      final p = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(p.minHeight, 6.0);
      expect(p.backgroundColor, const Color(0xFFFFE4DB));
      expect(p.valueColor!.value, const Color(0xFFFF6D78));
    });

    testWidgets('🔴 다 읽기 전에는 결과 버튼을 누를 수 없다', (tester) async {
      await pump(tester, const BizReadingDsScreen());
      await tester.pump(const Duration(milliseconds: 100));
      final st = tester.state<BizReadingDsScreenState>(
          find.byType(BizReadingDsScreen));
      expect(st.progress, lessThan(1.0));
      // 🔴 화면 전환으로 확인하면 안 된다. `pushReplacement` 는 애니메이션
      //    동안 이전 화면이 트리에 남아 있어서, 버튼을 항상 활성으로 바꿔도
      //    `findsOneWidget` 이 통과해 버린다(사보타주로 확인함).
      //    그래서 **버튼의 onTap 이 null 인지**를 직접 본다.
      final btn = tester.widget<SignupButton>(
        find.ancestor(
          of: find.text('인식 결과 확인하기'),
          matching: find.byType(SignupButton),
        ),
      );
      expect(btn.onTap, isNull,
          reason: '인식이 안 끝났는데 결과 버튼을 누를 수 있다 — 빈 결과가 뜬다');

      // 다 읽은 뒤에는 눌릴 수 있어야 한다.
      await tester.pump(const Duration(milliseconds: 2500));
      final btn2 = tester.widget<SignupButton>(
        find.ancestor(
          of: find.text('인식 결과 확인하기'),
          matching: find.byType(SignupButton),
        ),
      );
      expect(btn2.onTap, isNotNull, reason: '다 읽었는데도 버튼이 죽어 있다');
    });

    testWidgets('🔴 퍼센트가 숫자로 표시된다', (tester) async {
      await pump(tester, const BizReadingDsScreen());
      expect(find.textContaining('%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('#157 4번 — 사업자 정보 확인', () {
    Widget confirm({bool recognized = true}) => BizConfirmDsScreen(
          biz: FnBiz.recognized(),
          recognized: recognized,
        );

    testWidgets('🔴 여섯 칸과 라벨이 시안 그대로다', (tester) async {
      await pump(tester, confirm());
      expect(find.text('사업자 정보 확인'), findsOneWidget);
      for (final l in [
        '상호명',
        '사업자등록번호',
        '대표자',
        '사업장 소재지',
        '전화번호',
        '이메일 주소',
      ]) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('🔴 인식 결과가 네 칸에 채워져 있다', (tester) async {
      await pump(tester, confirm());
      expect(find.text('플로우노트 김사장 꽃집'), findsOneWidget);
      expect(find.text('123-45-67890'), findsOneWidget);
      expect(find.text('김민준'), findsOneWidget);
      expect(find.text('서울특별시 서초구 방배로 12'), findsOneWidget);
    });

    testWidgets('🔴 전화번호·이메일은 비어 있고 `*` 가 붙는다 (시안 실측)',
        (tester) async {
      await pump(tester, confirm());
      final fields = tester.widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[4].controller!.text, isEmpty, reason: '전화번호가 미리 채워졌다');
      expect(fields[5].controller!.text, isEmpty, reason: '이메일이 미리 채워졌다');
      expect(find.text(' *'), findsNWidgets(2));
      expect(find.text('* 표시 항목은 직접 입력해 주셔야 하는 정보예요.'), findsOneWidget);
    });

    testWidgets('🔴 필수 두 칸을 채우기 전에는 버튼이 회색이다', (tester) async {
      await pump(tester, confirm());
      expect(boxOf(const Color(0xFFE5E5E5)), findsOneWidget);
      expect(find.text('확인하고 시작하기'), findsOneWidget);
    });

    testWidgets('🔴 필수 두 칸을 채우면 버튼이 코랄이 된다', (tester) async {
      await pump(tester, confirm());
      final f = find.byType(TextField);
      await tester.enterText(f.at(4), '02-1234-5678');
      await tester.enterText(f.at(5), 'shop@example.com');
      await tester.pump();
      expect(boxOf(const Color(0xFFE5E5E5)), findsNothing);
      // 코랄 = 상단 배지(원형) 는 DecoratedBox 라 Container 가 아니다.
      expect(boxOf(const Color(0xFFFF6D78)), findsOneWidget);
    });

    testWidgets('🔴 한 칸만 채우면 아직 비활성이다', (tester) async {
      await pump(tester, confirm());
      await tester.enterText(find.byType(TextField).at(4), '02-1234-5678');
      await tester.pump();
      final st = tester.state<BizConfirmDsScreenState>(
          find.byType(BizConfirmDsScreen));
      expect(st.canSubmit, isFalse);
    });

    testWidgets('🔴 직접 입력 경로면 인식 완료 배지를 숨긴다', (tester) async {
      await pump(tester, BizConfirmDsScreen(biz: FnBiz(), recognized: false));
      expect(find.text('자동 인식이 완료되었어요'), findsNothing);
      expect(find.text('상호명'), findsOneWidget);
    });

    testWidgets('🔴 하단 안내 카드가 있다', (tester) async {
      await pump(tester, confirm());
      expect(find.text('입력하신 사업자 정보는\n매입 내역 정산서에 자동 반영돼요.'),
          findsOneWidget);
    });
  });

  group('#157 5번 — 가입 완료', () {
    testWidgets('🔴 제목·부제·체크 네 줄·버튼이 시안 그대로다', (tester) async {
      await pump(tester, const BizFinishDsScreen());
      // 🔴 '가입 완료' 는 **앱바 제목과 체크 목록 첫 줄** 두 군데에 나온다.
      //    시안이 그렇게 생겼다. findsOneWidget 으로 두면 틀린 단정이 된다.
      expect(find.text('가입 완료'), findsNWidgets(2));
      expect(find.text('1분 만에 준비가 끝났어요'), findsOneWidget);
      expect(find.text('이제 영수증만 찍으면\n매입 내역이 자동으로 쌓여요'), findsOneWidget);
      for (final l in [
        '가입 완료',
        '사업자등록증 자동 인식 완료',
        '상호명·사업자번호·대표자·이메일 등록',
        '정산서 내보내기 준비 완료',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      expect(find.text('영수증 찍어보기'), findsOneWidget);
    });

    testWidgets('🔴 체크 아이콘이 네 개이고 코랄이다', (tester) async {
      await pump(tester, const BizFinishDsScreen());
      final icons = tester
          .widgetList<Icon>(find.byIcon(Icons.check_rounded))
          .toList();
      expect(icons.length, 4);
      for (final i in icons) {
        expect(i.color, const Color(0xFFFF6D78));
        expect(i.size, 16.0);
      }
    });
  });

  group('#157 그림자 · 토큰', () {
    test('🔴 카드 그림자가 실측대로 아주 연하다', () {
      expect(FnSignup.cardShadow.length, 1);
      final s = FnSignup.cardShadow.first;
      expect(s.color, const Color(0x0F000000));
      expect(s.blurRadius, 12.0);
      expect(s.offset, const Offset(0, 3));
    });

    test('🔴 진행바 토큰이 실측값이다', () {
      expect(FnSignup.progressHeight, 6.0);
      expect(FnSignup.progressTrack, const Color(0xFFFFE4DB));
    });

    testWidgets('🔴 세 화면의 카드가 모두 같은 그림자를 쓴다', (tester) async {
      for (final w in <Widget>[
        const BizReadingDsScreen(),
        BizConfirmDsScreen(biz: FnBiz.recognized(), recognized: true),
        const BizFinishDsScreen(),
      ]) {
        await pump(tester, w);
        final cards = find.byWidgetPredicate((x) {
          if (x is! Container) return false;
          final d = x.decoration;
          return d is BoxDecoration &&
              d.color == const Color(0xFFFFFFFF) &&
              d.boxShadow != null &&
              d.boxShadow!.isNotEmpty;
        });
        expect(cards, findsWidgets, reason: '${w.runtimeType} 에 그림자 카드가 없다');
        for (final e in cards.evaluate()) {
          final d = (e.widget as Container).decoration as BoxDecoration;
          expect(d.boxShadow!.first.color, const Color(0x0F000000),
              reason: '${w.runtimeType} 의 그림자가 시안보다 진하다');
        }
        if (w is BizReadingDsScreen) {
          await tester.pump(const Duration(milliseconds: 2500));
        }
      }
    });
  });

  group('#157 소스 계약', () {
    test('🔴 가입 완료 버튼이 이 흐름을 연다', () {
      final c = File('lib/screens/ds/signup_password_ds_screen.dart')
          .readAsStringSync();
      expect(c.contains('BizIntroDsScreen()'), isTrue,
          reason: "'사업자등록증 등록하러 가기' 가 아무 데도 안 간다");
    });

    test('🔴 계정 이메일을 사업장 이메일로 덮어쓰지 않는다', () {
      final c = File('lib/screens/ds/biz_signup_ds_screens.dart')
          .readAsStringSync();
      // UserModel 에 사업장 이메일 칸이 없다. email: 로 넘기면 로그인
      // 주소가 바뀌어 버린다.
      expect(RegExp(r'updateBusinessInfo\([^)]*email:').hasMatch(c), isFalse,
          reason: '로그인 이메일이 사업장 이메일로 덮어써진다');
    });

    test('🔴 다섯 화면의 앱바 제목이 시안과 같다', () {
      final c = File('lib/screens/ds/biz_signup_ds_screens.dart')
          .readAsStringSync();
      for (final t in [
        "navTitle: '사업자 정보'",
        "navTitle: '사업자등록증 인식 중'",
        "navTitle: '사업자 정보 확인'",
        "navTitle: '가입 완료'",
      ]) {
        expect(c.contains(t), isTrue, reason: t);
      }
    });
  });
}
