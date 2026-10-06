/// 문서 저장 — 플랫폼별 구현 선택.
///
/// 만들어진 문서(PDF) 바이트를 **사용자가 실제로 꺼낼 수 있는 곳**에 넘긴다.
///
/// 안드로이드/iOS 와 웹은 "파일을 준다" 는 뜻이 완전히 다르다.
///
/// | | 저장 위치 | 사용자가 꺼내는 방법 |
/// |---|---|---|
/// | 앱 | 앱 문서 폴더에 파일로 씀 | `share_plus` → 카카오톡/메일 |
/// | 웹 | 브라우저 다운로드 | 다운로드 폴더에 바로 떨어짐 |
///
/// 🔴 웹에서 `path_provider` 를 쓸 수 없다.
///    `path_provider-2.1.5/pubspec.yaml` 의 `platforms:` 에
///    android/ios/linux/macos/windows 만 있고 **web 이 없다.**
///    그래서 웹에서 `getApplicationDocumentsDirectory()` 를 부르면
///    `MissingPluginException` 으로 정산서 만들기가 통째로 실패한다.
///
/// 조건부 export 로 플랫폼마다 다른 구현을 붙인다. 이렇게 하면
/// 웹 빌드에 `dart:io` 코드가, 앱 빌드에 `dart:js_interop` 코드가
/// 아예 들어가지 않는다.
library;

export 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';
