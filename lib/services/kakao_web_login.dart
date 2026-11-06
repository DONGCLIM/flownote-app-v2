/// 웹 카카오 로그인 (SDK 우회 · 직접 OAuth).
///
/// 네이티브에서는 SDK 경로가 정상이므로 stub 이 들어간다.
/// 우회가 필요한 이유는 `kakao_web_login_types.dart` 상단 참고.
library;

export 'kakao_web_login_stub.dart'
    if (dart.library.js_interop) 'kakao_web_login_web.dart';
