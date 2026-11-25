import 'package:flutter/foundation.dart';

/// 게스트 흐름 기록. (#192)
///
/// 🔴 **아직 Firebase Analytics 에 붙이지 않았다.** `firebase_analytics`
///    패키지가 `pubspec.yaml` 에 없다. 패키지를 더하면 웹 설정(gtag)과
///    iOS/안드로이드 설정까지 함께 손봐야 해서, 이번에는 **부르는 자리만**
///    만들어 두고 실제 전송은 다음 작업으로 미뤘다.
///    (사장님께 보고함 — `docs/TODO_기능연결.md` 참고)
///
/// 지금은 디버그 로그만 남는다. 패키지를 붙이는 날 이 파일 안의
/// `_log` 한 곳만 고치면 모든 자리가 함께 살아난다. 부르는 쪽을
/// 나중에 찾아다니지 않아도 된다.
///
/// 남기는 것 — 사장님 지시(#192):
/// ```
///   guest_start      첫 방문 (게스트로 들어옴)
///   guest_first_scan 첫 스캔
///   guest_limit_hit  5장 다 씀
///   guest_signed_up  가입 완료
/// ```
class FnAnalytics {
  FnAnalytics._();

  static const String evGuestStart = 'guest_start';
  static const String evGuestFirstScan = 'guest_first_scan';
  static const String evGuestLimitHit = 'guest_limit_hit';
  static const String evGuestSignedUp = 'guest_signed_up';

  /// 게스트로 들어왔다.
  static Future<void> guestStart() => _log(evGuestStart);

  /// 체험 중 첫 영수증을 찍었다.
  static Future<void> guestFirstScan() => _log(evGuestFirstScan);

  /// 체험 5장을 다 썼다.
  static Future<void> guestLimitHit() => _log(evGuestLimitHit);

  /// 게스트가 정식 가입했다.
  static Future<void> guestSignedUp({String? method}) =>
      _log(evGuestSignedUp, {'method': method ?? ''});

  static Future<void> _log(String name, [Map<String, Object?>? params]) async {
    // 🔴 여기에 `FirebaseAnalytics.instance.logEvent(...)` 가 들어갈 자리다.
    if (kDebugMode) debugPrint('[Analytics] $name ${params ?? ''}');
  }
}
