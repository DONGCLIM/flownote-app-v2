import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flow_note/design/fn_receipt_illust.dart';
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

  group('#158 영수증 일러스트 — 비어 있던 자리', () {
    testWidgets('🔴 가입 완료 화면에 일러스트가 실제로 그려진다', (tester) async {
      await pump(tester, const BizFinishDsScreen());
      // 🔴 #157 에서는 이게 없었다. SizedBox 로 공간만 두고 그림을 안 그렸다.
      expect(find.byType(FnReceiptIllust), findsOneWidget,
          reason: '영수증 그림이 또 사라졌다 — 사장님이 바로 알아채신 문제다');
    });

    testWidgets('🔴 일러스트가 가운데 정렬이다 (시안 실측: 중심 236.0 vs 236.5)',
        (tester) async {
      await pump(tester, const BizFinishDsScreen());
      final r = tester.getRect(find.byType(FnReceiptIllust));
      expect(r.center.dx, closeTo(375 / 2, 1.0));
    });

    testWidgets('🔴 일러스트 크기가 시안 실측값이다', (tester) async {
      await pump(tester, const BizFinishDsScreen());
      final r = tester.getRect(find.byType(FnReceiptIllust));
      // 시안 243x192px ÷ 1.26133 = 192.7 x 152.2dp
      expect(r.width, closeTo(192.7, 1.0));
      expect(r.height, closeTo(152.2, 1.5));
    });

    test('🔴 종이가 세 장이고 가운데가 맨 앞이다', () {
      final p = ReceiptIllustPainter.papers;
      expect(p.length, 3);
      // 리스트 순서 = 그리는 순서. 마지막(가운데)이 맨 앞.
      expect(p.last.left, greaterThan(p[0].left), reason: '가운데가 왼쪽보다 오른쪽');
      expect(p.last.left, lessThan(p[1].left), reason: '가운데가 오른쪽보다 왼쪽');
    });

    test('🔴 일러스트는 그림 자산이 아니라 벡터로 그린다', () {
      final code =
          File('lib/design/fn_receipt_illust.dart').readAsStringSync();
      // assets/ 에 영수증 그림이 없다. Image.asset 을 쓰면 빈칸이 된다.
      expect(code.contains('Image.asset'), isFalse,
          reason: 'assets 에 영수증 그림이 없다 — 또 빈칸이 된다');
      expect(code.contains('CustomPaint'), isTrue);
    });
  });

  // =====================================================================
  // 🔴 #159 — 사장님이 지적하신 두 가지.
  //   1) "옆에 글로우도 너무 어색하게 네모져있거든"
  //   2) "맨 오른쪽 영수증 이미지 너무 얇고 다르잖아"
  // 둘 다 내 실측 실수였다. 재발 방지를 위해 불변식으로 고정한다.
  // =====================================================================
  group('#159 글로우 네모짐 · 오른쪽 종이 두께', () {
    /// 🔴 주석을 뺀 **실제 코드만** 돌려준다.
    /// 왜 이게 필요한가: 이 파일 주석에는 "#158 에서 RadialGradient 를
    /// 썼다가 네모져 보였다" 같은 경위 설명이 들어 있다. 원문 전체를
    /// 검사하면 그 설명 문구를 코드 잔재로 잘못 읽어 테스트가 깨진다.
    String code() {
      final raw = File('lib/design/fn_receipt_illust.dart').readAsStringSync();
      return raw
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//');
          })
          .join('\n');
    }

    test('🔴 세 장이 모두 비슷한 크기다 (한 장만 얇으면 안 된다)', () {
      final p = ReceiptIllustPainter.papers;
      final ws = p.map((e) => e.width).toList();
      final minW = ws.reduce((a, b) => a < b ? a : b);
      final maxW = ws.reduce((a, b) => a > b ? a : b);
      // 시안 실측: 79.2 / 80.2 / 80.9 px → 편차 1.7px (박스 243px 대비 0.7%)
      expect(maxW - minW, lessThan(0.02),
          reason: '#158 에서 오른쪽을 0.1934(47px)로 넣어 "너무 얇다"고 하셨다. '
              '그건 가려지고 남은 가시 폭이었지 본래 폭이 아니다');
      // 폭이 절반 수준으로 돌아가는 퇴행을 직접 막는다.
      for (final w in ws) {
        expect(w, greaterThan(0.30),
            reason: '종이 한 장이 다시 얇아졌다');
      }
    });

    test('🔴 세 장의 높이도 비슷하다', () {
      final hs = ReceiptIllustPainter.papers.map((e) => e.height).toList();
      final minH = hs.reduce((a, b) => a < b ? a : b);
      final maxH = hs.reduce((a, b) => a > b ? a : b);
      expect(maxH - minH, lessThan(0.02));
    });

    test('🔴 기울기가 왼쪽→오른쪽 부채꼴로 단조 감소한다', () {
      final p = ReceiptIllustPainter.papers;
      // papers 순서는 [왼쪽, 오른쪽, 가운데] (그리는 순서)
      final left = p[0], right = p[1], center = p[2];
      // 시안 실측 (바깥 변 직선 피팅, 잔차 0.30~0.45)
      //   왼쪽 dx/dy=-0.1599 → +9.08도
      //   가운데 좌변 -0.0187 / 우변 -0.0136 → +0.93도
      //   오른쪽 dx/dy=+0.1363 → -7.76도
      expect(left.turn, closeTo(9.08, 0.01), reason: '왼쪽');
      expect(center.turn, closeTo(0.93, 0.01), reason: '가운데');
      expect(right.turn, closeTo(-7.76, 0.01), reason: '오른쪽');
      // 🔴 #158 에서 세 장 모두 부호가 반대였다. 방향을 명시적으로 고정한다.
      expect(left.turn, greaterThan(0),
          reason: '왼쪽 장은 시계 방향으로 기운다');
      expect(right.turn, lessThan(0),
          reason: '오른쪽 장은 반시계 방향으로 기운다 — #158 에서 반대였다');
      // 화면 왼쪽일수록 더 시계 방향 = 부채꼴
      expect(left.turn, greaterThan(center.turn));
      expect(center.turn, greaterThan(right.turn));
    });

    test('🔴 글로우를 사각형으로 칠하지 않는다 (네모진 테두리의 원인)', () {
      final c = code();
      // 🔴 #158 은 drawRect + RadialGradient(radius 0.78) 이었다.
      //    대각선 거리 1.0 까지 가기 전에 사각형에서 잘려 테두리가 보였다.
      expect(c.contains('drawRect('), isFalse,
          reason: '사각형을 칠하면 글로우 경계가 네모로 보인다');
      expect(c.contains('RadialGradient'), isFalse,
          reason: '방사 그라디언트는 사각 캔버스에서 잘린다');
      // 대신 종이 실루엣을 블러한다 → 모양이 종이를 따라가므로 각이 안 생긴다.
      expect(c.contains('MaskFilter.blur'), isTrue);
      expect(c.contains('glowBlur'), isTrue);
    });

    test('🔴 글로우가 과하지 않다 (코랄 배경처럼 보이면 안 된다)', () {
      // 실측 최대 차이가 R-3 G-12 B-9 → 알파 0x1A 수준.
      expect(ReceiptIllustPainter.glowColor, const Color(0x1AFF6D78),
          reason: '진하면 코랄 배경처럼 보인다 — #158 에서 이미 겪었다');
      expect(code().contains('Color(0x33FF6D78)'), isFalse,
          reason: '처음에 넣었다가 코랄 배경처럼 보였던 그 값이다');
    });

    test('🔴 글로우 번짐이 충분히 넓다 (좁으면 경계가 드러난다)', () {
      // 실측: 종이 둘레에서 r 90px(=71dp) 까지 서서히 사라진다.
      expect(ReceiptIllustPainter.glowBlur, greaterThanOrEqualTo(20.0));
    });

    test('🔴 줄 색이 시안 실측값이다', () {
      // 🔴 #158 의 greyLine #F2F1F0(G=241) 은 너무 진했다.
      //    시안 세로 프로파일상 본문줄은 (250,250,250) 이다.
      expect(ReceiptIllustPainter.greyLine, const Color(0xFFFAFAFA));
      // 코랄줄 코어 평균 (250,187,193)
      expect(ReceiptIllustPainter.coralLine, const Color(0xFFFABBC1));
    });

    test('🔴 줄 위치·폭·여백이 시안 실측값이다', () {
      final tops = ReceiptIllustPainter.lineTops;
      final widths = ReceiptIllustPainter.lineWidths;
      final lefts = ReceiptIllustPainter.lineLefts;
      expect(tops, [0.1403, 0.2471, 0.3360, 0.4339, 0.5317]);
      expect(widths, [0.593, 0.630, 0.532, 0.581, 0.420]);
      expect(lefts, [0.1286, 0.1533, 0.1409, 0.1409, 0.1409]);
      expect(widths.length, tops.length);
      expect(lefts.length, tops.length);
      // 줄은 위에서 아래로 순서대로 내려가야 한다.
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]));
      }
      // 가운데 종이는 코랄 1 + 회색 4 = 5줄
      expect(ReceiptIllustPainter.papers.last.greyLines, 4);
    });

    test('🔴 줄이 종이 밖으로 삐져나가지 않는다', () {
      final widths = ReceiptIllustPainter.lineWidths;
      final lefts = ReceiptIllustPainter.lineLefts;
      for (var i = 0; i < widths.length; i++) {
        expect(lefts[i] + widths[i], lessThan(1.0),
            reason: '$i 번 줄이 종이 오른쪽 밖으로 나간다');
      }
      for (final p in ReceiptIllustPainter.papers) {
        expect(ReceiptIllustPainter.lineTops[p.greyLines], lessThan(1.0));
      }
    });

    test('🔴 종이가 일러스트 박스 안에 들어온다', () {
      for (final p in ReceiptIllustPainter.papers) {
        expect(p.left, greaterThanOrEqualTo(0.0));
        expect(p.top, greaterThanOrEqualTo(0.0));
        expect(p.left + p.width, lessThanOrEqualTo(1.0),
            reason: '종이가 박스 오른쪽으로 넘친다');
        expect(p.top + p.height, lessThanOrEqualTo(1.0),
            reason: '종이가 박스 아래로 넘친다');
      }
    });

    test('🔴 세 장이 서로 겹쳐 보인다 (떨어지면 부채가 아니다)', () {
      final p = ReceiptIllustPainter.papers;
      final left = p[0], right = p[1], center = p[2];
      // 가운데가 좌우를 각각 덮어야 한다.
      expect(center.left, lessThan(left.left + left.width),
          reason: '가운데와 왼쪽이 떨어져 있다');
      expect(center.left + center.width, greaterThan(right.left),
          reason: '가운데와 오른쪽이 떨어져 있다');
    });
  });
}
