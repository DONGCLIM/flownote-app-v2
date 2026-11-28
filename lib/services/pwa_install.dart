/// "홈 화면에 추가" 안내를 위한 플랫폼 판별.
///
/// 웹에서만 의미가 있으므로 조건부 import 로 갈라둔다.
/// (네이티브 앱은 이미 설치된 상태라 안내 자체가 필요 없다)
library;

export 'pwa_install_stub.dart'
    if (dart.library.js_interop) 'pwa_install_web.dart';
