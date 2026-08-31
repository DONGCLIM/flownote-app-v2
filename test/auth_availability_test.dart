import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/screens/ds/auth_unavailable_banner.dart';
import 'package:flow_note/services/firebase_status.dart';

/// 요청 #29 회귀 — "또 로그인이 안 된다" 를 다시 추측으로 쫓지 않기 위한 테스트.
///
/// 이전 버그: `Firebase.initializeApp()` 이 실패하면
///  - 사유가 `kDebugMode` 로그로만 남아 릴리즈에서 완전히 사라졌고
///  - 로그인 화면은 정상처럼 그려져서 눌러도 아무 일이 안 일어났다.
void main() {
  setUp(() {
    FirebaseStatus.attempted = false;
    FirebaseStatus.ready = false;
    FirebaseStatus.errorDetail = null;
    FirebaseStatus.errorStage = null;
  });

  tearDown(() {
    FirebaseStatus.attempted = false;
    FirebaseStatus.ready = false;
    FirebaseStatus.errorDetail = null;
    FirebaseStatus.errorStage = null;
  });

  group('FirebaseStatus — 초기화 실패 사유를 버리지 않는다', () {
    test('markFailed 는 단계와 사유를 모두 보관한다', () {
      FirebaseStatus.markFailed(
          'Firebase.initializeApp', Exception('no google-services.json'));

      expect(FirebaseStatus.attempted, isTrue);
      expect(FirebaseStatus.ready, isFalse);
      expect(FirebaseStatus.errorStage, 'Firebase.initializeApp');
      expect(FirebaseStatus.errorDetail, contains('google-services.json'));
      expect(FirebaseStatus.userMessage, contains('Firebase.initializeApp'));
      expect(FirebaseStatus.userMessage, contains('google-services.json'));
    });

    test('markReady 는 이전 실패 흔적을 지운다', () {
      FirebaseStatus.markFailed('Firebase.initializeApp', 'boom');
      FirebaseStatus.markReady();

      expect(FirebaseStatus.ready, isTrue);
      expect(FirebaseStatus.errorDetail, isNull);
      expect(FirebaseStatus.userMessage, isEmpty);
    });

    test('사유를 모르는 실패에도 사용자 안내 문구가 비지 않는다', () {
      FirebaseStatus.markFailed('Firebase.initializeApp', '');
      expect(FirebaseStatus.userMessage, isNotEmpty);
    });
  });

  group('AuthUnavailableBanner — 상태에 따라 정확히 켜지고 꺼진다', () {
    test('초기화 시도 전에는 차단하지 않는다 (테스트/초기 프레임)', () {
      expect(AuthUnavailableBanner.blocked, isFalse);
    });

    test('초기화 성공이면 차단하지 않는다', () {
      FirebaseStatus.markReady();
      expect(AuthUnavailableBanner.blocked, isFalse);
    });

    test('초기화 실패면 차단한다', () {
      FirebaseStatus.markFailed('Firebase.initializeApp', 'boom');
      expect(AuthUnavailableBanner.blocked, isTrue);
    });

    testWidgets('정상일 때 배너는 아무것도 그리지 않는다', (tester) async {
      FirebaseStatus.markReady();
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AuthUnavailableBanner())));

      expect(find.textContaining('로그인 서버에 연결되지 않았어요'), findsNothing);
    });

    testWidgets('실패 시 배너에 사유가 그대로 보인다', (tester) async {
      FirebaseStatus.markFailed(
          'Firebase.initializeApp', 'FirebaseException: 설정 파일 없음');
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AuthUnavailableBanner())));

      expect(find.textContaining('로그인 서버에 연결되지 않았어요'), findsOneWidget);
      expect(find.textContaining('설정 파일 없음'), findsOneWidget);
      expect(find.textContaining('Firebase.initializeApp'), findsOneWidget);
    });
  });
}
