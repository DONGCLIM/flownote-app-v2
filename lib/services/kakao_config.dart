import 'package:flutter/foundation.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// 카카오 로그인에 필요한 앱 키를 담는 곳.
///
/// 🔴 키를 코드에 직접 적지 않는 이유
///    이 저장소는 공개되어 있다. 소스에 키를 박으면 누구나 우리 앱을
///    사칭하는 앱을 만들 수 있다. Gemini 키와 똑같은 방식으로
///    `secrets/kakao.json` 을 빌드할 때 주입한다.
///
///      1) cp secrets/kakao.example.json secrets/kakao.json
///      2) KAKAO_NATIVE_APP_KEY 를 채운다
///      3) ./tool/build_apk.sh --fat
///
/// 네이티브 앱 키는 원래 앱 안에 들어가는 값이라(스킴에도 노출된다)
/// 유출되어도 서버 키만큼 위험하지는 않다. 그래도 저장소에는 두지 않는다.
class KakaoConfig {
  KakaoConfig._();

  /// 카카오 개발자 콘솔 → 플랫폼 키 → 네이티브 앱 키 (Android/iOS 전용)
  static const String nativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '',
  );

  /// 카카오 개발자 콘솔 → 앱 키 → **JavaScript 키** (웹 전용)
  ///
  /// 🔴 웹은 네이티브 앱 키로 로그인할 수 없다.
  ///
  /// SDK 내부를 보면 이유가 명확하다
  /// (`kakao_flutter_sdk_common-1.10.0/lib/src/kakao_sdk.dart:23`):
  ///
  /// ```dart
  /// static String get appKey => kIsWeb ? _jsKey : _nativeKey;
  /// ```
  ///
  /// 웹에서는 `_jsKey` 만 본다. `KakaoSdk.init(nativeAppKey: ...)` 만
  /// 넘기면 `_jsKey` 가 빈 문자열이 되고, 카카오 인증 서버는 앱 키가
  /// 빈 요청을 받아 **KOE101 (앱 관리자 설정 오류)** 를 돌려준다.
  /// 사장님 화면에 뜬 그 오류가 정확히 이것이다.
  static const String javaScriptKey = String.fromEnvironment(
    'KAKAO_JS_KEY',
    defaultValue: '',
  );

  /// 지금 플랫폼에서 실제로 쓰이는 키.
  static String get activeKey => kIsWeb ? javaScriptKey : nativeAppKey;

  /// 이 플랫폼에서 카카오 로그인을 쓸 수 있는지.
  ///
  /// 키가 없으면 카카오 버튼은 "준비 중" 으로 남는다. 키 없이
  /// `UserApi.instance.login...` 을 부르면 카카오가 KOE101 을 돌려주는데,
  /// 사용자에게는 검은 화면의 낯선 에러 코드로만 보인다. 자기 계정
  /// 문제로 오해하게 만드는 것보다 버튼 단계에서 막는 게 낫다.
  static bool get isConfigured => activeKey.length >= 20;

  /// 웹에서 JS 키만 없는 상태인지. (안내 문구를 정확히 쓰기 위해 구분한다)
  static bool get isWebKeyMissing =>
      kIsWeb && javaScriptKey.isEmpty && nativeAppKey.isNotEmpty;

  static bool _inited = false;

  /// 앱 시작 시 한 번 호출. 로그인보다 반드시 먼저 실행돼야 한다.
  static void init() {
    if (_inited || !isConfigured) return;
    KakaoSdk.init(
      // 플랫폼마다 필요한 키만 넘긴다. 둘 다 넘겨도 SDK 가 알아서
      // 골라 쓰지만(위 getter), 없는 키를 빈 문자열로 넣으면
      // customScheme 기본값이 `kakao` 로 뭉개져서 헷갈린다.
      nativeAppKey: kIsWeb ? null : nativeAppKey,
      javaScriptAppKey: kIsWeb ? javaScriptKey : null,
      // 리다이렉트 스킴은 SDK 기본값(kakao{앱키})을 그대로 쓴다.
      // AndroidManifest / Info.plist 에 등록한 값과 동일해야 한다.
      loggingEnabled: kDebugMode,
    );
    _inited = true;
  }
}
