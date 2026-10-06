import 'kakao_web_login_types.dart';

export 'kakao_web_login_types.dart';

/// 네이티브(안드로이드/iOS) 구현 — 아무것도 하지 않는다.
///
/// 🔴 네이티브에서는 SDK 경로가 **정상이다.** 문제가 되는
/// `os/javascript` KA 헤더는 웹 구현에서만 붙는다
/// (네이티브는 `os/android` / `os/ios`). 그래서 네이티브 쪽 로그인
/// 코드는 손대지 않고 그대로 둔다.
///
/// 이 파일은 조건부 import 의 짝을 맞추기 위한 껍데기다. 여기 함수가
/// 실제로 불릴 일은 없지만, 혹시 잘못 불렸을 때 조용히 실패해서
/// 원인을 감추지 않도록 명시적으로 예외를 던진다.
bool kakaoWebLoginReturning() => false;

Future<KakaoWebToken?> kakaoWebFinishRedirect() async => null;

Future<KakaoWebToken> kakaoWebLogin({required String javaScriptKey}) async {
  throw const KakaoWebLoginException(
    '이 경로는 웹에서만 사용합니다.',
    code: 'not-web',
  );
}

String? kakaoWebReturnPath() => null;
