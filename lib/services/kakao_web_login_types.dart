/// 웹 카카오 로그인 우회 경로가 주고받는 값들.
///
/// 🔴 왜 우회가 필요한가 — 실측으로 확정한 원인
///
/// `kakao_flutter_sdk` 의 웹 구현은 토큰 교환 요청에 `KA` 헤더를 붙이는데,
/// 그 값이 이렇게 **하드코딩** 되어 있다.
///
/// ```dart
/// // kakao_flutter_sdk_common/lib/src/web/kakao_flutter_sdk_plugin.dart:329
/// String _getKaHeader() {
///   return "os/javascript origin/${web.window.location.origin}";
/// }
/// ```
///
/// 이 `os/javascript` 토큰이 붙으면 카카오 서버가 "Javascript env
/// validation" 을 돌리는데, 우리 앱은 그걸 통과하지 못한다. 같은 요청에서
/// **`KA` 헤더만** 바꿔가며 실측한 결과가 아래다.
///
/// | KA 헤더                                              | 결과                    |
/// |------------------------------------------------------|-------------------------|
/// | `… os/javascript origin/https://flownote-404ef.web.app` | KOE009 misconfigured  |
/// | `… os/javascript origin/…firebaseapp.com`              | KOE009                |
/// | `… os/javascript origin/https://미등록도메인`            | KOE009                |
/// | `os/javascript` (origin 없음)                          | KOE009                |
/// | `sdk/1.10.0 sdk_type/flutter` (**os/ 없음**)           | KOE320 → **통과**     |
/// | `sdk_type/javascript` (**os/ 없음**)                   | KOE320 → **통과**     |
/// | **헤더 없음**                                          | KOE320 → **통과**     |
///
/// (KOE320 = "authorization code not found" — 가짜 code 를 보냈으니 정상
///  응답이다. 즉 **검증을 통과했다**는 뜻이다)
///
/// 핵심은 `origin` **값이 무엇이든 무관**하다는 점이다. `os/javascript` 가
/// 있느냐 없느냐만으로 갈린다. 그래서 콘솔에서 도메인을 아무리 고쳐도
/// 증상이 그대로였다. (사장님이 ask#87 스크린샷으로 보여주신 JavaScript
/// SDK 도메인·리다이렉트 URI 설정은 실제로 올바르게 되어 있었다)
///
/// 결론: **SDK 의 웹 로그인 경로를 쓰지 않는다.** 표준 OAuth 2.0
/// 리다이렉트를 우리가 직접 구현하면 `KA` 헤더가 아예 붙지 않으므로
/// 문제의 검증 자체가 발생하지 않는다.
///
/// 실측으로 확인한 우회로의 전제조건:
///   - `/oauth/authorize` : JS 키 + 등록된 `redirect_uri` → 302 정상
///   - `/oauth/token`     : JS 키 + `KA` 헤더 없음 → 검증 통과
///   - `/oauth/token` 응답에 `Access-Control-Allow-Origin: *` 이 있어서
///     **브라우저에서 직접 호출 가능** (별도 서버 중계가 필요 없다)
library;

/// 카카오에서 받아온 액세스 토큰.
///
/// 우리가 필요한 건 서버 함수에 넘길 액세스 토큰 하나뿐이다.
/// (신원 검증은 서버가 카카오에 직접 물어본다 — `auth_service` 주석 참고)
class KakaoWebToken {
  const KakaoWebToken(this.accessToken);

  final String accessToken;
}

/// 우회 로그인이 실패하는 사유.
///
/// 원인을 뭉개지 않기 위해 카카오가 준 원문을 그대로 들고 다닌다.
class KakaoWebLoginException implements Exception {
  const KakaoWebLoginException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      code == null ? message : '$message${code!.isEmpty ? '' : ' ($code)'}';
}

/// 사용자가 카카오 화면에서 취소를 눌렀다.
///
/// 오류가 아니므로 화면에 빨간 토스트를 띄우면 안 된다.
class KakaoWebLoginCancelled implements Exception {
  const KakaoWebLoginCancelled();
}
