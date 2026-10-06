import 'package:flutter/foundation.dart';

/// Firebase 초기화 결과를 앱 전체에서 읽을 수 있게 보관한다.
///
/// **왜 필요한가**
/// 이전 코드는 `main()` 에서 `Firebase.initializeApp()` 이 실패하면
/// `if (kDebugMode) debugPrint(...)` 로만 남기고 그대로 버렸다.
/// 그 결과 릴리즈 APK 에서는
///
/// 1. 로그인 화면이 **완전히 정상처럼** 그려지고
/// 2. 아무 버튼을 눌러도 매번 같은 문구만 뜨거나 아무 일도 안 일어나고
/// 3. 진짜 원인(google-services.json 누락, 패키지명 불일치, 플러그인 초기화
///    실패 등)은 화면 어디에도 남지 않는다.
///
/// "또 로그인이 안 된다" 를 다시 추측으로 쫓지 않기 위해, 실패 사유를
/// 여기에 담아 두고 로그인 화면 상단 배너에 그대로 노출한다.
class FirebaseStatus {
  FirebaseStatus._();

  /// 초기화 시도 자체가 끝났는지 (성공/실패 무관).
  static bool attempted = false;

  /// `Firebase.initializeApp()` 이 성공했는지.
  static bool ready = false;

  /// 실패 사유 원문. 성공했으면 null.
  static String? errorDetail;

  /// 실패한 단계 이름 (`Firebase.initializeApp` / `AuthService.init` 등).
  static String? errorStage;

  static void markReady() {
    attempted = true;
    ready = true;
    errorDetail = null;
    errorStage = null;
  }

  static void markFailed(String stage, Object error) {
    attempted = true;
    ready = false;
    errorStage = stage;
    errorDetail = error.toString();
    if (kDebugMode) debugPrint('[Firebase] $stage 실패: $error');
  }

  /// 사용자에게 보여줄 한 줄 요약. 사유를 모르면 일반 안내.
  static String get userMessage {
    if (ready) return '';
    final detail = errorDetail;
    if (detail == null || detail.isEmpty) {
      return '로그인 서버에 연결할 수 없습니다.\n잠시 후 앱을 다시 실행해 주세요.';
    }
    return '로그인 서버 초기화에 실패했습니다.\n($errorStage) $detail';
  }
}
